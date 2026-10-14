create or replace function public.execute_my_customer_direct_deposit(
    p_identifier text,
    p_currency_code text,
    p_amount numeric,
    p_reference text,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_finance_user public.users%rowtype;
    v_customer public.users%rowtype;
    v_treasury public.users%rowtype;

    v_identifier text;
    v_currency_code text;
    v_reference text;

    v_amount numeric;
    v_fee numeric := 0;
    v_net_amount numeric;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;

    v_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_receiver_notification_id text;
begin
    /*
     * Authenticate and authorize finance.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    v_identifier :=
        nullif(
            btrim(p_identifier),
            ''
        );

    if v_identifier is null then
        raise exception
            'IDENTIFIER_REQUIRED';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    v_reference :=
        nullif(
            btrim(p_reference),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    v_amount :=
        p_amount;

    if v_amount is null
       or v_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * References are globally unique.
     */
    perform 1
    from public.financial_transaction
        financial_transaction_record
    where financial_transaction_record.reference =
          v_reference
    limit 1;

    if found then
        raise exception
            'TRANSACTION_REPLAY';
    end if;

    /*
     * Fetch trusted finance-user context.
     */
    v_finance_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_finance_user.id is null then
        raise exception
            'FINANCE_USER_NOT_FOUND';
    end if;

    if v_finance_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch the customer and country treasury.
     */
    v_customer :=
        public.fetch_user_by_email_or_phone(
            v_identifier
        );

    if v_customer.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    v_treasury :=
        public.fetch_country_treasury(
            v_finance_user.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;

    /*
     * Validate customer.
     */
    if v_customer.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    if v_customer.country_code is distinct from
       v_finance_user.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Fetch GL mappings.
     */
    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        'customer_direct_deposit'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build deposit components.
     */
    v_components :=
        public.build_posting_components(
            'customer_direct_deposit'::public."TransactionType",
            v_amount,
            v_mappings,
            v_finance_user.country_code,
            v_currency_code,
            false
        );

    if v_components is null
       or cardinality(v_components) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Extract the configured deposit fee.
     */
    select coalesce(
        component_record.credit_amount,
        0
    )
    into v_fee
    from unnest(
        v_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'deposit_fee'::public."ComponentType"
    limit 1;

    v_fee :=
        coalesce(
            v_fee,
            0
        );

    if v_fee < 0 then
        raise exception
            'INVALID_FEE_AMOUNT';
    end if;

    v_net_amount :=
        v_amount -
        v_fee;

    if v_net_amount <= 0 then
        raise exception
            'INVALID_NET_DEPOSIT_AMOUNT';
    end if;

    /*
     * Fetch fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_finance_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Prepare customer notification.
     */
    v_notification :=
        public.create_notification_message(
            v_finance_user.country_code,
            'customer_direct_deposit'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(
                v_currency_code
            ),
            v_reference,
            0,
            'Ngoda',
            coalesce(
                v_customer.email,
                v_customer.phone,
                v_customer.id
            )
        );

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_customer.country_code,
                v_customer.id
            ),
            array[]::text[]
        );

    /*
     * Generate document number.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'customer_direct_deposit'::public."TransactionType"
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_finance_user.country_code
        );

    /*
     * Create financial transaction header.
     */
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
        country_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_document_number,
        v_reference,
        'customer_direct_deposit'::public."TransactionType",
        format(
            'Customer direct deposit for %s',
            coalesce(
                v_customer.email,
                v_customer.phone,
                v_customer.id
            )
        ),
        v_finance_user.id,
        v_amount,
        v_currency_code,
        v_finance_user.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post GL entries.
     */
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_finance_user.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'customer_direct_deposit'::public."TransactionType",

        p_created_by =>
            v_finance_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_currency_code,

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
     * Post wallet entries.
     *
     * The treasury wallet is the internal system counterparty.
     * The external money itself is received through the bank
     * or office and is represented by the GL posting.
     */
    select wallet_result.receiver_notification_id
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
            v_customer.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            'customer_direct_deposit'::public."TransactionType",

        p_credit_amount =>
            v_net_amount,

        p_debit_amount =>
            v_amount,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            v_currency_code,

        p_country_code =>
            v_finance_user.country_code,

        p_audit_action_type =>
            'customer_direct_deposit'::public."AuditActionType",

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            v_fee,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_notification,

        p_sender_notification =>
            null
    ) as wallet_result;

    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_document_number,

        'reference',
        v_reference,

        'user_id',
        v_customer.id,

        'currency_code',
        v_currency_code,

        'funded_amount',
        v_amount::text,

        'fee',
        v_fee::text,

        'net_amount',
        v_net_amount::text,

        'receiver_notification_id',
        v_receiver_notification_id,

        'device_tokens',
        to_jsonb(
            v_device_tokens
        ),

        'push_title',
        v_notification.title,

        'push_body',
        v_notification.body,

        'push_reference',
        v_notification.payload
            ->> 'reference'
    );
end;
$function$;


revoke all on function
    public.execute_my_customer_direct_deposit(
        text,
        text,
        numeric,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_customer_direct_deposit(
        text,
        text,
        numeric,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_customer_direct_deposit(
        text,
        text,
        numeric,
        text,
        text
    )
to authenticated;