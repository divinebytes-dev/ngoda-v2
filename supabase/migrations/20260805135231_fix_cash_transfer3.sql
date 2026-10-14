create or replace function public.cash_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    amount text,
    fee text,
    currency text,
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
    v_decimals numeric := 100;

    v_amount numeric;
    v_principal numeric;
    v_currency text;
    v_reference text;
    v_receiver_identifier text;

    v_fiscal_year integer;
    v_period integer;

    v_receiver public.users%rowtype;
    v_sender public.users%rowtype;
    v_treasury public.users%rowtype;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_component_totals
        public.component_totals;

    v_principal_amount numeric;
    v_others_amount numeric;
    v_fee numeric := 0;

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
    /*
     * The Edge Function calls this function with the
     * service-role client. Therefore auth.uid() is not
     * used here.
     *
     * Ownership is established through the transaction
     * state that was created using the authenticated client.
     */
    v_stage :=
        'validate and lock transaction state';

    perform 1
    from public.transaction_state ts
    where ts.id =
          p_transaction_state_id
      and ts.created_by =
          p_sender_id
      and ts.transaction_type =
          p_transaction_type
      and ts.status =
          'processing'::public."TransactionStatus"
    for update;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    v_stage := 'validate transaction type';

    if p_transaction_type <>
       'cash_transfer'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_TRANSFER_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    /*
     * Parse transaction data.
     */
    v_stage := 'parse transaction amount';

    v_amount :=
        (p_transaction ->> 'a')::numeric /
        v_decimals;

    if v_amount <= 0 then
        raise exception 'INVALID_AMOUNT';
    end if;

    v_principal := v_amount;

    v_stage := 'parse transaction currency';

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency is null then
        raise exception 'CURRENCY_MISSING';
    end if;

    v_stage := 'parse transaction reference';

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception 'REFERENCE_MISSING';
    end if;

    v_stage := 'parse receiver identifier';

    v_receiver_identifier :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_receiver_identifier is null then
        raise exception
            'RECEIVER_IDENTIFIER_MISSING';
    end if;

    /*
     * Fetch GL mappings.
     */
    v_stage := 'fetch GL mappings';

    select array_agg(mapping_row)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_row;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build posting components.
     */
    v_stage := 'build posting components';

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

    /*
     * Fetch fiscal period.
     */
    v_stage := 'fetch fiscal period';

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

    /*
     * Fetch users.
     */
    v_stage := 'fetch receiver';

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    v_stage := 'fetch sender';

    v_sender :=
        public.fetch_user_by_id(
            p_sender_id
        );

    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    /*
     * Validate users.
     */
    v_stage := 'validate receiver status';

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'RECEIVER_NOT_ACTIVE';
    end if;

    v_stage := 'validate sender status';

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    v_stage :=
        'validate sender and receiver';

    if v_sender.id = v_receiver.id then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       v_receiver.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Extract component totals.
     */
    v_stage := 'extract component totals';

    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );

    v_principal_amount :=
        v_component_totals.principal_amount;

    v_others_amount :=
        v_component_totals.others_amount;

    /*
     * Extract transfer fee.
     */
    v_stage := 'extract transfer fee';

    select coalesce(
        component.credit_amount,
        0
    )
    into v_fee
    from unnest(v_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'transfer_fee'::public."ComponentType"
    limit 1;

    v_fee := coalesce(v_fee, 0);

    v_stage := 'validate transfer fee';

    if v_fee <= 0 then
        raise exception
            'INVALID_FEE_AMOUNT';
    end if;

    /*
     * Build sender notification.
     */
    v_stage := 'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'sender'::public."NotificationAudience",
            v_principal_amount,
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
            )
        );

    /*
     * Build receiver notification.
     */
    v_stage := 'create receiver notification';

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

    /*
     * Fetch receiver device tokens.
     */
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

    /*
     * Generate document number.
     */
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

    /*
     * Create financial transaction.
     */
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

    /*
     * Post financial entries.
     */
    v_stage := 'post financial entries';

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

    /*
     * Post wallet entries and create notification rows.
     */
    v_stage := 'post wallet entries';

    select result.receiver_notification_id
    into v_receiver_notification_id
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

        p_credit_amount =>
            v_amount,

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
            v_fee,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification
    ) as result;

    /*
     * Mark transaction as successful.
     */
    v_stage := 'update transaction state';

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

    /*
     * Return posting and notification data.
     */
    v_stage :=
        'return cash transfer result';

    return query
    select
        true,
        v_amount::text,
        v_others_amount::text,
        v_currency,
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


/*
 * The posting function must only be callable by the
 * service-role client used inside the Edge Function.
 */
revoke execute on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to service_role;