/*
 * ============================================================
 * COMPLETE MERCHANT PAYMENT
 * ============================================================
 */

create or replace function public.complete_merchant_payment(
    p_payer_id text,
    p_transaction jsonb,
    p_approval jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    document_number text,
    amount text,
    payment_fee text,
    currency_code text,

    receiver_notification_id text,
    device_tokens text[],

    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_preparation record;

    v_payer public.users%rowtype;
    v_merchant public.users%rowtype;

    v_sender_notification
        public.notification_message;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;

    v_reference text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the Edge Function's service-role client may
     * execute privileged payment posting.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    /*
     * Recalculate all trusted values.
     *
     * prepare_merchant_payment also locks the processing
     * transaction state.
     */
    v_stage :=
        'prepare merchant payment';

    select preparation_record.*
    into v_preparation
    from public.prepare_merchant_payment(
        p_payer_id,
        p_transaction,
        p_approval,
        p_country_code,
        p_transaction_state_id
    ) as preparation_record;

    if not found then
        raise exception
            'MERCHANT_PAYMENT_PREPARATION_NOT_FOUND';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    /*
     * Fetch payer and merchant for descriptions and
     * notification messages.
     */
    v_stage :=
        'fetch payment users';

    v_payer :=
        public.fetch_user_by_id(
            v_preparation.payer_id
        );

    v_merchant :=
        public.fetch_user_by_id(
            v_preparation.merchant_id
        );

    if v_payer.id is null then
        raise exception
            'PAYER_NOT_FOUND';
    end if;

    if v_merchant.id is null then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    /*
     * Sender notification belongs to the payer.
     */
    v_stage :=
        'create payer notification';

    v_sender_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'merchant_payment'::public."TransactionType",
            'sender'::public."NotificationAudience",
            v_preparation.payer_debit_amount::numeric,
            upper(
                v_preparation.currency_code
            ),
            v_reference || '-01',
            0,
            'Ngoda',
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        );

    /*
     * Receiver notification belongs to the merchant.
     */
    v_stage :=
        'create merchant notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'merchant_payment'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.merchant_credit_amount::numeric,
            upper(
                v_preparation.currency_code
            ),
            v_reference || '-02',
            0,
            coalesce(
                v_payer.email,
                v_payer.phone,
                v_payer.id
            ),
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        );

    /*
     * Fetch merchant push-notification tokens.
     */
    v_stage :=
        'fetch merchant device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_merchant.id
            ),
            array[]::text[]
        );

    /*
     * Generate the document number using the configured
     * prefix returned by prepare_merchant_payment.
     */
    v_stage :=
        'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    if v_document_number is null
       or btrim(
           v_document_number
       ) = ''
    then
        raise exception
            'DOCUMENT_NUMBER_GENERATION_FAILED';
    end if;

    /*
     * Create financial transaction header.
     */
    v_stage :=
        'insert financial transaction';

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
        v_preparation.fiscal_year,
        v_preparation.period,
        v_document_number,
        'merchant_payment'::public."TransactionType",
        'User ' ||
        coalesce(
            v_payer.email,
            v_payer.phone,
            v_payer.id
        ) ||
        ' pays merchant ' ||
        coalesce(
            v_merchant.email,
            v_merchant.phone,
            v_merchant.id
        ),
        v_payer.id,
        v_preparation.payer_debit_amount::numeric,
        v_preparation.currency_code,
        v_reference,
        v_preparation.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post Merchant Payment GL entries.
     */
    v_stage :=
        'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'merchant_payment'::public."TransactionType",

        p_created_by =>
            v_payer.id,

        p_components =>
            v_preparation.components,

        p_mappings =>
            v_preparation.mappings,

        p_currency_code =>
            v_preparation.currency_code,

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );

    /*
     * Wallet movement:
     *
     * Payer customer wallet:
     *   debit configured principal amount
     *
     * Merchant wallet:
     *   credit purchase amount
     *
     * Treasury wallet:
     *   credit payment fee
     */
    v_stage :=
        'post wallet entries';

    select wallet_result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_merchant.id,

        p_sender_id =>
            v_payer.id,

        p_transaction_type =>
            'merchant_payment'::public."TransactionType",

        p_credit_amount =>
            v_preparation.merchant_credit_amount::numeric,

        p_debit_amount =>
            v_preparation.payer_debit_amount::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'merchant'::public."WalletOwnerType",

        p_currency_code =>
            v_preparation.currency_code,

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'merchant_payment'::public."AuditActionType",

        p_treasury_id =>
            v_preparation.treasury_id,

        p_fee_amount =>
            v_preparation.payment_fee::numeric,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification
    ) as wallet_result;

    /*
     * Record the merchant's share of the payment fee.
     */
    v_stage :=
        'insert merchant commission';

    if v_preparation.payment_fee::numeric > 0 then
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
            v_preparation.fiscal_year,
            v_preparation.period,
            'merchant_payment'::public."TransactionType",
            v_preparation.currency_code,
            v_preparation.merchant_credit_amount::numeric,
            v_preparation.payment_fee::numeric,
            v_preparation.commission_rate::numeric,
            v_preparation.commission_amount::numeric,
            false,
            v_preparation.country_code
        );
    end if;

    /*
     * Mark transaction state successful.
     */
    v_stage :=
        'complete transaction state';

    update public.transaction_state
    set
        user_id =
            v_merchant.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()

    where id =
          p_transaction_state_id
      and created_by =
          p_payer_id
      and user_id =
          v_merchant.id
      and transaction_type =
          'merchant_payment'::public."TransactionType"
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    /*
     * Return posting and push-notification data.
     */
    v_stage :=
        'return merchant payment result';

    return query
    select
        true,
        v_document_number,
        v_preparation.merchant_credit_amount,
        v_preparation.payment_fee,
        v_preparation.currency_code,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload
            ->> 'reference';

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
                    'MERCHANT_PAYMENT_FAILED at [%s]: %s',
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
                    'Check the Merchant Payment stage reported in the error'
                );
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.complete_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    text
)
owner to postgres;

revoke all
on function public.complete_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    text
)
from public, anon, authenticated, service_role;

grant execute
on function public.complete_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    text
)
to service_role;