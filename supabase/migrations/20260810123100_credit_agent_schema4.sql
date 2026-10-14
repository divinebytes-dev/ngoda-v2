create or replace function public.execute_my_credit_agent_funding(
    p_agent_identifier text,
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
    v_executor public.users%rowtype;
    v_treasury public.users%rowtype;
    v_merchant public.users%rowtype;

    v_credit_account
        public.credit_agent_account%rowtype;

    v_credit_entry
        public.credit_agent_entry%rowtype;

    v_credit_transaction_type
        public."TransactionType" :=
        'credit_agent_funding'::public."TransactionType";

    v_deposit_transaction_type
        public."TransactionType" :=
        'agent_deposit'::public."TransactionType";

    v_identifier text;
    v_currency_code text;
    v_amount numeric;
    v_reference text;

    v_fiscal_year integer;
    v_period integer;

    v_credit_mappings
        public.transaction_gl_mapping[];

    v_deposit_mappings
        public.transaction_gl_mapping[];

    v_credit_components
        public.posting_component[];

    v_deposit_components
        public.posting_component[];

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_credit_document_prefix text;
    v_deposit_document_prefix text;

    v_credit_document_number text;
    v_deposit_document_number text;

    v_credit_transaction_id
        public.financial_transaction.id%type;

    v_deposit_transaction_id
        public.financial_transaction.id%type;

    v_receiver_notification
        public.notification_message;

    v_receivable_balance numeric;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate treasury.
     */
    v_stage := 'authorize treasury user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    v_stage := 'validate input';

    v_identifier :=
        nullif(
            btrim(p_agent_identifier),
            ''
        );

    if v_identifier is null then
        raise exception
            'MERCHANT_IDENTIFIER_REQUIRED';
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

    if v_currency_code = 'gold' then
        raise exception
            'CREDIT_AGENT_CURRENCY_MUST_BE_FIAT';
    end if;

    v_amount :=
        trunc(
            p_amount,
            2
        );

    if v_amount is null
       or v_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
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

    /*
     * Fetch authenticated treasury user.
     */
    v_stage := 'fetch treasury user';

    v_executor :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_executor.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if v_executor.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch country treasury.
     */
    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_executor.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Find an active merchant.
     */
    v_stage := 'fetch merchant';

    select user_record.*
    into v_merchant
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.country_code =
              v_executor.country_code

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'merchant'

      and (
          lower(
              user_record.email
          ) =
              lower(v_identifier)

          or user_record.phone =
              v_identifier
      )
    limit 1;

    if not found then
        raise exception
            'ACTIVE_MERCHANT_NOT_FOUND';
    end if;

    /*
     * Lock the approved credit-agent account.
     */
    v_stage := 'lock credit agent account';

    select account_record.*
    into v_credit_account
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
              v_merchant.id

      and account_record.country_code =
              v_executor.country_code

      and account_record.currency_code =
              v_currency_code
    for update;

    if not found then
        raise exception
            'MERCHANT_NOT_APPROVED_FOR_CREDIT_FACILITY';
    end if;

    if not v_credit_account.is_active then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_ACTIVE';
    end if;

    /*
     * Prevent reference replay.
     */
    v_stage := 'check transaction reference';

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.reference =
          v_reference
    limit 1;

    if found then
        raise exception
            'TRANSACTION_REPLAY';
    end if;

    /*
     * Fetch GL mappings.
     */
    v_stage := 'fetch credit funding mappings';

    select array_agg(mapping_record)
    into v_credit_mappings
    from public.fetch_gl_mappings(
        v_credit_transaction_type
    ) as mapping_record;

    if v_credit_mappings is null
       or cardinality(v_credit_mappings) = 0
    then
        raise exception
            'CREDIT_AGENT_FUNDING_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'fetch agent deposit mappings';

    select array_agg(mapping_record)
    into v_deposit_mappings
    from public.fetch_gl_mappings(
        v_deposit_transaction_type
    ) as mapping_record;

    if v_deposit_mappings is null
       or cardinality(v_deposit_mappings) = 0
    then
        raise exception
            'AGENT_DEPOSIT_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build posting components.
     *
     * credit_agent_funding:
     * Dr Agent Receivable
     * Cr Bank
     *
     * agent_deposit:
     * Dr Bank
     * Cr Agent Float Payable
     */
    v_stage := 'build credit funding components';

    v_credit_components :=
        public.build_posting_components(
            v_credit_transaction_type,
            v_amount,
            v_credit_mappings,
            v_executor.country_code,
            v_currency_code,
            false
        );

    v_stage := 'build agent deposit components';

    v_deposit_components :=
        public.build_posting_components(
            v_deposit_transaction_type,
            v_amount,
            v_deposit_mappings,
            v_executor.country_code,
            v_currency_code,
            false
        );

    /*
     * Fetch wallet-owner configuration.
     */
    v_stage := 'fetch wallet-owner configuration';

    select wallet_owner_record.*
    into v_wallet_owners
    from public.fetch_transaction_type_wallet_owner(
        v_credit_transaction_type
    ) as wallet_owner_record;

    if not found then
        raise exception
            'CREDIT_AGENT_FUNDING_WALLET_OWNER_NOT_FOUND';
    end if;

    if v_wallet_owners.sender_wallet_owner <>
       'treasury'::public."WalletOwnerType"
    then
        raise exception
            'CREDIT_AGENT_FUNDING_SENDER_MUST_BE_TREASURY';
    end if;

    if v_wallet_owners.receiver_wallet_owner <>
       'agent'::public."WalletOwnerType"
    then
        raise exception
            'CREDIT_AGENT_FUNDING_RECEIVER_MUST_BE_AGENT_WALLET';
    end if;

    if v_wallet_owners.audit_action_type is null then
        raise exception
            'CREDIT_AGENT_FUNDING_AUDIT_ACTION_NOT_CONFIGURED';
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
        v_executor.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch document prefixes.
     */
    v_stage := 'fetch credit funding document prefix';

    v_credit_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_credit_transaction_type
        );

    if nullif(
        btrim(v_credit_document_prefix),
        ''
    ) is null
    then
        raise exception
            'CREDIT_AGENT_FUNDING_DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_stage := 'fetch agent deposit document prefix';

    v_deposit_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_deposit_transaction_type
        );

    if nullif(
        btrim(v_deposit_document_prefix),
        ''
    ) is null
    then
        raise exception
            'AGENT_DEPOSIT_DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Generate document numbers.
     */
    v_stage := 'generate credit funding document';

    v_credit_document_number :=
        public.generate_document_number(
            v_credit_document_prefix,
            v_fiscal_year,
            v_period,
            v_executor.country_code
        );

    v_stage := 'generate agent deposit document';

    v_deposit_document_number :=
        public.generate_document_number(
            v_deposit_document_prefix,
            v_fiscal_year,
            v_period,
            v_executor.country_code
        );

    /*
     * Create receiver notification.
     */
    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code =>
                v_executor.country_code,

            p_transaction_type =>
                v_credit_transaction_type,

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
                    v_treasury.email,
                    'Ngoda'
                ),

            p_receiver =>
                coalesce(
                    v_merchant.email,
                    v_merchant.id
                )
        );

    /*
     * Document 1:
     *
     * Dr Agent Receivable
     * Cr Bank
     */
    v_stage := 'create credit funding transaction';

    insert into public.financial_transaction (
        fiscal_year,
        period,
        country_code,
        document_number,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_executor.country_code,
        v_credit_document_number,
        v_reference,
        v_credit_transaction_type,
        format(
            'Credit funding issued to merchant %s',
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        ),
        v_executor.id,
        v_amount,
        v_currency_code
    )
    returning id
    into v_credit_transaction_id;

    v_stage := 'post credit funding entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_credit_document_number,

        p_country_code =>
            v_executor.country_code,

        p_transaction_id =>
            v_credit_transaction_id,

        p_transaction_type =>
            v_credit_transaction_type,

        p_created_by =>
            v_executor.id,

        p_components =>
            v_credit_components,

        p_mappings =>
            v_credit_mappings,

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
     * Document 2:
     *
     * Dr Bank
     * Cr Agent Float Payable
     */
    v_stage := 'create agent deposit transaction';

    insert into public.financial_transaction (
        fiscal_year,
        period,
        country_code,
        document_number,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_executor.country_code,
        v_deposit_document_number,
        v_credit_document_number,
        v_deposit_transaction_type,
        format(
            'Credit float deposited to merchant agent wallet %s',
            coalesce(
                v_merchant.email,
                v_merchant.phone,
                v_merchant.id
            )
        ),
        v_executor.id,
        v_amount,
        v_currency_code
    )
    returning id
    into v_deposit_transaction_id;

    v_stage := 'post agent deposit entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_deposit_document_number,

        p_country_code =>
            v_executor.country_code,

        p_transaction_id =>
            v_deposit_transaction_id,

        p_transaction_type =>
            v_deposit_transaction_type,

        p_created_by =>
            v_executor.id,

        p_components =>
            v_deposit_components,

        p_mappings =>
            v_deposit_mappings,

        p_currency_code =>
            v_currency_code,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_credit_document_number,

        p_deposit_type =>
            null
    );

    /*
     * Move electronic float:
     *
     * Treasury -> merchant agent wallet.
     */
    v_stage := 'post wallet entries';

    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_document_number =>
            v_credit_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_merchant.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            v_credit_transaction_type,

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
            v_executor.country_code,

        p_audit_action_type =>
            v_wallet_owners.audit_action_type,

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    );

    /*
     * Increase this merchant's receivable:
     *
     * debit_receivable = funding amount.
     */
    v_stage := 'post credit agent receivable';

    v_credit_entry :=
        public.post_credit_agent_entry(
            p_credit_agent_account_id =>
                v_credit_account.id,

            p_document_number =>
                v_credit_document_number,

            p_transaction_type =>
                v_credit_transaction_type,

            p_fiscal_year =>
                v_fiscal_year,

            p_period =>
                v_period,

            p_debit_receivable =>
                v_amount,

            p_credit_receivable =>
                0,

            p_debit_cash_holding =>
                0,

            p_credit_cash_holding =>
                0,

            p_created_by =>
                v_executor.id
        );

    /*
     * Read final balance.
     */
    v_stage := 'fetch final receivable balance';

    select account_record.receivable_balance
    into v_receivable_balance
    from public.credit_agent_account
        account_record
    where account_record.id =
          v_credit_account.id;

    return jsonb_build_object(
        'success',
        true,

        'transaction_type',
        v_credit_transaction_type,

        'document_number',
        v_credit_document_number,

        'deposit_document_number',
        v_deposit_document_number,

        'reference',
        v_reference,

        'funded_amount',
        v_amount::text,

        'currency_code',
        v_currency_code,

        'merchant_id',
        v_merchant.id,

        'credit_agent_account_id',
        v_credit_account.id,

        'credit_agent_entry_id',
        v_credit_entry.id,

        'receivable_balance',
        v_receivable_balance::text
    );

exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,

            message = format(
                'CREDIT_AGENT_FUNDING_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the Credit Agent Funding stage reported in the error'
            );
end;
$function$;


revoke all on function
    public.execute_my_credit_agent_funding(
        text,
        text,
        numeric,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_credit_agent_funding(
        text,
        text,
        numeric,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_credit_agent_funding(
        text,
        text,
        numeric,
        text,
        text
    )
to authenticated;