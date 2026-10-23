BEGIN;
-- Preserve existing ownership and all EXECUTE grants. Never use CASCADE.
CREATE TEMP TABLE ngoda_cash_phone_acl ON COMMIT DROP AS
SELECT p.proname, pg_get_userbyid(p.proowner) AS owner_name,
       coalesce(p.proacl, acldefault('f',p.proowner)) AS saved_acl
FROM pg_proc p
WHERE p.oid IN (
 'public.create_my_transaction_state(jsonb,public."TransactionType")'::regprocedure,
 'public.cash_transfer(text,jsonb,public."TransactionType",text,text,text,text)'::regprocedure
);
DO $preflight$
BEGIN
 IF to_regprocedure('public.create_my_transaction_state(jsonb,public."TransactionType",text)') IS NOT NULL
 OR to_regprocedure('public.cash_transfer(text,jsonb,public."TransactionType",text,text,text,text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'NORMALIZED_RECEIVER_SIGNATURE_ALREADY_EXISTS_REVIEW_REQUIRED';
 END IF;
END;
$preflight$;
DROP FUNCTION public.create_my_transaction_state(jsonb,public."TransactionType");
DROP FUNCTION public.cash_transfer(text,jsonb,public."TransactionType",text,text,text,text);

CREATE OR REPLACE FUNCTION public.create_my_transaction_state(p_transaction jsonb, p_transaction_type "TransactionType", p_receiver_identifier text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user_id text;
    v_country_code text;
    v_transaction_id text;
    v_transaction_data jsonb;

    v_receiver_identifier text;
    v_state_user_id text;
    v_receiver public.users%rowtype;
begin
    /*
     * Authenticate the caller.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select
        u.id,
        u.country_code
    into
        v_user_id,
        v_country_code
    from public.users u
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_ACTIVE_OR_NOT_FOUND';
    end if;

    if nullif(btrim(v_country_code), '') is null then
        raise exception 'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Validate the request.
     */
    if p_transaction is null
       or jsonb_typeof(p_transaction) <> 'object'
    then
        raise exception 'TRANSACTION_DATA_IS_MISSING';
    end if;

    if p_transaction_type is null then
        raise exception 'TRANSACTION_TYPE_REQUIRED';
    end if;

    if nullif(btrim(p_transaction ->> 'r'), '') is null then
        raise exception 'TRANSACTION_REFERENCE_REQUIRED';
    end if;

    /*
     * Preserve the existing participant behavior for
     * other transaction types.
     */
    v_state_user_id := p_transaction ->> 's';

    /*
     * Cash transfer:
     *
     * The signed "s" field contains an email or phone.
     * transaction_state.user_id must contain users.id.
     *
     * Use the Edge-normalized identifier when supplied. Resolve the recipient without modifying the
     * signed transaction fields.
     */
    if p_transaction_type =
       'cash_transfer'::public."TransactionType"
    then
        v_receiver_identifier :=
            coalesce(nullif(btrim(p_receiver_identifier), ''),
                     nullif(btrim(p_transaction ->> 's'), ''));

        if v_receiver_identifier is null then
            raise exception 'RECEIVER_IDENTIFIER_MISSING';
        end if;

        v_receiver :=
            public.fetch_user_by_email_or_phone(
                v_receiver_identifier
            );

        if v_receiver.id is null then
            raise exception 'RECEIVER_NOT_FOUND';
        end if;

        if v_receiver.status is distinct from
           'active'::public."UserStatus"
        then
            raise exception 'RECEIVER_NOT_ACTIVE';
        end if;

        if v_receiver.id = v_user_id
           or v_receiver.country_code is distinct from
              v_country_code
        then
            raise exception 'OPERATION_NOT_ALLOWED';
        end if;

        v_state_user_id := v_receiver.id;

        /*
         * Do not require a receiver wallet here.
         * Posting creates it on first receipt if absent.
         */
    end if;

    v_transaction_id :=
        gen_random_uuid()::text;

    /*
     * Preserve the existing transaction-data structure
     * and the original signed field values.
     */
    v_transaction_data :=
        jsonb_build_object(
            'v', p_transaction -> 'v',
            'r', p_transaction -> 'r',
            's', p_transaction -> 's',
            'a', p_transaction -> 'a',
            'f', p_transaction -> 'f',
            'g', p_transaction -> 'g',
            'c', p_transaction -> 'c',
            't', p_transaction -> 't',
            'e', p_transaction -> 'e',
            'ms', p_transaction -> 'ms'
        );

    insert into public.transaction_state (
        id,
        reference,
        status,
        transaction_type,
        country_code,
        transaction_data,
        created_by,
        user_id,
        updated_at
    )
    values (
        v_transaction_id,
        p_transaction ->> 'r',
        'processing'::public."TransactionStatus",
        p_transaction_type,
        v_country_code,
        v_transaction_data,
        v_user_id,
        v_state_user_id,
        now()
    );

    return v_transaction_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$function$;

CREATE OR REPLACE FUNCTION public.cash_transfer(p_sender_id text, p_transaction jsonb, p_transaction_type "TransactionType", p_country_code text, p_transaction_state_id text, p_ip_address text DEFAULT NULL::text, p_fee_payment_method text DEFAULT 'cash'::text, p_receiver_identifier text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, reference text, financial_transaction_id text, amount text, amount_usd text, original_fee text, cash_fee text, cash_charges text, fee_payment_method text, points_redeemed bigint, redemption_ledger_id text, loyalty jsonb, currency text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text, receiver_id text, sender_debit text, sender_debit_usd text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare

v_decimals numeric := 100;

v_amount numeric;
v_amount_usd numeric(20, 6);
v_principal numeric;
v_currency text;
v_reference text;
v_receiver_identifier text;
v_fee_payment_method text;
v_rate_to_usd numeric;

/*
 * Actual sender wallet debit converted using the same
 * transaction-time exchange rate as the transfer amount.
 */
v_sender_debit_usd numeric(20, 6);

v_fiscal_year integer;
v_period integer;

v_receiver public.users%rowtype;
v_sender public.users%rowtype;
v_treasury public.users%rowtype;
v_transaction_state public.transaction_state%rowtype;

v_mappings
    public.transaction_gl_mapping[];

v_components
    public.posting_component[];

v_component_totals
    public.component_totals;

v_principal_amount numeric;
v_others_amount numeric;
v_original_fee numeric := 0;
v_cash_fee numeric := 0;
v_fee_amount_usd numeric(20, 6) := 0;

v_redemption_config
    public.loyalty_redemption_config%rowtype;

v_points_redeemed bigint := 0;
v_redemption_result jsonb;
v_redemption_ledger_id text;
v_loyalty_result jsonb;

v_sender_notification
    public.notification_message;

v_receiver_notification
    public.notification_message;

v_device_tokens text[] :=
    array[]::text[];

v_document_prefix text;
v_document_number text;

v_financial_transaction_id bigint;
v_receiver_notification_id text;

v_stage text := 'initialization';
v_error_state text;
v_error_message text;
v_error_detail text;
v_error_hint text;
v_error_context text;


begin

v_stage := 'validate service role';

if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
        errcode = '42501',
        message = 'SERVICE_ROLE_REQUIRED';
end if;


v_stage := 'validate transaction type';

if p_transaction_type <>
   'cash_transfer'::public."TransactionType"
then
    raise exception
        'INVALID_CASH_TRANSFER_TRANSACTION_TYPE_%',
        p_transaction_type;
end if;


v_fee_payment_method :=
    lower(
        coalesce(
            nullif(
                btrim(p_fee_payment_method),
                ''
            ),
            'cash'
        )
    );


if v_fee_payment_method not in (
    'cash',
    'points'
) then
    raise exception
        'INVALID_FEE_PAYMENT_METHOD';
end if;


/* ---------------------------------------------------------------------- */
/* VALIDATE AND LOCK TRANSACTION STATE                                    */
/* ---------------------------------------------------------------------- */

v_stage :=
    'validate and lock transaction state';


select transaction_state_record.*
into v_transaction_state
from public.transaction_state
    transaction_state_record
where transaction_state_record.id =
      p_transaction_state_id
  and transaction_state_record.created_by =
      p_sender_id
  and transaction_state_record.transaction_type =
      p_transaction_type
  and transaction_state_record.country_code =
      p_country_code
  and transaction_state_record.status =
      'processing'::public."TransactionStatus"
limit 1
for update;


if not found then
    raise exception
        'INVALID_TRANSACTION_STATE';
end if;


if v_transaction_state.transaction_data
   is distinct from p_transaction
then
    raise exception
        'TRANSACTION_STATE_DATA_MISMATCH';
end if;


/* ---------------------------------------------------------------------- */
/* PARSE TRANSACTION                                                      */
/* ---------------------------------------------------------------------- */

v_stage := 'parse transaction amount';


v_amount :=
    (p_transaction ->> 'a')::numeric /
    v_decimals;


if v_amount <= 0 then
    raise exception
        'INVALID_AMOUNT';
end if;


v_principal :=
    v_amount;


v_stage :=
    'parse transaction currency';


v_currency :=
    lower(
        nullif(
            btrim(
                p_transaction ->> 'c'
            ),
            ''
        )
    );


if v_currency is null then
    raise exception
        'CURRENCY_MISSING';
end if;


v_stage :=
    'parse transaction reference';


v_reference :=
    nullif(
        btrim(
            p_transaction ->> 'r'
        ),
        ''
    );


if v_reference is null then
    raise exception
        'REFERENCE_MISSING';
end if;


v_stage :=
    'parse receiver identifier';


v_receiver_identifier :=
    coalesce(nullif(btrim(p_receiver_identifier), ''),
             nullif(btrim(p_transaction ->> 's'), ''));


if v_receiver_identifier is null then
    raise exception
        'RECEIVER_IDENTIFIER_MISSING';
end if;


/* ---------------------------------------------------------------------- */
/* TRANSFER USD VALUE                                                     */
/* ---------------------------------------------------------------------- */

v_stage :=
    'calculate transfer USD amount';


if v_currency = 'usd' then

    v_rate_to_usd := 1;

    v_amount_usd :=
        round(
            v_amount,
            6
        );

else

    select
        rate_record.rate_to_usd
    into
        v_rate_to_usd
    from public.current_rates
        rate_record
    where lower(
        btrim(rate_record.code)
    ) = v_currency
    limit 1;


    if not found
       or v_rate_to_usd is null
       or v_rate_to_usd <= 0
    then
        raise exception
            'CURRENT_RATE_NOT_FOUND_%',
            upper(v_currency);
    end if;


    if v_currency = 'gold' then

        v_amount_usd :=
            round(
                v_amount *
                v_rate_to_usd,
                6
            );

    else

        v_amount_usd :=
            round(
                v_amount /
                v_rate_to_usd,
                6
            );

    end if;

end if;


if v_amount_usd <= 0 then
    raise exception
        'INVALID_TRANSFER_USD_AMOUNT';
end if;


/* ---------------------------------------------------------------------- */
/* GL MAPPINGS                                                            */
/* ---------------------------------------------------------------------- */

v_stage :=
    'fetch GL mappings';


select
    array_agg(mapping_row)
into
    v_mappings
from public.fetch_gl_mappings(
    p_transaction_type
) as mapping_row;


if v_mappings is null
   or cardinality(v_mappings) = 0
then
    raise exception
        'GL_MAPPINGS_NOT_FOUND';
end if;


/* ---------------------------------------------------------------------- */
/* POSTING COMPONENTS                                                     */
/* ---------------------------------------------------------------------- */

v_stage :=
    'build posting components';


v_components :=
    public.build_posting_components(
        p_transaction_type,
        v_principal,
        v_mappings,
        p_country_code,
        v_currency,
        false
    );


if v_components is null
   or cardinality(v_components) = 0
then
    raise exception
        'POSTING_COMPONENTS_NOT_FOUND';
end if;


/* ---------------------------------------------------------------------- */
/* ORIGINAL TRANSFER FEE                                                  */
/* ---------------------------------------------------------------------- */

v_stage :=
    'extract transfer fee';


select
    coalesce(
        component.credit_amount,
        0
    )
into
    v_original_fee
from unnest(v_components)
    as component(
        component_type,
        debit_amount,
        credit_amount
    )
where component.component_type =
      'transfer_fee'::public."ComponentType"
limit 1;


v_original_fee :=
    coalesce(
        v_original_fee,
        0
    );


if v_original_fee <= 0 then
    raise exception
        'INVALID_FEE_AMOUNT';
end if;


/* ---------------------------------------------------------------------- */
/* TRANSFER FEE USD                                                       */
/* ---------------------------------------------------------------------- */

if v_currency = 'usd' then

    v_fee_amount_usd :=
        round(
            v_original_fee,
            6
        );

elsif v_currency = 'gold' then

    v_fee_amount_usd :=
        round(
            v_original_fee *
            v_rate_to_usd,
            6
        );

else

    v_fee_amount_usd :=
        round(
            v_original_fee /
            v_rate_to_usd,
            6
        );

end if;


if v_fee_amount_usd <= 0 then
    raise exception
        'INVALID_TRANSFER_FEE_USD_AMOUNT';
end if;


/* ---------------------------------------------------------------------- */
/* POINT REDEMPTION                                                       */
/* ---------------------------------------------------------------------- */

/*
 * Resolve and apply all-or-nothing transfer-fee redemption.
 *
 * Other components, including government tax,
 * remain payable in cash.
 */

if v_fee_payment_method = 'points' then

    v_stage :=
        'resolve loyalty redemption config';


    select
        config_record.*
    into
        v_redemption_config
    from public.loyalty_redemption_config
        config_record
    where config_record.transaction_type =
          p_transaction_type

      and config_record.is_active = true

      and (
          config_record.country_code is null
          or config_record.country_code =
             lower(p_country_code)
      )

      and (
          config_record.currency_code is null
          or config_record.currency_code =
             v_currency
      )

      and (
          config_record.valid_from is null
          or config_record.valid_from <= now()
      )

      and (
          config_record.valid_until is null
          or config_record.valid_until > now()
      )

    order by

        case
            when config_record.country_code
                 is not null
            then 0
            else 1
        end,

        case
            when config_record.currency_code
                 is not null
            then 0
            else 1
        end,

        config_record.priority,
        config_record.id

    limit 1;


    if not found then
        raise exception
            'TRANSFER_FEE_POINT_REDEMPTION_NOT_AVAILABLE';
    end if;


    v_points_redeemed :=
        ceil(
            v_fee_amount_usd *
            v_redemption_config.points_per_usd
        )::bigint;


    if v_points_redeemed <= 0 then
        raise exception
            'INVALID_TRANSFER_FEE_POINTS';
    end if;


    /*
     * Remove transfer-fee component from the cash
     * posting and reduce the gross sender debit by
     * the same amount.
     */

    v_stage :=
        'apply loyalty fee discount to components';


    select
        array_agg(
            row(
                component.component_type,

                case
                    when component.component_type =
                         'principal'::public."ComponentType"
                    then
                        component.debit_amount -
                        v_original_fee
                    else
                        component.debit_amount
                end,

                component.credit_amount

            )::public.posting_component

            order by component.position
        )
    into
        v_components

    from unnest(v_components)
        with ordinality as component(
            component_type,
            debit_amount,
            credit_amount,
            position
        )

    where component.component_type <>
          'transfer_fee'::public."ComponentType";


    v_components :=
        public.validate_components(
            v_components
        );


    v_cash_fee := 0;

else

    v_cash_fee :=
        v_original_fee;

end if;


/* ---------------------------------------------------------------------- */
/* FINAL CASH TOTALS                                                      */
/* ---------------------------------------------------------------------- */

v_stage :=
    'extract final component totals';


v_component_totals :=
    public.extract_component_totals(
        v_components,
        false
    );


/*
 * IMPORTANT:
 *
 * This is the ACTUAL wallet debit for the sender.
 *
 * It contains:
 *
 * transfer principal
 * + charges still payable in cash
 *
 * If the transfer fee was redeemed with points,
 * that fee is no longer included.
 */

v_principal_amount :=
    v_component_totals.principal_amount;


v_others_amount :=
    v_component_totals.others_amount;


if v_principal_amount < v_amount then
    raise exception
        'INVALID_FINAL_TRANSFER_DEBIT';
end if;


/* ---------------------------------------------------------------------- */
/* SENDER ACTUAL DEBIT USD                                                */
/* ---------------------------------------------------------------------- */

/*
 * Financial Intelligence needs the USD equivalent
 * of the exact amount that was deducted from the
 * sender wallet.
 *
 * Use the SAME transaction-time rate already resolved
 * above. Do not fetch another exchange rate.
 */

v_stage :=
    'calculate sender debit USD';


if v_currency = 'usd' then

    v_sender_debit_usd :=
        round(
            v_principal_amount,
            6
        );

elsif v_currency = 'gold' then

    v_sender_debit_usd :=
        round(
            v_principal_amount *
            v_rate_to_usd,
            6
        );

else

    v_sender_debit_usd :=
        round(
            v_principal_amount /
            v_rate_to_usd,
            6
        );

end if;


if v_sender_debit_usd <= 0 then
    raise exception
        'INVALID_SENDER_DEBIT_USD_AMOUNT';
end if;


/* ---------------------------------------------------------------------- */
/* FISCAL PERIOD                                                          */
/* ---------------------------------------------------------------------- */

v_stage :=
    'fetch fiscal period';


select
    fiscal_period.fiscal_year,
    fiscal_period.period
into
    v_fiscal_year,
    v_period
from public.fetch_fiscal_period(
    p_country_code
) as fiscal_period;


if not found then
    raise exception
        'FISCAL_PERIOD_NOT_FOUND';
end if;


/* ---------------------------------------------------------------------- */
/* PARTICIPANTS                                                           */
/* ---------------------------------------------------------------------- */

v_stage :=
    'fetch receiver';


v_receiver :=
    public.fetch_user_by_email_or_phone(
        v_receiver_identifier
    );


-- The posting recipient must be the same user resolved during state creation.
if v_receiver.id is distinct from v_transaction_state.user_id then
    raise exception 'TRANSACTION_STATE_RECEIVER_MISMATCH';
end if;

v_stage :=
    'fetch sender';


v_sender :=
    public.fetch_user_by_id(
        p_sender_id
    );


v_stage :=
    'fetch country treasury';


v_treasury :=
    public.fetch_country_treasury(
        p_country_code
    );


/* ---------------------------------------------------------------------- */
/* PARTICIPANT VALIDATION                                                 */
/* ---------------------------------------------------------------------- */

v_stage :=
    'validate receiver status';


if v_receiver.status <>
   'active'::public."UserStatus"
then
    raise exception
        'RECEIVER_NOT_ACTIVE';
end if;


v_stage :=
    'validate sender status';


if v_sender.status <>
   'active'::public."UserStatus"
then
    raise exception
        'SENDER_NOT_ACTIVE';
end if;


if v_sender.id = v_receiver.id
   or v_sender.country_code is distinct from
      v_receiver.country_code
   or v_sender.country_code is distinct from
      p_country_code
then
    raise exception
        'OPERATION_NOT_ALLOWED';
end if;


/* ---------------------------------------------------------------------- */
/* NOTIFICATIONS                                                          */
/* ---------------------------------------------------------------------- */

v_stage :=
    'create sender notification';


v_sender_notification :=
    public.create_notification_message(
        p_country_code,
        p_transaction_type,
        'sender'::public."NotificationAudience",
        v_amount,
        upper(v_currency),
        v_reference || '-01',
        0,

        coalesce(
            v_sender.email,
            v_sender.phone,
            v_sender.id
        ),

        coalesce(
            v_receiver.email,
            v_receiver.phone,
            v_receiver.id
        ),
        p_fee => v_cash_fee,
        p_gross_amount => v_principal_amount
    );


v_stage :=
    'create receiver notification';


v_receiver_notification :=
    public.create_notification_message(
        p_country_code,
        p_transaction_type,
        'receiver'::public."NotificationAudience",
        v_amount,
        upper(v_currency),
        v_reference || '-02',
        0,

        coalesce(
            v_sender.email,
            v_sender.phone,
            v_sender.id
        ),

        coalesce(
            v_receiver.email,
            v_receiver.phone,
            v_receiver.id
        )
    );


v_stage :=
    'fetch receiver device tokens';


v_device_tokens :=
    coalesce(
        public.fetch_device_tokens(
            p_country_code,
            v_receiver.id
        ),
        array[]::text[]
    );


/* ---------------------------------------------------------------------- */
/* DOCUMENT NUMBER                                                        */
/* ---------------------------------------------------------------------- */

v_stage :=
    'fetch document number prefix';


v_document_prefix :=
    public.fetch_transaction_doc_num_prefix(
        p_transaction_type
    );


v_stage :=
    'generate document number';


v_document_number :=
    public.generate_document_number(
        v_document_prefix,
        v_fiscal_year,
        v_period,
        p_country_code
    );


/* ---------------------------------------------------------------------- */
/* FINANCIAL TRANSACTION                                                  */
/* ---------------------------------------------------------------------- */

v_stage :=
    'insert financial transaction';


insert into public.financial_transaction (
    document_number,
    fiscal_year,
    period,
    transaction_type,
    description,
    created_by,
    gross_amount,
    currency_code,
    reference,
    country_code
)
values (
    v_document_number,
    v_fiscal_year,
    v_period,
    p_transaction_type,

    'User transfer from ' ||
    coalesce(
        v_sender.email,
        v_sender.phone,
        v_sender.id
    ) ||
    ' to ' ||
    coalesce(
        v_receiver.email,
        v_receiver.phone,
        v_receiver.id
    ),

    p_sender_id,
    v_principal_amount,
    v_currency,
    v_reference,
    p_country_code
)
returning id
into v_financial_transaction_id;


/* ---------------------------------------------------------------------- */
/* REDEEM LOYALTY POINTS                                                  */
/* ---------------------------------------------------------------------- */

if v_fee_payment_method = 'points' then

    v_stage :=
        'redeem loyalty points';


    v_redemption_result :=
        public.redeem_loyalty_points_for_transfer_fee(
            p_sender_id,
            v_reference,
            v_financial_transaction_id::text,
            p_transaction_type,
            p_country_code,
            v_currency,
            v_original_fee,
            v_fee_amount_usd,
            v_points_redeemed,
            v_redemption_config.points_per_usd
        );


    v_redemption_ledger_id :=
        v_redemption_result ->>
        'ledger_id';


    if v_redemption_ledger_id is null then
        raise exception
            'LOYALTY_REDEMPTION_LEDGER_NOT_CREATED';
    end if;


    v_loyalty_result :=
        jsonb_build_object(

            'points_earned',
                0,

            'points_spent',
                coalesce(
                    (
                        v_redemption_result ->>
                        'points_redeemed'
                    )::bigint,
                    0
                ),

            'available_points',
                coalesce(
                    (
                        v_redemption_result ->>
                        'available_points'
                    )::bigint,
                    0
                ),

            'tier_points',
                coalesce(
                    (
                        v_redemption_result ->>
                        'tier_points'
                    )::bigint,
                    0
                ),

            'previous_level_code',
                v_redemption_result ->>
                'level_code',

            'level_code',
                v_redemption_result ->>
                'level_code',

            'level_changed',
                false
        );

end if;


/* ---------------------------------------------------------------------- */
/* FINANCIAL ENTRIES                                                      */
/* ---------------------------------------------------------------------- */

v_stage :=
    'post financial entries';


perform *
from public.post_financial_entries(

    p_document_number =>
        v_document_number,

    p_country_code =>
        p_country_code,

    p_transaction_id =>
        v_financial_transaction_id,

    p_transaction_type =>
        p_transaction_type,

    p_created_by =>
        p_sender_id,

    p_components =>
        v_components,

    p_mappings =>
        v_mappings,

    p_currency_code =>
        v_currency,

    p_fiscal_year =>
        v_fiscal_year,

    p_period =>
        v_period,

    p_reference =>
        v_reference,

    p_deposit_type =>
        null
);


/* ---------------------------------------------------------------------- */
/* WALLET ENTRIES                                                         */
/* ---------------------------------------------------------------------- */

v_stage :=
    'post wallet entries';


select
    result.receiver_notification_id
into
    v_receiver_notification_id
from public.post_wallet_entries(

    p_fiscal_year =>
        v_fiscal_year,

    p_period =>
        v_period,

    p_document_number =>
        v_document_number,

    p_reference =>
        v_reference,

    p_receiver_id =>
        v_receiver.id,

    p_sender_id =>
        p_sender_id,

    p_transaction_type =>
        p_transaction_type,

    /*
     * Receiver receives ONLY the entered transfer amount.
     */
    p_credit_amount =>
        v_amount,

    /*
     * Sender loses the transfer amount plus all remaining
     * charges payable in cash.
     */
    p_debit_amount =>
        v_principal_amount,

    p_sender_wallet_owner =>
        'customer'::public."WalletOwnerType",

    p_receiver_wallet_owner =>
        'customer'::public."WalletOwnerType",

    p_currency_code =>
        v_currency,

    p_country_code =>
        p_country_code,

    p_audit_action_type =>
        'cash_transferred'::public."AuditActionType",

    p_treasury_id =>
        v_treasury.id,

    p_fee_amount =>
        v_cash_fee,

    p_ip_address =>
        p_ip_address,

    p_receiver_notification =>
        v_receiver_notification,

    p_sender_notification =>
        v_sender_notification

) as result;


/* ---------------------------------------------------------------------- */
/* TRANSACTION SUCCESS                                                    */
/* ---------------------------------------------------------------------- */

v_stage :=
    'update transaction state';


update public.transaction_state
set
    user_id =
        v_receiver.id,

    status =
        'success'::public."TransactionStatus",

    message =
        null,

    updated_at =
        now()

where id =
      p_transaction_state_id

  and created_by =
      p_sender_id

  and transaction_type =
      p_transaction_type

  and status =
      'processing'::public."TransactionStatus";


if not found then
    raise exception
        'TRANSACTION_STATE_UPDATE_FAILED';
end if;


/* ---------------------------------------------------------------------- */
/* RETURN                                                                 */
/* ---------------------------------------------------------------------- */

v_stage :=
    'return cash transfer result';


return query
select
    true,

    v_reference,

    v_financial_transaction_id::text,

    /*
     * Amount received by receiver.
     */
    v_amount::text,

    v_amount_usd::text,

    v_original_fee::text,

    v_cash_fee::text,

    v_others_amount::text,

    v_fee_payment_method,

    v_points_redeemed,

    v_redemption_ledger_id,

    v_loyalty_result,

    v_currency,

    v_receiver_notification_id,

    v_device_tokens,

    v_receiver_notification.title,

    v_receiver_notification.body,

    v_receiver_notification.payload
        ->> 'reference',

    /*
     * ----------------------------------------------------------
     * Financial Intelligence
     * ----------------------------------------------------------
     */

    /*
     * Resolved user ID, not transaction.s email/phone.
     */
    v_receiver.id,

    /*
     * Exact sender wallet debit.
     */
    v_principal_amount::text,

    /*
     * Exact sender wallet debit in USD.
     */
    v_sender_debit_usd::text;


exception
when others then

    get stacked diagnostics

        v_error_state =
            returned_sqlstate,

        v_error_message =
            message_text,

        v_error_detail =
            pg_exception_detail,

        v_error_hint =
            pg_exception_hint,

        v_error_context =
            pg_exception_context;


    raise exception using

        errcode =
            v_error_state,

        message =
            format(
                'CASH_TRANSFER_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

        detail =
            coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(
                            v_error_detail,
                            ''
                        ),
                        nullif(
                            v_error_context,
                            ''
                        )
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),

        hint =
            coalesce(
                nullif(
                    v_error_hint,
                    ''
                ),
                'Check the cash-transfer stage reported in the error'
            );

end;

$function$;

DO $permissions$
DECLARE r record; g record; current_grant record; signature text; role_name text;
BEGIN
 FOR r IN SELECT * FROM pg_temp.ngoda_cash_phone_acl LOOP
  signature := CASE r.proname
   WHEN 'create_my_transaction_state' THEN 'public.create_my_transaction_state(jsonb,public."TransactionType",text)'
   ELSE 'public.cash_transfer(text,jsonb,public."TransactionType",text,text,text,text,text)' END;
  EXECUTE format('ALTER FUNCTION %s OWNER TO %I',signature,r.owner_name);
  -- Remove newly inherited default grants before restoring the original ACL.
  FOR current_grant IN SELECT DISTINCT a.grantee
   FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=signature::regprocedure LOOP
   role_name := CASE WHEN current_grant.grantee=0 THEN 'PUBLIC'
    ELSE quote_ident(pg_get_userbyid(current_grant.grantee)) END;
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',signature,role_name);
  END LOOP;
  FOR g IN SELECT * FROM aclexplode(r.saved_acl) LOOP
   role_name := CASE WHEN g.grantee=0 THEN 'PUBLIC'
    ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',g.privilege_type,signature,role_name,
    CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
END;
$permissions$;
COMMIT;
