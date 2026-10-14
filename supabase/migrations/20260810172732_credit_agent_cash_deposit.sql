create or replace function public.credit_agent_cash_deposit(
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
    v_stage text := 'initialization';

    v_customer public.users%rowtype;
    v_provider public.users%rowtype;
    v_transaction_state public.transaction_state%rowtype;
    v_credit_account public.credit_agent_account%rowtype;

    v_transaction_version text;
    v_reference text;
    v_provider_id text;
    v_currency_code text;

    v_amount_minor numeric;
    v_amount numeric;

    v_fiscal_year integer;
    v_period integer;

    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id
        public.financial_transaction.id%type;

    v_notification public.notification_message;
    v_notification_json jsonb;

    v_device_tokens text[];

    v_wallet_entry_count integer;
    v_receiver_notification_id text;

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * This function is called only by the Edge Function
     * through the service-role Supabase client.
     */
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_transaction_type <>
       'credit_agent_cash_deposit'::public."TransactionType"
    then
        raise exception
            'INVALID_CREDIT_AGENT_CASH_DEPOSIT_TRANSACTION_TYPE';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if nullif(btrim(p_transaction_state_id), '') is null then
        raise exception
            'TRANSACTION_STATE_ID_REQUIRED';
    end if;

    /*
     * Read signed transaction fields.
     *
     * a = amount in minor currency units
     * c = currency
     * r = reference
     * s = provider/merchant ID
     * v = transaction version
     */
    v_stage := 'read transaction fields';

    v_transaction_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    v_provider_id :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    v_currency_code :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_transaction_version <> 'v1' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_provider_id is null then
        raise exception
            'PROVIDER_NOT_FOUND';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if coalesce(p_transaction ->> 'a', '') !~ '^[0-9]+$' then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_amount_minor :=
        (p_transaction ->> 'a')::numeric;

    /*
     * Signed fiat amounts are represented in minor units.
     */
    v_amount :=
        round(
            v_amount_minor / 100,
            2
        );

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Lock and validate the processing transaction state.
     */
    v_stage := 'validate transaction state';

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state transaction_state_record
    where transaction_state_record.id::text =
          p_transaction_state_id
    for update;

    if not found then
        raise exception
            'TRANSACTION_STATE_NOT_FOUND';
    end if;

    if v_transaction_state.status <>
       'processing'::public."TransactionStatus"
    then
        raise exception
            'TRANSACTION_NOT_PROCESSING';
    end if;

    if v_transaction_state.transaction_type <>
       p_transaction_type
    then
        raise exception
            'TRANSACTION_TYPE_MISMATCH';
    end if;

    if v_transaction_state.reference <>
       v_reference
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    if v_transaction_state.created_by <>
       p_user_id
    then
        raise exception
            'CUSTOMER_MISMATCH';
    end if;

    if v_transaction_state.user_id <>
       v_provider_id
    then
        raise exception
            'PROVIDER_MISMATCH';
    end if;

    /*
     * Fetch the customer.
     */
    v_stage := 'fetch customer';

    select user_record.*
    into v_customer
    from public.users user_record
    where user_record.id = p_user_id
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'CUSTOMER_NOT_FOUND';
    end if;

    if lower(v_customer.country_code) <>
       lower(p_country_code)
    then
        raise exception
            'CUSTOMER_COUNTRY_MISMATCH';
    end if;

    /*
     * Fetch and validate the merchant.
     */
    v_stage := 'fetch credit merchant';

    select merchant_record.*
    into v_provider
    from public.users merchant_record
    join public.user_role role_record
      on role_record.id =
         merchant_record.role_id
    where merchant_record.id =
          v_provider_id

      and merchant_record.status =
          'active'::public."UserStatus"

      and lower(
          merchant_record.country_code
      ) =
          lower(p_country_code)

      and lower(
          role_record.name::text
      ) =
          'merchant'
    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_NOT_FOUND';
    end if;

    /*
     * Lock the currency balance belonging to this
     * credit merchant.
     */
    v_stage := 'lock credit agent account';

    select account_record.*
    into v_credit_account
    from public.credit_agent_account account_record
    where account_record.merchant_id =
          v_provider.id

      and lower(
          account_record.country_code
      ) =
          lower(p_country_code)

      and lower(
          account_record.currency_code
      ) =
          v_currency_code

      and account_record.is_active =
          true
    for update;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_ACTIVE';
    end if;

    /*
     * Prevent a verified reference from being posted
     * more than once.
     */
    v_stage := 'check posting replay';

    perform 1
    from public.financial_transaction
        financial_transaction_record
    where financial_transaction_record.reference =
          v_reference

      and financial_transaction_record.country_code =
          p_country_code

      and financial_transaction_record.transaction_type =
          p_transaction_type
    limit 1;

    if found then
        raise exception
            'TRANSACTION_REPLAY';
    end if;

    /*
     * Load accounting configuration.
     */
    v_stage := 'fetch gl mappings';

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

    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_amount,
            v_mappings,
            p_country_code,
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
     * Expected configured accounting:
     *
     * Dr 1008000 Agent Cash Holding
     * Cr 2002000 Customer Deposits
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

    v_stage := 'fetch wallet-owner configuration';

    select wallet_owner_record.*
    into v_wallet_owners
    from public.fetch_transaction_type_wallet_owner(
        p_transaction_type
    ) as wallet_owner_record;

    if not found then
        raise exception
            'CREDIT_AGENT_CASH_DEPOSIT_WALLET_OWNER_NOT_FOUND';
    end if;

    v_stage := 'generate document number';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    if nullif(btrim(v_document_prefix), '') is null then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );

    /*
     * Build notification before wallet posting.
     */
    v_stage := 'build customer notification';

    v_notification :=
        public.create_notification_message(
            p_country_code =>
                p_country_code,

            p_transaction_type =>
                p_transaction_type,

            p_audience =>
                'receiver'::public."NotificationAudience",

            p_amount =>
                v_amount,

            p_currency =>
                upper(v_currency_code),

            p_reference =>
                v_reference,

            p_quantity =>
                0,

            p_sender =>
                coalesce(
                    v_provider.email,
                    v_provider.id
                ),

            p_receiver =>
                coalesce(
                    v_customer.email,
                    v_customer.id
                )
        );

    v_notification_json :=
        to_jsonb(v_notification);

    v_device_tokens :=
        public.fetch_device_tokens(
            p_country_code,
            v_customer.id
        );

    /*
     * Create financial transaction.
     */
    v_stage := 'create financial transaction';

    insert into public.financial_transaction (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_reference,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        format(
            'Credit-agent cash deposit for customer %s through merchant %s',
            v_customer.id,
            v_provider.id
        ),
        v_provider.id,
        v_amount,
        v_currency_code,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post the GL journal.
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
     * Move wallet value:
     *
     * sender   = merchant's agent wallet
     * receiver = customer's user wallet
     */
    v_stage := 'post wallet entries';

    select
        wallet_result.wallet_entry_count,
        wallet_result.receiver_notification_id
    into
        v_wallet_entry_count,
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
            v_customer.id,

        p_sender_id =>
            v_provider.id,

        p_transaction_type =>
            p_transaction_type,

        p_credit_amount =>
            v_amount,

        p_debit_amount =>
            v_amount,

        p_sender_wallet_owner =>
            v_wallet_owners.sender_wallet_owner,

        p_receiver_wallet_owner =>
            v_wallet_owners.receiver_wallet_owner,

        p_currency_code =>
            v_currency_code,

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            v_wallet_owners.audit_action_type,

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_notification,

        p_sender_notification =>
            null
    ) as wallet_result;

    /*
     * Increase the merchant's cash holding.
     *
     * Receivable is unchanged.
     */
    v_stage := 'post credit agent cash holding';

    perform public.post_credit_agent_entry(
        p_credit_agent_account_id =>
            v_credit_account.id::text,

        p_document_number =>
            v_document_number,

        p_transaction_type =>
            p_transaction_type,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_debit_receivable =>
            0,

        p_credit_receivable =>
            0,

        p_debit_cash_holding =>
            v_amount,

        p_credit_cash_holding =>
            0,

        p_created_by =>
            v_provider.id
    );

    /*
     * Mark the verified transaction state completed.
     */
    v_stage := 'complete transaction state';

    update public.transaction_state
    set
        status =
            'completed'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id::text =
          p_transaction_state_id

      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    return query
    select
        true,

        v_reference,

        v_customer.id,

        v_amount::text,

        v_receiver_notification_id,

        v_device_tokens,

        coalesce(
            v_notification_json ->> 'title',
            v_notification_json ->> 'push_title'
        ),

        coalesce(
            v_notification_json ->> 'body',
            v_notification_json ->> 'message',
            v_notification_json ->> 'push_body'
        ),

        coalesce(
            v_notification_json ->> 'reference',
            v_reference
        );

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
                    'CREDIT_AGENT_CASH_DEPOSIT_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                concat_ws(
                    E'\n',
                    nullif(v_error_detail, ''),
                    nullif(v_error_context, '')
                ),

            hint =
                coalesce(
                    nullif(v_error_hint, ''),
                    format(
                        'Check the Credit Agent Cash Deposit stage: %s',
                        v_stage
                    )
                );
end;
$function$;


/*
 * Posting is only available to the service-role Edge
 * Function. Customers and merchants cannot invoke it
 * directly.
 */
revoke all on function
    public.credit_agent_cash_deposit(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from public;

revoke all on function
    public.credit_agent_cash_deposit(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from anon;

revoke all on function
    public.credit_agent_cash_deposit(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from authenticated;

grant execute on function
    public.credit_agent_cash_deposit(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
to service_role;