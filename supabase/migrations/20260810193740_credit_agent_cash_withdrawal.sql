create or replace function public.credit_agent_cash_withdrawal(
    p_agent_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    document_no text,
    amount text,
    fee text,
    tax text,
    currency text,
    holding_used text,
    receivable_used text,
    user_notification_id text,
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

    v_transaction_state
        public.transaction_state%rowtype;

    v_agent public.users%rowtype;
    v_user public.users%rowtype;

    v_credit_account
        public.credit_agent_account%rowtype;

    v_transaction_version text;
    v_reference text;
    v_user_id text;
    v_currency_code text;

    v_requested_amount_minor numeric;
    v_requested_amount numeric;

    v_fiscal_year integer;
    v_period integer;

    v_all_mappings
        public.transaction_gl_mapping[];

    v_build_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_final_components
        public.posting_component[] :=
            array[]::public.posting_component[];

    v_component
        public.posting_component;

    v_principal_component
        public.posting_component;

    v_cash_amount numeric := 0;
    v_total_wallet_debit numeric := 0;

    v_fee numeric := 0;
    v_tax numeric := 0;
    v_total_charges numeric := 0;

    v_holding_used numeric := 0;
    v_receivable_used numeric := 0;
    v_available_balance numeric := 0;

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id
        public.financial_transaction.id%type;

    v_notification
        public.notification_message;

    v_notification_json jsonb;

    v_device_tokens text[];

    v_wallet_entry_count integer;
    v_ignored_notification_id text;

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the Edge Function service client can execute
     * the accounting transaction.
     */
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_transaction_type <>
       'credit_agent_cash_withdrawal'::public."TransactionType"
    then
        raise exception
            'INVALID_CREDIT_AGENT_CASH_WITHDRAWAL_TRANSACTION_TYPE';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if nullif(btrim(p_transaction_state_id), '') is null then
        raise exception
            'TRANSACTION_STATE_ID_REQUIRED';
    end if;

    /*
     * Read the signed transaction.
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

    v_user_id :=
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

    if v_transaction_version <> 'v3' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_user_id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if coalesce(p_transaction ->> 'a', '') !~ '^[0-9]+$' then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_requested_amount_minor :=
        (p_transaction ->> 'a')::numeric;

    v_requested_amount :=
        round(
            v_requested_amount_minor / 100,
            2
        );

    if v_requested_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Lock and validate the processing state.
     */
    v_stage := 'validate transaction state';

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state
        transaction_state_record
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
       p_agent_id
    then
        raise exception
            'MERCHANT_MISMATCH';
    end if;

    if v_transaction_state.user_id <>
       v_user_id
    then
        raise exception
            'USER_MISMATCH';
    end if;

    /*
     * Revalidate the merchant.
     */
    v_stage := 'fetch credit merchant';

    select merchant_record.*
    into v_agent
    from public.users merchant_record
    join public.user_role role_record
      on role_record.id =
         merchant_record.role_id
    where merchant_record.id =
          p_agent_id

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
     * Revalidate the withdrawing user.
     */
    v_stage := 'fetch withdrawing user';

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id =
          v_user_id

      and user_record.status =
          'active'::public."UserStatus"

      and lower(
          user_record.country_code
      ) =
          lower(p_country_code)
    limit 1;

    if not found then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    /*
     * Lock the merchant balance before calculating the
     * withdrawal split.
     */
    v_stage := 'lock credit agent account';

    select account_record.*
    into v_credit_account
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
          v_agent.id

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
     * Load all mappings.
     */
    v_stage := 'fetch gl mappings';

    select array_agg(mapping_record)
    into v_all_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_record;

    if v_all_mappings is null
       or cardinality(v_all_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * The dynamic receivable component is constructed
     * after the cash/credit split. Exclude it while the
     * normal pricing components are built.
     */
    select array_agg(mapping_record)
    into v_build_mappings
    from unnest(
        v_all_mappings
    ) as mapping_record
    where mapping_record.component_type <>
          'credit_agent_receivable'::public."ComponentType";

    if v_build_mappings is null
       or cardinality(v_build_mappings) = 0
    then
        raise exception
            'BASE_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'build withdrawal components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_requested_amount,
            v_build_mappings,
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
     * Read the principal amounts.
     *
     * Gross withdrawal mode:
     *
     * debit  = customer wallet deduction including fees
     * credit = physical cash paid to the customer
     */
    v_stage := 'read principal component';

    select component_record
    into v_principal_component
    from unnest(
        v_components
    ) as component_record
    where component_record.component_type =
          'principal'::public."ComponentType"
    limit 1;

    if not found then
        raise exception
            'PRINCIPAL_COMPONENT_NOT_FOUND';
    end if;

    v_total_wallet_debit :=
        coalesce(
            v_principal_component.debit_amount,
            0
        );

    v_cash_amount :=
        coalesce(
            v_principal_component.credit_amount,
            0
        );

    if v_total_wallet_debit <= 0
       or v_cash_amount <= 0
    then
        raise exception
            'INVALID_WITHDRAWAL_COMPONENTS';
    end if;

    /*
     * Read fee and tax independently for the response.
     */
    select coalesce(
        sum(
            greatest(
                component_record.debit_amount,
                component_record.credit_amount
            )
        ),
        0
    )
    into v_fee
    from unnest(
        v_components
    ) as component_record
    where component_record.component_type =
          'withdrawal_fee'::public."ComponentType";

    select coalesce(
        sum(
            greatest(
                component_record.debit_amount,
                component_record.credit_amount
            )
        ),
        0
    )
    into v_tax
    from unnest(
        v_components
    ) as component_record
    where component_record.component_type =
          'government_tax'::public."ComponentType";

    v_total_charges :=
        v_total_wallet_debit -
        v_cash_amount;

    if v_total_charges < 0 then
        raise exception
            'INVALID_WITHDRAWAL_CHARGES';
    end if;

    /*
     * Use cash holding first. Any remaining amount uses
     * the merchant's funded receivable balance.
     */
    v_stage := 'calculate balance split';

    v_holding_used :=
        least(
            v_cash_amount,
            coalesce(
                v_credit_account.cash_holding_balance,
                0
            )
        );

    v_receivable_used :=
        v_cash_amount -
        v_holding_used;

    v_available_balance :=
        coalesce(
            v_credit_account.cash_holding_balance,
            0
        ) +
        coalesce(
            v_credit_account.receivable_balance,
            0
        );

    if v_cash_amount >
       v_available_balance
    then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_WITHDRAWAL_BALANCE';
    end if;

    if v_receivable_used >
       coalesce(
           v_credit_account.receivable_balance,
           0
       )
    then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_RECEIVABLE_BALANCE';
    end if;

    /*
     * Replace the principal credit with only the amount
     * funded by Agent Cash Holding.
     *
     * The debit remains the complete customer deduction.
     */
    v_stage := 'build split posting components';

    foreach v_component in array v_components
    loop
        if v_component.component_type =
           'principal'::public."ComponentType"
        then
            v_component :=
                row(
                    v_component.component_type,
                    v_component.debit_amount,
                    v_holding_used
                )::public.posting_component;
        end if;

        v_final_components :=
            array_append(
                v_final_components,
                v_component
            );
    end loop;

    /*
     * Add the receivable credit only when credit float
     * was used.
     */
    if v_receivable_used > 0 then
        v_final_components :=
            array_append(
                v_final_components,
                row(
                    'credit_agent_receivable'::public."ComponentType",
                    0,
                    v_receivable_used
                )::public.posting_component
            );
    end if;

    /*
     * Validate the complete split journal.
     */
    v_final_components :=
        public.validate_components(
            v_final_components
        );

    /*
     * Fiscal period and document number.
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

    v_stage := 'fetch document prefix';

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
     * Fetch wallet direction:
     *
     * customer -> merchant agent wallet
     */
    v_stage := 'fetch wallet-owner configuration';

    select wallet_owner_record.*
    into v_wallet_owners
    from public.fetch_transaction_type_wallet_owner(
        p_transaction_type
    ) as wallet_owner_record;

    if not found then
        raise exception
            'CREDIT_AGENT_CASH_WITHDRAWAL_WALLET_OWNER_NOT_FOUND';
    end if;

    /*
     * Notification belongs to the withdrawing customer,
     * who is the wallet sender.
     */
    v_stage := 'build user notification';

    v_notification :=
        public.create_notification_message(
            p_country_code =>
                p_country_code,

            p_transaction_type =>
                p_transaction_type,

            p_audience =>
                'sender'::public."NotificationAudience",

            p_amount =>
                v_cash_amount,

            p_currency =>
                upper(v_currency_code),

            p_reference =>
                v_reference,

            p_quantity =>
                0,

            p_sender =>
                coalesce(
                    v_user.email,
                    v_user.id
                ),

            p_receiver =>
                coalesce(
                    v_agent.email,
                    v_agent.id
                )
        );

    v_notification_json :=
        to_jsonb(v_notification);

    v_device_tokens :=
        public.fetch_device_tokens(
            p_country_code,
            v_user.id
        );

    /*
     * Financial transaction header.
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
            'Credit-agent cash withdrawal for user %s through merchant %s',
            v_user.id,
            v_agent.id
        ),
        v_agent.id,
        v_total_wallet_debit,
        v_currency_code,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post the split GL journal.
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
            v_agent.id,

        p_components =>
            v_final_components,

        p_mappings =>
            v_all_mappings,

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
     * Customer wallet decreases by the gross debit.
     * Merchant agent wallet receives the cash principal.
     *
     * Fees and tax remain represented by the difference
     * between debit and credit.
     */
    v_stage := 'post wallet entries';

    select
        wallet_result.wallet_entry_count,
        wallet_result.receiver_notification_id
    into
        v_wallet_entry_count,
        v_ignored_notification_id
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
            v_agent.id,

        p_sender_id =>
            v_user.id,

        p_transaction_type =>
            p_transaction_type,

        p_credit_amount =>
            v_cash_amount,

        p_debit_amount =>
            v_total_wallet_debit,

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
            v_total_charges,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            null,

        p_sender_notification =>
            v_notification
    ) as wallet_result;

    /*
     * Reduce the balances used for the withdrawal.
     */
    v_stage := 'post credit agent balance movement';

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
            v_receivable_used,

        p_debit_cash_holding =>
            0,

        p_credit_cash_holding =>
            v_holding_used,

        p_created_by =>
            v_agent.id
    );

    /*
     * TransactionStatus uses success, not completed.
     */
    v_stage := 'complete transaction state';

    update public.transaction_state
    set
        status =
            'success'::public."TransactionStatus",

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

        v_document_number,

        v_cash_amount::text,

        v_fee::text,

        v_tax::text,

        v_currency_code,

        v_holding_used::text,

        v_receivable_used::text,

        null::text,

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
                    'CREDIT_AGENT_CASH_WITHDRAWAL_FAILED at [%s]: %s',
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
                        'Check the Credit Agent Cash Withdrawal stage: %s',
                        v_stage
                    )
                );
end;
$function$;


revoke all on function
    public.credit_agent_cash_withdrawal(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from public;

revoke all on function
    public.credit_agent_cash_withdrawal(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from anon;

revoke all on function
    public.credit_agent_cash_withdrawal(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
from authenticated;

grant execute on function
    public.credit_agent_cash_withdrawal(
        text,
        jsonb,
        public."TransactionType",
        text,
        text,
        text
    )
to service_role;