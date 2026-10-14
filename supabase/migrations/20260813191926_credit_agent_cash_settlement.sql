CREATE OR REPLACE FUNCTION public.credit_agent_cash_settlement(p_merchant_id text, p_transaction jsonb, p_transaction_type "TransactionType", p_country_code text, p_transaction_state_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, reference text, merchant_id text, accounts_id text, currency_code text, settled_amount text, cash_holding_before text, cash_holding_after text, merchant_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text :=
        'initialization';

    v_transaction_state
        public.transaction_state%rowtype;

    v_merchant
        public.users%rowtype;

    v_accounts
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_treasury_wallet
        public.wallet%rowtype;

    v_credit_account
        public.credit_agent_account%rowtype;

    v_transaction_version text;
    v_reference text;
    v_accounts_id text;
    v_currency_code text;

    v_amount_minor numeric;
    v_amount numeric;

    v_cash_holding_before numeric;
    v_cash_holding_after numeric;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_principal_debit numeric := 0;
    v_principal_credit numeric := 0;

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id
        public.financial_transaction.id%type;

    v_notification
        public.notification_message;

    v_notification_json jsonb;

    v_device_tokens text[];

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the Edge Function service client executes the
     * financial posting.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;

    if p_transaction_type <>
       'credit_agent_cash_settlement'::public."TransactionType"
    then
        raise exception
            'INVALID_CREDIT_AGENT_CASH_SETTLEMENT_TRANSACTION_TYPE';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if nullif(
        btrim(
            p_transaction_state_id
        ),
        ''
    ) is null
    then
        raise exception
            'TRANSACTION_STATE_ID_REQUIRED';
    end if;

    /*
     * Read transaction fields.
     *
     * transaction.s is the accounts user who received
     * the physical cash.
     */
    v_stage :=
        'read transaction fields';

    v_transaction_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    v_accounts_id :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    v_currency_code :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_transaction_version <> 'v8' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_accounts_id is null then
        raise exception
            'ACCOUNTS_ID_MISSING';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'INVALID_SETTLEMENT_CURRENCY';
    end if;

    if coalesce(
        p_transaction ->> 'a',
        ''
    ) !~ '^[0-9]+$'
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_amount_minor :=
        (p_transaction ->> 'a')::numeric;

    v_amount :=
        round(
            v_amount_minor /
            100,
            2
        );

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Lock and validate the processing state.
     */
    v_stage :=
        'validate transaction state';

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

    /*
     * The merchant created the state after scanning the
     * accounts transaction.
     */
    if v_transaction_state.created_by <>
       p_merchant_id
    then
        raise exception
            'MERCHANT_MISMATCH';
    end if;

    /*
     * The accounts user signed TransactionData.
     */
    if v_transaction_state.user_id <>
       v_accounts_id
    then
        raise exception
            'ACCOUNTS_USER_MISMATCH';
    end if;

    if lower(
        v_transaction_state.country_code
    ) <>
       lower(p_country_code)
    then
        raise exception
            'COUNTRY_MISMATCH';
    end if;

    /*
     * Fetch the active merchant.
     */
    v_stage :=
        'fetch merchant';

    select merchant_record.*
    into v_merchant
    from public.users
        merchant_record
    join public.user_role
        role_record
      on role_record.id =
         merchant_record.role_id
    where merchant_record.id =
          p_merchant_id

      and merchant_record.status =
          'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
          'merchant'

      and lower(
          merchant_record.country_code
      ) =
          lower(p_country_code)
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_AUTHORIZED';
    end if;

    /*
     * Fetch the active accounts user.
     */
    v_stage :=
        'fetch accounts user';

    select accounts_record.*
    into v_accounts
    from public.users
        accounts_record
    where accounts_record.id =
          v_accounts_id

      and accounts_record.status =
          'active'::public."UserStatus"

      and accounts_record.country_code =
          v_merchant.country_code
    limit 1;

    if not found then
        raise exception
            'ACCOUNTS_USER_NOT_FOUND';
    end if;

    if not public.user_has_role(
        v_accounts.id,
        array[
            'accounts'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'ACCOUNTS_USER_NOT_AUTHORIZED';
    end if;

    /*
     * Fetch the country treasury using the trusted
     * merchant country.
     */
    v_stage :=
        'fetch country treasury';

    select treasury_record.*
    into v_treasury
    from public.fetch_country_treasury(
        v_merchant.country_code
    ) as treasury_record;

    if not found
       or v_treasury.id is null
    then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Lock the merchant's credit-agent account.
     */
    v_stage :=
        'lock credit agent account';

    select account_record.*
    into v_credit_account
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
          v_merchant.id

      and account_record.country_code =
          v_merchant.country_code

      and lower(
          btrim(
              account_record.currency_code
          )
      ) =
          v_currency_code

      and account_record.is_active =
          true
    for update;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_ACTIVE';
    end if;

    v_cash_holding_before :=
        coalesce(
            v_credit_account.cash_holding_balance,
            0
        );

    if v_amount >
       v_cash_holding_before
    then
        raise exception
            'SETTLEMENT_EXCEEDS_CASH_HOLDING';
    end if;

    v_cash_holding_after :=
        v_cash_holding_before -
        v_amount;

    /*
     * Prevent duplicate financial posting.
     */
    v_stage :=
        'check posting replay';

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
     * Fetch the principal-only settlement mappings.
     *
     * Expected posting:
     *
     * Dr Bank/Cash Reserve
     * Cr Agent Cash Holding
     */
    v_stage :=
        'fetch gl mappings';

    select array_agg(
        mapping_record
    )
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
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
        'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_amount,
            v_mappings,
            v_merchant.country_code,
            v_currency_code,
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
     * Settlement must not contain fees, taxes or
     * commissions.
     */
    perform 1
    from unnest(
        v_components
    ) as component_record
    where component_record.component_type <>
          'principal'::public."ComponentType"

      and (
          coalesce(
              component_record.debit_amount,
              0
          ) <> 0

          or

          coalesce(
              component_record.credit_amount,
              0
          ) <> 0
      )
    limit 1;

    if found then
        raise exception
            'CASH_SETTLEMENT_CHARGES_NOT_ALLOWED';
    end if;

    /*
     * Read the principal fields directly.
     */
    select
        coalesce(
            component_record.debit_amount,
            0
        ),

        coalesce(
            component_record.credit_amount,
            0
        )
    into
        v_principal_debit,
        v_principal_credit
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

    if v_principal_debit <> v_amount
       or v_principal_credit <> v_amount
    then
        raise exception
            'INVALID_SETTLEMENT_PRINCIPAL';
    end if;

    /*
     * Fetch fiscal period.
     */
    v_stage :=
        'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_merchant.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Generate document number.
     */
    v_stage :=
        'generate document number';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    if nullif(
        btrim(
            v_document_prefix
        ),
        ''
    ) is null
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_merchant.country_code
        );

    /*
     * Build settlement confirmation for the merchant.
     */
    v_stage :=
        'build merchant notification';

    v_notification :=
        public.create_notification_message(
            p_country_code =>
                v_merchant.country_code,

            p_transaction_type =>
                p_transaction_type,

            p_audience =>
                'receiver'::public."NotificationAudience",

            p_amount =>
                v_amount,

            p_currency =>
                upper(
                    v_currency_code
                ),

            p_reference =>
                v_reference,

            p_quantity =>
                0,

            p_sender =>
                coalesce(
                    v_accounts.email,
                    v_accounts.id
                ),

            p_receiver =>
                coalesce(
                    v_merchant.email,
                    v_merchant.id
                )
        );

    v_notification_json :=
        to_jsonb(
            v_notification
        );

    v_device_tokens :=
        public.fetch_device_tokens(
            v_merchant.country_code,
            v_merchant.id
        );

    /*
     * Create financial transaction.
     *
     * Accounts is the business user who received the
     * physical cash and created TransactionData.
     */
    v_stage :=
        'create financial transaction';

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
            'Credit-agent cash settlement received from merchant %s by accounts user %s',
            v_merchant.id,
            v_accounts.id
        ),

        v_accounts.id,
        v_amount,
        v_currency_code,
        v_merchant.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post:
     *
     * Dr Bank/Cash Reserve
     * Cr Agent Cash Holding
     */
    v_stage :=
        'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_merchant.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            p_transaction_type,

        p_created_by =>
            v_accounts.id,

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
     * Lock the country treasury wallet.
     */
    v_stage :=
        'lock treasury wallet';

    select wallet_record.*
    into v_treasury_wallet
    from public.wallet
        wallet_record
    where wallet_record.country_code =
          v_merchant.country_code

      and wallet_record.user_id =
          v_treasury.id

      and lower(
          btrim(
              wallet_record.currency_code
          )
      ) =
          v_currency_code

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"
    for update;

    if not found then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;

    if not v_treasury_wallet.is_active then
        raise exception
            'TREASURY_WALLET_FROZEN';
    end if;

    /*
     * Accounts and merchant do not have financial-wallet
     * movements. Only the country treasury wallet is
     * credited.
     */
    v_stage :=
        'credit treasury wallet';

    update public.wallet
    set
        balance =
            balance +
            v_amount
    where id =
          v_treasury_wallet.id

      and is_active =
          true;

    if not found then
        raise exception
            'TREASURY_WALLET_UPDATE_FAILED';
    end if;

    insert into public.wallet_entry (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        wallet_id,
        currency_code,
        country_code,
        debit,
        credit,
        created_by
    )
    values (
        v_document_number,
        v_reference,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_treasury_wallet.id,
        v_currency_code,
        v_merchant.country_code,
        0,
        v_amount,
        v_accounts.id
    );

    /*
     * Update the treasury wallet snapshot.
     *
     * The first wallet amount is debit/outgoing.
     * The second wallet amount is credit/incoming.
     */
    perform public.update_wallet_balance_snapshot(
        p_transaction_type,
        v_treasury.id,
        v_treasury.id,
        null,
        v_currency_code,
        'treasury'::public."WalletOwnerType",
        'treasury'::public."WalletOwnerType",
        0,
        v_amount,
        v_fiscal_year,
        v_period,
        v_merchant.country_code,
        0
    );

    /*
     * Reduce the merchant cash-holding balance and create
     * the immutable credit-agent entry.
     */
    v_stage :=
        'post credit agent cash settlement';

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
            0,

        p_credit_cash_holding =>
            v_amount,

        p_created_by =>
            v_accounts.id
    );

    /*
     * Audit the accounts user who received the cash.
     */
    v_stage :=
        'create audit log';

    insert into public.audit_log (
        user_id,
        country_code,
        fiscal_year,
        period,
        action_type,
        entity_type,
        entity_id,
        document_number,
        old_value,
        new_value,
        metadata,
        ip_address
    )
    values (
        v_accounts.id,
        v_merchant.country_code,
        v_fiscal_year,
        v_period,
        'credit_agent_cash_settled'::public."AuditActionType",
        'credit_agent_account',
        v_credit_account.id::text,
        v_document_number,

        jsonb_build_object(
            'cash_holding_balance',
            v_cash_holding_before::text
        ),

        jsonb_build_object(
            'cash_holding_balance',
            v_cash_holding_after::text
        ),

        jsonb_build_object(
            'merchant_id',
            v_merchant.id,

            'accounts_id',
            v_accounts.id,

            'treasury_id',
            v_treasury.id,

            'reference',
            v_reference,

            'currency_code',
            v_currency_code,

            'settled_amount',
            v_amount::text
        ),

        p_ip_address
    );

    /*
     * Mark the signed transaction successful.
     */
    v_stage :=
        'complete transaction state';

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

        v_reference,

        v_merchant.id,

        v_accounts.id,

        v_currency_code,

        v_amount::text,

        v_cash_holding_before::text,

        v_cash_holding_after::text,

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
                    'CREDIT_AGENT_CASH_SETTLEMENT_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
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

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    format(
                        'Check the Credit Agent Cash Settlement stage: %s',
                        v_stage
                    )
                );
end;
$function$
