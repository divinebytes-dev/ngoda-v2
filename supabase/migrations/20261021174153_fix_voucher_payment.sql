-- Complete replacement for complete_voucher_payment(), retaining its signature.
-- Run as one transaction in the QA SQL Editor.
-- Voucher payments remain merchant_payment, with payment fee always zero.
-- The authenticated wrapper and voucher-payment Edge need no fee flag.
BEGIN;
DO $guard$
BEGIN
    IF to_regprocedure('public.complete_voucher_payment(text,jsonb,jsonb,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'CURRENT_VOUCHER_PAYMENT_FUNCTION_NOT_FOUND';
    END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.complete_voucher_payment(p_merchant_id text, p_transaction jsonb, p_voucher jsonb, p_country_code text, p_transaction_state_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, reference text, customer_id text, gross_amount text, fee text, currency text, voucher_remaining_balance text, notification_id text, device_tokens text[], push_title text, push_body text, push_reference text, gross_amount_usd text, voucher_owner_debit_amount text, voucher_owner_debit_amount_usd text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_transaction_type
        public."TransactionType" :=
            'merchant_payment'::public."TransactionType";

    v_stage text :=
        'initialization';

    v_merchant
        public.users%rowtype;

    v_voucher_owner
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_transaction_reference text;

    v_voucher_reference text;

    v_voucher_owner_id text;

    v_currency text;

    v_amount numeric;

    v_voucher_total numeric;

    v_voucher_used numeric :=
        0;

    v_voucher_available numeric :=
        0;

    v_voucher_remaining numeric :=
        0;


    /*
     * ========================================================
     * USD VALUES
     * ========================================================
     */
    v_rate_to_usd numeric;

    v_amount_usd
        numeric(20, 6);

    v_voucher_owner_debit_usd
        numeric(20, 6);


    v_fiscal_year integer;

    v_period integer;


    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_component_totals
        public.component_totals;


    v_principal_amount numeric :=
        0;

    v_others_amount numeric :=
        0;

    v_fee numeric :=
        0;


    v_merchant_commission_rate numeric :=
        0;

    v_merchant_commission_amount numeric :=
        0;


    v_document_prefix text;

    v_document_number text;

    v_financial_transaction_id bigint;


    v_voucher_usage_id text;


    v_sender_notification
        public.notification_message;

    v_receiver_notification
        public.notification_message;


    v_receiver_notification_id text;

    v_voucher_owner_notification_id text;


    v_device_tokens text[] :=
        array[]::text[];


    v_error_state text;

    v_error_message text;

    v_error_detail text;

    v_error_hint text;

    v_error_context text;

begin
    /*
     * ========================================================
     * VALIDATE TRANSACTION STATE
     * ========================================================
     */

    v_stage :=
        'validate and lock transaction state';


    perform 1
    from public.transaction_state
        state_record
    where state_record.id =
          p_transaction_state_id
      and state_record.created_by =
          p_merchant_id
      and state_record.transaction_type =
          v_transaction_type
      and state_record.status =
          'processing'::public."TransactionStatus"
      and state_record.country_code =
          p_country_code
      and state_record.transaction_data =
          p_transaction
      and state_record.sender_approval =
          p_voucher
    for update;


    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;


    /*
     * The service-role client may ultimately call this through
     * the authenticated wrapper, therefore validate the supplied
     * merchant ID rather than relying on auth.uid().
     */
    v_stage :=
        'validate merchant role';


    if not public.user_has_role(
        p_merchant_id,
        array[
            'merchant',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;


    /*
     * ========================================================
     * VALIDATE VERSIONS
     * ========================================================
     */

    v_stage :=
        'validate transaction version';


    if p_transaction ->> 'v'
       is distinct from
       'v0'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    v_stage :=
        'validate voucher version';


    if p_voucher ->> 'v'
       is distinct from
       'v0'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    /*
     * ========================================================
     * PARSE TRANSACTION AND VOUCHER
     * ========================================================
     */

    v_stage :=
        'parse transaction reference';


    v_transaction_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );


    if v_transaction_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;


    v_stage :=
        'parse voucher reference';


    v_voucher_reference :=
        nullif(
            btrim(
                p_voucher ->> 'r'
            ),
            ''
        );


    if v_voucher_reference is null then
        raise exception
            'VOUCHER_REFERENCE_MISSING';
    end if;


    /*
     * transaction.s contains the voucher reference.
     */
    if nullif(
        btrim(
            p_transaction ->> 's'
        ),
        ''
    ) is distinct from
       v_voucher_reference
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;


    v_stage :=
        'parse voucher owner';


    v_voucher_owner_id :=
        nullif(
            btrim(
                p_voucher ->> 's'
            ),
            ''
        );


    if v_voucher_owner_id is null then
        raise exception
            'VOUCHER_OWNER_ID_MISSING';
    end if;


    v_stage :=
        'parse currency';


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


    if v_currency
       is distinct from
       lower(
           nullif(
               btrim(
                   p_voucher ->> 'c'
               ),
               ''
           )
       )
    then
        raise exception
            'CURRENCY_MISMATCH';
    end if;


    v_stage :=
        'parse payment amount';


    begin
        v_amount :=
            (
                p_transaction ->> 'a'
            )::numeric /
            100;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_AMOUNT';
    end;


    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;


    v_stage :=
        'parse voucher total';


    begin
        v_voucher_total :=
            (
                p_voucher ->> 'a'
            )::numeric /
            100;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_VOUCHER_AMOUNT';
    end;


    if v_voucher_total <= 0 then
        raise exception
            'INVALID_VOUCHER_AMOUNT';
    end if;


    /*
     * ========================================================
     * FETCH AND VALIDATE USERS
     * ========================================================
     */

    v_stage :=
        'fetch merchant';


    v_merchant :=
        public.fetch_user_by_id(
            p_merchant_id
        );


    v_stage :=
        'fetch voucher owner';


    v_voucher_owner :=
        public.fetch_user_by_id(
            v_voucher_owner_id
        );


    v_stage :=
        'fetch treasury';


    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );


    if v_merchant.id is null then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;


    if v_voucher_owner.id is null then
        raise exception
            'VOUCHER_OWNER_NOT_FOUND';
    end if;


    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;


    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;


    if v_voucher_owner.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'VOUCHER_OWNER_NOT_ACTIVE';
    end if;


    if v_merchant.id =
       v_voucher_owner.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    if v_merchant.country_code
       is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    if v_voucher_owner.country_code
       is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    /*
     * Confirm the transaction state belongs to the voucher
     * owner.
     */
    perform 1
    from public.transaction_state
        state_record
    where state_record.id =
          p_transaction_state_id
      and state_record.user_id =
          v_voucher_owner.id;


    if not found then
        raise exception
            'VOUCHER_OWNER_MISMATCH';
    end if;


    /*
     * ========================================================
     * FETCH POSTING CONFIGURATION
     * ========================================================
     */

    v_stage :=
        'fetch GL mappings';


    select
        array_agg(
            mapping_record
        )
    into
        v_mappings
    from public.fetch_gl_mappings(
        v_transaction_type
    ) as mapping_record;


    if v_mappings is null
       or cardinality(
           v_mappings
       ) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;


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


    if not found
       or v_fiscal_year is null
       or v_period is null
    then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;


    v_stage :=
        'build posting components';


    v_components :=
        public.build_posting_components(
            v_transaction_type,
            v_amount,
            v_mappings,
            p_country_code,
            v_currency,
            false
        );


    if v_components is null
       or cardinality(
           v_components
       ) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;


    /*
     * Voucher payments never charge the optional payment fee.
     * As in merchant payment with contribution=false, remove its
     * component and reduce the gross principal debit by that fee.
     * Keep other component amounts and the merchant credit unchanged.
     */
    v_stage := 'remove voucher payment fee';

    select coalesce(sum(greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )), 0)
    into v_fee
    from unnest(v_components) as component_record
    where component_record.component_type =
          'payment_fee'::public."ComponentType";

    select array_agg(
        row(
            component_record.component_type,
            case
                when component_record.component_type =
                     'principal'::public."ComponentType"
                then component_record.debit_amount - v_fee
                else component_record.debit_amount
            end,
            component_record.credit_amount
        )::public.posting_component
        order by component_record.position
    )
    into v_components
    from unnest(v_components) with ordinality as component_record(
        component_type, debit_amount, credit_amount, position
    )
    where component_record.component_type <>
          'payment_fee'::public."ComponentType";

    select array_agg(mapping_record order by mapping_record.component_type)
    into v_mappings
    from unnest(v_mappings) as mapping_record
    where mapping_record.component_type <>
          'payment_fee'::public."ComponentType";

    if v_components is null or cardinality(v_components) = 0 then
        raise exception 'VOUCHER_PAYMENT_COMPONENTS_NOT_FOUND';
    end if;

    if exists (
        select 1 from unnest(v_components) as component_record
        where component_record.debit_amount < 0
           or component_record.credit_amount < 0
    ) then
        raise exception 'INVALID_VOUCHER_PAYMENT_COMPONENT_AMOUNT';
    end if;

    v_components := public.validate_components(v_components);
    v_fee := 0;

    v_stage :=
        'extract component totals';


    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );


    v_principal_amount :=
        coalesce(
            v_component_totals
                .principal_amount,
            0
        );


    v_others_amount :=
        coalesce(
            v_component_totals
                .others_amount,
            0
        );


    if v_principal_amount <= 0 then
        raise exception
            'INVALID_PRINCIPAL_AMOUNT';
    end if;


    -- v_fee remains zero for every voucher payment.

    /*
     * ========================================================
     * CALCULATE USD VALUES
     * ========================================================
     *
     * Use exactly the same FX convention as the current
     * merchant-payment implementation.
     *
     * current_rates.rate_to_usd represents local-currency units
     * per USD, therefore local amounts are divided by the rate.
     *
     * v_amount:
     *     qualifying merchant-purchase / spending amount
     *
     * v_principal_amount:
     *     exact voucher-owner wallet debit
     */
    v_stage :=
        'calculate voucher payment USD values';


    if lower(
        v_currency
    ) = 'usd'
    then
        v_amount_usd :=
            round(
                v_amount,
                6
            );


        v_voucher_owner_debit_usd :=
            round(
                v_principal_amount,
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
            btrim(
                rate_record.code
            )
        ) =
        lower(
            v_currency
        )
        limit 1;


        if not found
           or v_rate_to_usd is null
           or v_rate_to_usd <= 0
        then
            raise exception
                'CURRENT_RATE_NOT_FOUND_%',
                upper(
                    v_currency
                );
        end if;


        /*
         * Voucher merchant payments support fiat currencies,
         * matching normal merchant payment.
         */
        v_amount_usd :=
            round(
                v_amount /
                v_rate_to_usd,
                6
            );


        v_voucher_owner_debit_usd :=
            round(
                v_principal_amount /
                v_rate_to_usd,
                6
            );
    end if;


    if v_amount_usd <= 0 then
        raise exception
            'INVALID_VOUCHER_PAYMENT_USD_AMOUNT';
    end if;


    if v_voucher_owner_debit_usd <= 0 then
        raise exception
            'INVALID_VOUCHER_PAYMENT_DEBIT_USD_AMOUNT';
    end if;


    /*
     * ========================================================
     * MERCHANT COMMISSION
     * ========================================================
     */

    v_stage :=
        'fetch merchant commission rate';


    v_merchant_commission_rate :=
        coalesce(
            public.fetch_merchant_commission_rate(
                v_transaction_type,
                v_currency,
                p_country_code
            ),
            0
        );


    if v_merchant_commission_rate < 0 then
        raise exception
            'INVALID_MERCHANT_COMMISSION_RATE';
    end if;


    if v_fee > 0
       and
       v_merchant_commission_rate > 0
    then
        v_merchant_commission_amount :=
            trunc(
                (
                    v_fee *
                    v_merchant_commission_rate
                ) /
                100,
                6
            );
    else
        v_merchant_commission_amount :=
            0;
    end if;


    /*
     * ========================================================
     * LOCK AND VALIDATE VOUCHER BALANCE
     * ========================================================
     */

    v_stage :=
        'acquire voucher lock';


    perform
        pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                v_voucher_reference,
                0
            )
        );


    v_stage :=
        'calculate voucher balance';


    v_voucher_used :=
        public.fetch_voucher_used_amount(
            v_voucher_reference
        );


    v_voucher_available :=
        v_voucher_total -
        coalesce(
            v_voucher_used,
            0
        );


    /*
     * The voucher covers the complete wallet debit.
     */
    if v_principal_amount >
       v_voucher_available
    then
        raise exception
            'VOUCHER_BALANCE_NOT_ENOUGH_[% %]',
            upper(
                v_currency
            ),
            trim_scale(
                greatest(
                    v_voucher_available,
                    0
                )
            );
    end if;


    v_voucher_remaining :=
        v_voucher_available -
        v_principal_amount;


    /*
     * ========================================================
     * CREATE VOUCHER USAGE
     * ========================================================
     */

    v_stage :=
        'create voucher usage';


    insert into public.voucher_usage (
        voucher_reference,
        reference,
        status,
        merchant_id,
        debit,
        credit,
        voucher_data,
        transaction_data
    )
    values (
        v_voucher_reference,
        v_transaction_reference,
        'processing'::public."TransactionStatus",
        v_merchant.id,
        v_principal_amount,
        0,
        p_voucher,
        p_transaction
    )
    returning
        id::text
    into
        v_voucher_usage_id;


    /*
     * ========================================================
     * BUILD NOTIFICATIONS
     * ========================================================
     */

    v_stage :=
        'create voucher owner notification';


    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            v_transaction_type,
            'sender'::public."NotificationAudience",
            v_principal_amount,
            upper(
                v_currency
            ),
            v_transaction_reference ||
            '-01',
            0,
            coalesce(
                v_voucher_owner.email,
                v_voucher_owner.phone,
                v_voucher_owner.id
            ),
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        );


    v_stage :=
        'create merchant notification';


    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            v_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(
                v_currency
            ),
            v_transaction_reference ||
            '-02',
            0,
            coalesce(
                v_voucher_owner.email,
                v_voucher_owner.phone,
                v_voucher_owner.id
            ),
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        );


    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_voucher_owner.id
            ),
            array[]::text[]
        );


    /*
     * ========================================================
     * GENERATE DOCUMENT NUMBER
     * ========================================================
     */

    v_stage :=
        'fetch document prefix';


    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );


    if v_document_prefix is null
       or btrim(
           v_document_prefix
       ) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;


    v_stage :=
        'generate document number';


    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );


    /*
     * ========================================================
     * FINANCIAL TRANSACTION
     * ========================================================
     */

    v_stage :=
        'create financial transaction';


    insert into public.financial_transaction (
        fiscal_year,
        period,
        document_number,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reference,
        country_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_document_number,
        v_transaction_type,
        'Voucher payment from ' ||
        coalesce(
            v_voucher_owner.email,
            v_voucher_owner.phone,
            v_voucher_owner.id
        ) ||
        ' to merchant ' ||
        coalesce(
            v_merchant.email,
            v_merchant.phone,
            v_merchant.id
        ),
        v_merchant.id,
        v_principal_amount,
        v_currency,
        v_transaction_reference,
        p_country_code
    )
    returning
        id
    into
        v_financial_transaction_id;


    /*
     * ========================================================
     * POST FINANCIAL ENTRIES
     * ========================================================
     */

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
            v_transaction_type,

        p_created_by =>
            v_merchant.id,

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
            v_transaction_reference,

        p_deposit_type =>
            null
    );


    /*
     * ========================================================
     * POST WALLET ENTRIES
     * ========================================================
     *
     * Voucher owner:
     *     debit = v_principal_amount
     *
     * Merchant:
     *     credit = v_amount
     *
     * Therefore v_principal_amount is the exact FI cash/savings
     * outflow for the voucher owner.
     */

    v_stage :=
        'post wallet entries';


    select
        posting_result
            .receiver_notification_id
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
            v_transaction_reference,

        p_receiver_id =>
            v_merchant.id,

        p_sender_id =>
            v_voucher_owner.id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            v_amount,

        p_debit_amount =>
            v_principal_amount,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'merchant'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            'merchant_payment'::public."AuditActionType",

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            v_fee,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification
    ) as posting_result;


    /*
     * Find the voucher-owner notification inserted as the
     * sender notification by post_wallet_entries.
     */
    v_stage :=
        'fetch voucher owner notification';


    select
        notification_record.id::text
    into
        v_voucher_owner_notification_id
    from public.notifications
        notification_record
    where notification_record.user_id =
          v_voucher_owner.id
      and notification_record.reference =
          (
              v_sender_notification.payload
              ->> 'reference'
          )
    limit 1;


    /*
     * ========================================================
     * MERCHANT COMMISSION
     * ========================================================
     */

    if v_merchant_commission_amount > 0 then
        v_stage :=
            'create merchant commission';


        insert into public.merchant_commission (
            merchant_id,
            document_number,
            fiscal_year,
            period,
            transaction_type,
            currency_code,
            amount,
            fee_amount,
            commission_rate,
            commission_amount,
            is_settled,
            country_code
        )
        values (
            v_merchant.id,
            v_document_number,
            v_fiscal_year,
            v_period,
            v_transaction_type,
            v_currency,
            v_amount,
            v_fee,
            v_merchant_commission_rate,
            v_merchant_commission_amount,
            false,
            p_country_code
        );
    end if;


    /*
     * ========================================================
     * COMPLETE VOUCHER USAGE
     * ========================================================
     */

    v_stage :=
        'complete voucher usage';


    update public.voucher_usage
    set
        status =
            'success'::public."TransactionStatus",

        message =
            null
    where id::text =
          v_voucher_usage_id
      and status =
          'processing'::public."TransactionStatus";


    if not found then
        raise exception
            'VOUCHER_USAGE_UPDATE_FAILED';
    end if;


    /*
     * ========================================================
     * COMPLETE TRANSACTION STATE
     * ========================================================
     */

    v_stage :=
        'complete transaction state';


    update public.transaction_state
    set
        user_id =
            v_voucher_owner.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_merchant_id
      and transaction_type =
          v_transaction_type
      and status =
          'processing'::public."TransactionStatus";


    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;


    /*
     * ========================================================
     * RESULT
     * ========================================================
     *
     * Loyalty:
     *
     * gross_amount
     * gross_amount_usd
     *
     * Financial Intelligence:
     *
     * spending:
     *     gross_amount / gross_amount_usd
     *
     * cash/savings outflow:
     *     voucher_owner_debit_amount /
     *     voucher_owner_debit_amount_usd
     */

    v_stage :=
        'return result';


    return query
    select
        true,

        v_transaction_reference,

        v_voucher_owner.id,

        trim_scale(
            v_amount
        )::text,

        trim_scale(
            v_fee
        )::text,

        v_currency,

        trim_scale(
            v_voucher_remaining
        )::text,

        v_voucher_owner_notification_id,

        v_device_tokens,

        v_sender_notification.title,

        v_sender_notification.body,

        v_sender_notification.payload
            ->> 'reference',

        /*
         * USD equivalent of merchant purchase amount.
         */
        trim_scale(
            v_amount_usd
        )::text,

        /*
         * Exact voucher-owner wallet debit.
         */
        trim_scale(
            v_principal_amount
        )::text,

        /*
         * USD equivalent of exact voucher-owner wallet debit.
         */
        trim_scale(
            v_voucher_owner_debit_usd
        )::text;


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
                    'VOUCHER_PAYMENT_FAILED at [%s]: %s',
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
                    'Check the Voucher Payment stage reported in the error'
                );

end;
$function$;

COMMIT;
