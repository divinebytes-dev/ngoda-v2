/* =========================================================
 * CASH DEPOSIT
 * ========================================================= */

create or replace function public.cash_deposit(
    p_user_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    reference text,
    customer_id text,
    gross_amount text,
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
    v_currency text;
    v_reference text;
    v_provider_id text;

    v_fiscal_year integer;
    v_period integer;

    v_user public.users%rowtype;
    v_provider public.users%rowtype;

    v_transaction_state
        public.transaction_state%rowtype;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_receiver_notification
        public.notification_message;

    v_sender_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;
    v_receiver_notification_id text;

    v_deposit_type
        public."CustomerDepositType" :=
            'agent'::public."CustomerDepositType";

    /*
     * Debugging information.
     */
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Validate the transaction type.
     */
    v_stage := 'validate transaction type';

    if p_transaction_type <>
       'cash_deposit'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_DEPOSIT_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    /*
     * Validate and lock the processing transaction.
     *
     * This state was created through the authenticated
     * client before the service-role posting call.
     */
    v_stage :=
        'validate and lock transaction state';

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state
        transaction_state_record
    where transaction_state_record.id =
          p_transaction_state_id
      and transaction_state_record.created_by =
          p_user_id
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

    /*
     * Ensure the service-role posting uses the same
     * transaction that created the processing state.
     */
    v_stage :=
        'validate transaction state data';

    if v_transaction_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;

    /*
     * Parse transaction data.
     */
    v_stage := 'parse transaction amount';

    v_amount :=
        (p_transaction ->> 'a')::numeric /
        v_decimals;

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_stage := 'parse transaction currency';

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    v_stage := 'parse transaction reference';

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_stage := 'parse provider identifier';

    v_provider_id :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_provider_id is null then
        raise exception
            'PROVIDER_ID_MISSING';
    end if;

    /*
     * Ensure the locked state belongs to the provider
     * contained in the signed transaction.
     */
    if v_transaction_state.user_id
       is distinct from v_provider_id
    then
        raise exception
            'TRANSACTION_PROVIDER_MISMATCH';
    end if;

    /*
     * Validate the sender approval stored in the
     * transaction state.
     */
    v_stage := 'validate sender approval';

    if v_transaction_state.sender_approval is null
       or jsonb_typeof(
           v_transaction_state.sender_approval
       ) <> 'object'
    then
        raise exception
            'SENDER_APPROVAL_MISSING';
    end if;

    if (
        v_transaction_state.sender_approval
            ->> 'a'
       )::numeric <>
       (
        p_transaction ->> 'a'
       )::numeric
    then
        raise exception
            'AMOUNT_MISMATCH';
    end if;

    if lower(
        btrim(
            v_transaction_state.sender_approval
                ->> 'c'
        )
    ) is distinct from v_currency
    then
        raise exception
            'CURRENCY_MISMATCH';
    end if;

    if btrim(
        v_transaction_state.sender_approval
            ->> 'r'
    ) is distinct from v_reference
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    /*
     * Validate the initiating user's role.
     *
     * Customers, agents and vendors can all use their
     * customer-owned wallets.
     */
    v_stage := 'validate initiating user role';

    if not public.user_has_role(
        p_user_id,
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Validate the cash provider's role.
     */
    v_stage := 'validate provider role';

    if not public.user_has_role(
        v_provider_id,
        array[
            'agent'::public."Role",
            'merchant'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'PROVIDER_NOT_AUTHORIZED';
    end if;

    /*
     * Fetch both participants.
     */
    v_stage := 'fetch user';

    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );

    v_stage := 'fetch provider';

    v_provider :=
        public.fetch_user_by_id(
            v_provider_id
        );

    /*
     * Validate participants.
     */
    v_stage := 'validate participants';

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    if v_provider.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'PROVIDER_NOT_ACTIVE';
    end if;

    if v_user.id = v_provider.id then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_user.country_code is distinct from
       v_provider.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_user.country_code is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Fetch the current fiscal period.
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
     * Fetch the configured GL mappings.
     */
    v_stage := 'fetch GL mappings';

    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build the balanced posting components.
     */
    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_amount,
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
     * Build the user notification.
     */
    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-01',
            0,
            coalesce(
                v_provider.email,
                v_provider.phone,
                v_provider.id
            ),
            coalesce(
                v_user.email,
                v_user.phone,
                v_user.id
            )
        );

    /*
     * Build the provider notification.
     */
    v_stage := 'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'sender'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-02',
            0,
            'Ngoda',
            coalesce(
                v_user.email,
                v_user.phone,
                v_user.id
            )
        );

    /*
     * Fetch the receiving user's device tokens.
     */
    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_user.id
            ),
            array[]::text[]
        );

    /*
     * Generate the accounting document number.
     */
    v_stage :=
        'fetch document number prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );

    /*
     * Create the financial transaction header.
     */
    v_stage :=
        'insert financial transaction';

    insert into public.financial_transaction (
        fiscal_year,
        period,
        document_number,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        external_reference,
        country_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_document_number,
        v_document_number,
        p_transaction_type,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' deposit from provider ' ||
        coalesce(
            v_provider.email,
            v_provider.phone,
            v_provider.id
        ),
        v_provider.id,
        v_amount,
        v_currency,
        v_deposit_type::text,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post the financial ledger entries.
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
            v_provider.id,

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
            v_deposit_type
    );

    /*
     * Debit the provider's agent wallet and credit
     * the user's customer wallet.
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
            v_user.id,

        p_sender_id =>
            v_provider.id,

        p_transaction_type =>
            p_transaction_type,

        p_credit_amount =>
            v_amount,

        p_debit_amount =>
            v_amount,

        p_sender_wallet_owner =>
            'agent'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            'cash_deposited'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification
    ) as result;

    /*
     * Mark the transaction state as successful.
     */
    v_stage := 'update transaction state';

    update public.transaction_state
    set
        user_id =
            v_provider.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_user_id
      and user_id =
          v_provider.id
      and transaction_type =
          p_transaction_type
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    /*
     * Return posting and push-notification details.
     */
    v_stage := 'return cash deposit result';

    return query
    select
        true,
        v_document_number,
        v_user.id,
        v_amount::text,
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
                    'CASH_DEPOSIT_FAILED at [%s]: %s',
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
                    'Check the cash-deposit stage reported in the error'
                );
end;
$function$;


/* =========================================================
 * FUNCTION OWNER
 * ========================================================= */

alter function public.cash_deposit(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
owner to postgres;


/* =========================================================
 * EXECUTION PERMISSIONS
 * ========================================================= */

revoke execute on function public.cash_deposit(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute on function public.cash_deposit(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to service_role;


/* =========================================================
 * RELOAD POSTGREST
 * ========================================================= */

notify pgrst, 'reload schema';