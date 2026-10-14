DROP FUNCTION IF EXISTS public.cash_withdrawal(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
);


CREATE OR REPLACE FUNCTION public.cash_withdrawal(
    p_agent_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text DEFAULT NULL::text
)
RETURNS TABLE(
    success boolean,
    document_no text,
    amount text,
    amount_usd text,
    sender_debit text,
    sender_debit_usd text,
    fee text,
    tax text,
    currency text,
    user_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_decimals numeric := 100;

    v_amount numeric;
    v_amount_usd numeric(20, 6) := 0;

    v_currency text;
    v_reference text;
    v_user_id text;
    v_version text;

    /*
     * Transaction-time conversion rate.
     *
     * For normal fiat currencies the configured rate
     * represents units of local currency per USD.
     *
     * For gold the rate represents USD per gram.
     */
    v_rate_to_usd numeric(20, 10);

    /*
     * Actual amount removed from the withdrawing user's
     * wallet, converted to USD using the same transaction
     * rate.
     */
    v_sender_debit_usd numeric(20, 6) := 0;

    v_fiscal_year integer;
    v_period integer;

    v_agent public.users%rowtype;
    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_transaction_state
        public.transaction_state%rowtype;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_component_totals
        public.component_totals;

    v_principal_amount numeric := 0;
    v_others_amount numeric := 0;

    v_fee numeric := 0;
    v_tax numeric := 0;
    v_commission_amount numeric := 0;

    v_tax_rate numeric := 0;
    v_commission_rate numeric := 0;

    v_aml_threshold numeric;

    v_user_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;
    v_user_notification_id text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;

begin
    /*
     * ==========================================================
     * VALIDATE TRANSACTION TYPE
     * ==========================================================
     */
    v_stage := 'validate transaction type';

    if p_transaction_type <>
       'cash_withdrawal'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_WITHDRAWAL_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;


    /*
     * ==========================================================
     * VALIDATE AND LOCK TRANSACTION STATE
     * ==========================================================
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
          p_agent_id
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
     * Ensure the service-role call uses the transaction
     * that created the processing state.
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
     * ==========================================================
     * VALIDATE TRANSACTION VERSION
     * ==========================================================
     */
    v_stage := 'validate transaction version';

    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    if v_version is distinct from 'v3' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    /*
     * ==========================================================
     * PARSE TRANSACTION
     * ==========================================================
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


    v_stage := 'parse withdrawing user';

    v_user_id :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_user_id is null then
        raise exception
            'USER_ID_MISSING';
    end if;


    if v_transaction_state.user_id
       is distinct from v_user_id
    then
        raise exception
            'TRANSACTION_USER_MISMATCH';
    end if;


    /*
     * ==========================================================
     * VALIDATE STORED APPROVAL
     * ==========================================================
     */
    v_stage := 'validate sender approval';

    if v_transaction_state.sender_approval is null
       or jsonb_typeof(
           v_transaction_state.sender_approval
       ) <> 'object'
    then
        raise exception
            'SENDER_APPROVAL_IS_MISSING';
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
     * ==========================================================
     * VALIDATE PARTICIPANT ROLES
     * ==========================================================
     */

    v_stage := 'validate agent role';

    if not public.user_has_role(
        p_agent_id,
        array[
            'agent'::public."Role",
            'vendor'::public."Role",
            'merchant'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'AGENT_NOT_AUTHORIZED';
    end if;


    v_stage := 'validate user role';

    if not public.user_has_role(
        v_user_id,
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
     * ==========================================================
     * FETCH PARTICIPANTS
     * ==========================================================
     */

    v_stage := 'fetch agent';

    v_agent :=
        public.fetch_user_by_id(
            p_agent_id
        );


    v_stage := 'fetch user';

    v_user :=
        public.fetch_user_by_id(
            v_user_id
        );


    v_stage := 'fetch treasury';

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );


    /*
     * ==========================================================
     * VALIDATE PARTICIPANTS
     * ==========================================================
     */
    v_stage := 'validate participants';

    if v_agent.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'AGENT_NOT_ACTIVE';
    end if;


    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;


    if v_agent.id = v_user.id then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    if v_agent.country_code is distinct from
       v_user.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    if v_agent.country_code is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;


    /*
     * ==========================================================
     * FETCH FISCAL PERIOD
     * ==========================================================
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


    if not found
       or v_fiscal_year is null
       or v_period is null
    then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * FETCH TRANSACTION-TIME USD RATE
     * ==========================================================
     *
     * We need USD values for Financial Intelligence.
     *
     * USD:
     *     amount_usd = amount
     *
     * GOLD:
     *     amount_usd = amount * USD-per-gram
     *
     * Other fiat:
     *     amount_usd = amount / local-currency-per-USD
     */

    v_stage := 'fetch USD conversion rate';


    if v_currency = 'usd' then
        v_rate_to_usd := 1;

    else
        /*
         * Use the same current-rate source already used
         * throughout the pricing layer.
         *
         * current_rates stores the current configured rate
         * for the transaction currency.
         */
        select
            current_rate.rate
        into
            v_rate_to_usd
        from public.current_rates
            current_rate
        where lower(current_rate.currency_code) =
              lower(v_currency)
        limit 1;


        if not found
           or v_rate_to_usd is null
           or v_rate_to_usd <= 0
        then
            raise exception
                'CURRENT_RATE_NOT_FOUND_%',
                v_currency;
        end if;
    end if;


    /*
     * Convert the actual requested withdrawal amount.
     */
    v_stage := 'calculate withdrawal amount USD';


    if v_currency = 'usd' then
        v_amount_usd :=
            round(
                v_amount,
                6
            );

    elsif v_currency = 'gold' then
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


    if v_amount_usd <= 0 then
        raise exception
            'INVALID_AMOUNT_USD';
    end if;


    /*
     * ==========================================================
     * FETCH GL MAPPINGS
     * ==========================================================
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
     * ==========================================================
     * BUILD POSTING COMPONENTS
     * ==========================================================
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
     * ==========================================================
     * EXTRACT COMPONENT TOTALS
     * ==========================================================
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
     * cash_withdrawal is gross-mode.
     *
     * Therefore v_principal_amount is the actual amount
     * removed from the withdrawing user's wallet.
     *
     * It must never be less than the amount requested.
     */
    if v_principal_amount < v_amount then
        raise exception
            'INVALID_FINAL_WITHDRAWAL_DEBIT';
    end if;


    /*
     * ==========================================================
     * CONVERT ACTUAL USER WALLET DEBIT TO USD
     * ==========================================================
     *
     * This conversion happens AFTER posting components are
     * built because v_principal_amount is the authoritative
     * wallet debit including the applicable charges.
     */

    v_stage := 'calculate sender debit USD';


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


    /*
     * ==========================================================
     * EXTRACT GOVERNMENT TAX
     * ==========================================================
     */
    v_stage := 'extract government tax';

    select coalesce(
        component.credit_amount,
        0
    )
    into v_tax
    from unnest(v_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'government_tax'::public."ComponentType"
    limit 1;


    v_tax :=
        coalesce(
            v_tax,
            0
        );


    /*
     * ==========================================================
     * EXTRACT WITHDRAWAL FEE
     * ==========================================================
     */
    v_stage := 'extract withdrawal fee';

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
          'withdrawal_fee'::public."ComponentType"
    limit 1;


    v_fee :=
        coalesce(
            v_fee,
            0
        );


    /*
     * ==========================================================
     * EXTRACT AGENT COMMISSION
     * ==========================================================
     */
    v_stage := 'extract agent commission';

    select coalesce(
        component.credit_amount,
        0
    )
    into v_commission_amount
    from unnest(v_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'agent_commission'::public."ComponentType"
    limit 1;


    v_commission_amount :=
        coalesce(
            v_commission_amount,
            0
        );


    /*
     * ==========================================================
     * VALIDATE REQUIRED CHARGES
     * ==========================================================
     */
    v_stage := 'validate charges';

    if v_tax <= 0 then
        raise exception
            'INVALID_TAX_AMOUNT';
    end if;


    if v_fee <= 0 then
        raise exception
            'INVALID_FEE_AMOUNT';
    end if;


    /*
     * ==========================================================
     * FETCH CONFIGURED SETTLEMENT RATES
     * ==========================================================
     */
    v_stage := 'fetch configured rates';

    v_tax_rate :=
        public.fetch_government_tax_rate(
            p_transaction_type,
            v_currency,
            p_country_code
        );


    v_commission_rate :=
        public.fetch_agent_commission_rate(
            p_transaction_type,
            v_currency,
            p_country_code
        );


    /*
     * ==========================================================
     * TRANSACTION LIMIT
     * ==========================================================
     *
     * v_principal_amount is the actual customer wallet
     * debit for this gross-mode transaction.
     */
    v_stage := 'enforce transaction limit';

    perform public.enforce_transaction_limit(
        v_user.id,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_currency,
        v_principal_amount,
        p_country_code
    );


    /*
     * ==========================================================
     * AML CONFIGURATION
     * ==========================================================
     */
    v_stage := 'fetch AML configuration';

    select aml_config_record.threshold_amount
    into v_aml_threshold
    from public.aml_config aml_config_record
    where aml_config_record.transaction_type =
          p_transaction_type
      and lower(
          aml_config_record.country_code
      ) = lower(p_country_code)
      and lower(
          aml_config_record.currency_code
      ) = lower(v_currency)
      and aml_config_record.is_active = true
    limit 1;


    /*
     * ==========================================================
     * USER NOTIFICATION
     * ==========================================================
     */
    v_stage := 'create user notification';

    v_user_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-01',
            0,
            coalesce(
                v_user.email,
                v_user.phone,
                v_user.id
            ),
            coalesce(
                v_agent.email,
                v_agent.phone,
                v_agent.id
            )
        );


    /*
     * ==========================================================
     * DEVICE TOKENS
     * ==========================================================
     */
    v_stage := 'fetch user device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_user.id
            ),
            array[]::text[]
        );


    /*
     * ==========================================================
     * DOCUMENT NUMBER
     * ==========================================================
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
     * ==========================================================
     * AML FLAG
     * ==========================================================
     */
    v_stage := 'create AML flag';

    if v_aml_threshold is not null
       and v_amount >= v_aml_threshold
    then
        insert into public.system_flag (
            country_code,
            fiscal_year,
            period,
            flag_name,
            is_active,
            triggered_by,
            reason
        )
        values (
            p_country_code,
            v_fiscal_year,
            v_period,
            'AML_' || v_document_number,
            true,
            v_user.id,
            'Withdrawal above AML threshold'
        );
    end if;


    /*
     * ==========================================================
     * FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage :=
        'insert financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        v_reference,
        p_transaction_type,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' cash withdrawal from agent ' ||
        coalesce(
            v_agent.email,
            v_agent.phone,
            v_agent.id
        ),
        v_agent.id,
        v_amount,
        v_currency,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;


    /*
     * ==========================================================
     * FINANCIAL LEDGER
     * ==========================================================
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
     * ==========================================================
     * WALLET MOVEMENT
     * ==========================================================
     *
     * WITHDRAWING USER:
     *
     *     debit = v_principal_amount
     *
     * This contains the entered withdrawal amount plus
     * applicable charges.
     *
     * RECEIVING AGENT:
     *
     *     credit = v_amount
     *
     * The agent receives only the entered withdrawal
     * amount.
     */
    v_stage := 'post wallet entries';

    perform *
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
            v_amount,

        p_debit_amount =>
            v_principal_amount,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'agent'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            'cash_withdrawal'::public."AuditActionType",

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            v_fee + v_tax,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            null,

        p_sender_notification =>
            v_user_notification
    );


    /*
     * ==========================================================
     * USER NOTIFICATION ID
     * ==========================================================
     */
    v_stage := 'fetch user notification ID';

    select notification_record.id::text
    into v_user_notification_id
    from public.notifications notification_record
    where notification_record.user_id =
          v_user.id
      and notification_record.reference =
          v_user_notification.payload
              ->> 'reference'
      and notification_record.transaction_type =
          p_transaction_type
    order by notification_record.created_at desc
    limit 1;


    if not found then
        raise exception
            'USER_NOTIFICATION_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * AGENT COMMISSION
     * ==========================================================
     */
    v_stage := 'insert agent commission';

    if v_commission_amount > 0 then
        insert into public.agent_commission (
            agent_id,
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
            v_agent.id,
            v_document_number,
            v_fiscal_year,
            v_period,
            p_transaction_type,
            v_currency,
            v_amount,
            v_fee,
            coalesce(
                v_commission_rate,
                0
            ),
            v_commission_amount,
            false,
            p_country_code
        );
    end if;


    /*
     * ==========================================================
     * GOVERNMENT TAX PAYABLE
     * ==========================================================
     */
    v_stage :=
        'insert government tax payable';

    if v_tax > 0 then
        insert into public.government_tax_payable (
            document_number,
            fiscal_year,
            period,
            transaction_type,
            currency_code,
            gross_amount,
            tax_amount,
            tax_rate,
            is_settled,
            country_code
        )
        values (
            v_document_number,
            v_fiscal_year,
            v_period,
            p_transaction_type,
            v_currency,
            v_amount,
            v_tax,
            coalesce(
                v_tax_rate,
                0
            ),
            false,
            p_country_code
        );
    end if;


    /*
     * ==========================================================
     * COMPLETE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'update transaction state';

    update public.transaction_state
    set
        user_id =
            v_user.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_agent_id
      and user_id =
          v_user.id
      and transaction_type =
          p_transaction_type
      and status =
          'processing'::public."TransactionStatus";


    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;


    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     *
     * Financial Intelligence will use:
     *
     * WITHDRAWING USER
     *
     * amount          = amount
     * amount_usd      = amount_usd
     * cash_amount     = sender_debit
     * cash_amount_usd = sender_debit_usd
     *
     * RECEIVING AGENT
     *
     * amount          = amount
     * amount_usd      = amount_usd
     * cash_amount     = amount
     * cash_amount_usd = amount_usd
     */
    v_stage := 'return cash withdrawal result';

    return query
    select
        true,
        v_document_number,
        v_amount::text,
        v_amount_usd::text,
        v_principal_amount::text,
        v_sender_debit_usd::text,
        v_fee::text,
        v_tax::text,
        v_currency,
        v_user_notification_id,
        v_device_tokens,
        v_user_notification.title,
        v_user_notification.body,
        v_user_notification.payload
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
                    'CASH_WITHDRAWAL_FAILED at [%s]: %s',
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
                    'Check the cash-withdrawal stage reported in the error'
                );
end;
$function$;