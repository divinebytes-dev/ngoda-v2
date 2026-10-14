CREATE OR REPLACE FUNCTION public.execute_my_treasury_funding(
    p_transaction_type public."TransactionType",
    p_currency_code text DEFAULT NULL::text,
    p_amount numeric DEFAULT NULL::numeric,
    p_document_number text DEFAULT NULL::text,
    p_ip_address text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_executor public.users%rowtype;
    v_treasury public.users%rowtype;

    v_original_transaction
        public.financial_transaction%rowtype;

    v_is_reversal boolean;

    v_currency_code text;
    v_amount numeric;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;

    v_transaction_id
        public.financial_transaction.id%type;

    v_treasury_wallet
        public.wallet%rowtype;

    v_balance_before numeric;
    v_balance_after numeric;

    v_credit_amount numeric := 0;
    v_debit_amount numeric := 0;

    v_description text;

    v_audit_action
        public."AuditActionType";

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * =========================================================
     * AUTHENTICATION AND AUTHORIZATION
     * =========================================================
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
     * =========================================================
     * TRANSACTION TYPE
     * =========================================================
     */

    v_stage := 'validate transaction type';

    if p_transaction_type not in (
        'treasury_funding'::public."TransactionType",
        'treasury_funding_reversal'::public."TransactionType"
    ) then
        raise exception
            'INVALID_TREASURY_FUNDING_TRANSACTION_TYPE';
    end if;

    v_is_reversal :=
        p_transaction_type =
        'treasury_funding_reversal'::public."TransactionType";

    /*
     * =========================================================
     * AUTHENTICATED USER
     * =========================================================
     */

    v_stage := 'fetch authenticated user';

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
     * The old service received countryCode from its caller.
     *
     * In the RPC architecture we derive it from the authenticated
     * treasury user so the client cannot fund another country's
     * treasury.
     */

    /*
     * =========================================================
     * COUNTRY TREASURY
     * =========================================================
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
     * =========================================================
     * NORMAL TREASURY FUNDING
     * =========================================================
     */

    if not v_is_reversal then
        v_stage := 'validate funding input';

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

        v_amount :=
            public.round_down(
                p_amount
            );

        if v_amount is null
           or v_amount <= 0
        then
            raise exception
                'INVALID_AMOUNT';
        end if;

        v_description :=
            'Funding treasury';

        v_audit_action :=
            'treasury_funded'::public."AuditActionType";
    end if;

    /*
     * =========================================================
     * TREASURY FUNDING REVERSAL
     * =========================================================
     *
     * The original service received:
     *
     *     currency_code
     *     amount
     *     document_number
     *
     * and used document_number as the financial transaction
     * reference.
     *
     * In the RPC version we make reversal safer by resolving the
     * amount and currency from the original treasury-funding
     * document instead of trusting client-supplied values.
     */

    if v_is_reversal then
        v_stage := 'validate reversal document';

        if nullif(
            btrim(p_document_number),
            ''
        ) is null
        then
            raise exception
                'DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL';
        end if;

        /*
         * Lock the original treasury funding transaction.
         */
        v_stage := 'fetch original treasury funding';

        select
            transaction_record.*
        into
            v_original_transaction
        from public.financial_transaction
            transaction_record
        where transaction_record.document_number =
              btrim(p_document_number)

          and transaction_record.country_code =
              v_executor.country_code

        for update;

        if not found then
            raise exception
                'DOCUMENT_NOT_FOUND';
        end if;

        if v_original_transaction.transaction_type <>
           'treasury_funding'::public."TransactionType"
        then
            raise exception
                'DOCUMENT_IS_NOT_TREASURY_FUNDING';
        end if;

        /*
         * Prevent the same treasury funding from being
         * reversed more than once.
         */
        v_stage := 'check duplicate reversal';

        perform 1
        from public.financial_transaction
            reversal_record
        where reversal_record.country_code =
              v_executor.country_code

          and reversal_record.transaction_type =
              'treasury_funding_reversal'::public."TransactionType"

          and reversal_record.reversal_of =
              v_original_transaction.document_number
        limit 1;

        if found then
            raise exception
                'DOCUMENT_ALREADY_REVERSED';
        end if;

        v_currency_code :=
            lower(
                v_original_transaction.currency_code
            );

        v_amount :=
            v_original_transaction.gross_amount;

        if v_amount is null
           or v_amount <= 0
        then
            raise exception
                'INVALID_ORIGINAL_AMOUNT';
        end if;

        v_description :=
            'Treasury funding reversal';

        v_audit_action :=
            'treasury_fund_reversed'::public."AuditActionType";
    end if;

    /*
     * =========================================================
     * GL MAPPINGS
     * =========================================================
     *
     * Equivalent to:
     *
     *     fetchGlMappings(transactionType)
     */

    v_stage := 'fetch gl mappings';

    select
        array_agg(mapping_record)
    into
        v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'TREASURY_FUNDING_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * =========================================================
     * POSTING COMPONENTS
     * =========================================================
     *
     * Equivalent to:
     *
     *     buildPostingComponents({
     *         transactionType,
     *         principal: amount,
     *         mappings,
     *         countryCode,
     *         currencyCode
     *     })
     */

    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_amount,
            v_mappings,
            v_executor.country_code,
            v_currency_code,
            false
        );

    /*
     * =========================================================
     * FISCAL PERIOD
     * =========================================================
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
     * =========================================================
     * DOCUMENT PREFIX
     * =========================================================
     *
     * Old code:
     *
     * treasury_funding
     *     -> TREASURY-FUND
     *
     * treasury_funding_reversal
     *     -> REV-TREASURY-FUND
     *
     * We preserve those exact prefixes.
     */

    v_document_prefix :=
        case
            when v_is_reversal then
                'REV-TREASURY-FUND'
            else
                'TREASURY-FUND'
        end;

    /*
     * =========================================================
     * DOCUMENT NUMBER
     * =========================================================
     */

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_executor.country_code
        );

    /*
     * =========================================================
     * TREASURY WALLET
     * =========================================================
     *
     * This deliberately mirrors the original Prisma upsert.
     *
     * Funding:
     *     balance = balance + amount
     *
     * Reversal:
     *     balance = balance - amount
     *
     * There is only ONE treasury wallet involved.
     */

    v_stage := 'lock treasury wallet';

    select
        wallet_record.*
    into
        v_treasury_wallet
    from public.wallet wallet_record
    where wallet_record.country_code =
          v_executor.country_code

      and wallet_record.user_id =
          v_treasury.id

      and wallet_record.currency_code =
          v_currency_code

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"

    for update;

    if found then
        v_balance_before :=
            coalesce(
                v_treasury_wallet.balance,
                0
            );

        if v_is_reversal then
            v_balance_after :=
                v_balance_before -
                v_amount;
        else
            v_balance_after :=
                v_balance_before +
                v_amount;
        end if;

        /*
         * Do not allow a reversal to make the treasury
         * wallet negative.
         */
        if v_balance_after < 0 then
            raise exception
                'INSUFFICIENT_TREASURY_BALANCE';
        end if;

        update public.wallet
        set balance =
                v_balance_after
        where id =
              v_treasury_wallet.id

        returning *
        into v_treasury_wallet;
    else
        /*
         * This mirrors the old Prisma upsert create path.
         *
         * A normal funding may create the treasury wallet.
         *
         * A reversal cannot create a missing wallet because
         * there would be nothing to reverse from.
         */
        if v_is_reversal then
            raise exception
                'TREASURY_WALLET_NOT_FOUND';
        end if;

        v_balance_before := 0;
        v_balance_after := v_amount;

        insert into public.wallet (
            user_id,
            currency_code,
            country_code,
            owner_type,
            balance,
            is_active
        )
        values (
            v_treasury.id,
            v_currency_code,
            v_executor.country_code,
            'treasury'::public."WalletOwnerType",
            v_amount,
            true
        )
        returning *
        into v_treasury_wallet;
    end if;

    /*
     * =========================================================
     * FINANCIAL TRANSACTION
     * =========================================================
     *
     * Original:
     *
     * reference: document_number ?? documentNo
     *
     * Normal funding therefore references itself.
     *
     * Reversal references the supplied/original document.
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
        country_code,
        reversal_of,
        reversed_by
    )
    values (
        v_document_number,

        case
            when v_is_reversal then
                v_original_transaction.document_number
            else
                v_document_number
        end,

        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_description,
        v_executor.id,
        v_amount,
        v_currency_code,
        v_executor.country_code,

        case
            when v_is_reversal then
                v_original_transaction.document_number
            else
                null
        end,

        case
            when v_is_reversal then
                v_executor.id
            else
                null
        end
    )
    returning id
    into v_transaction_id;

    /*
     * =========================================================
     * FINANCIAL ENTRIES
     * =========================================================
     */

    v_stage := 'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_executor.country_code,

        p_transaction_id =>
            v_transaction_id,

        p_transaction_type =>
            p_transaction_type,

        p_created_by =>
            v_executor.id,

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

        /*
         * The old service passed document_number here.
         *
         * Normal funding had no document_number.
         * Reversal supplied the original document number.
         */
        p_reference =>
            case
                when v_is_reversal then
                    v_original_transaction.document_number
                else
                    null
            end,

        p_deposit_type =>
            null
    );

    /*
     * =========================================================
     * WALLET ENTRY
     * =========================================================
     *
     * Exact old behaviour:
     *
     * treasury_funding:
     *     debit  = 0
     *     credit = amount
     *
     * treasury_funding_reversal:
     *     debit  = amount
     *     credit = 0
     */

    if v_is_reversal then
        v_debit_amount :=
            v_amount;

        v_credit_amount :=
            0;
    else
        v_debit_amount :=
            0;

        v_credit_amount :=
            v_amount;
    end if;

    v_stage := 'create treasury wallet entry';

    insert into public.wallet_entry (
        document_number,
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
        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_treasury_wallet.id,
        v_currency_code,
        v_executor.country_code,
        v_debit_amount,
        v_credit_amount,
        v_executor.id
    );

    /*
     * =========================================================
     * WALLET BALANCE SNAPSHOT
     * =========================================================
     *
     * Equivalent to the original:
     *
     * updateWalletBalanceSnapshot({
     *     sender_id,
     *     transactionType,
     *     receiver_id: treasury.id,
     *     currency_code,
     *     country_code,
     *     receiver_wallet_owner: treasury,
     *     sender_wallet_owner: treasury,
     *     receiver_amount: amount,
     *     sender_amount: amount,
     *     fiscal_year,
     *     period
     * })
     */

    v_stage := 'update treasury wallet balance snapshot';

    perform *
    from public.update_wallet_balance_snapshot(
        p_sender_id =>
            v_executor.id,

        p_transaction_type =>
            p_transaction_type,

        p_receiver_id =>
            v_treasury.id,

        p_currency_code =>
            v_currency_code,

        p_country_code =>
            v_executor.country_code,

        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_amount =>
            v_amount,

        p_sender_amount =>
            v_amount,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period
    );

    /*
     * =========================================================
     * AUDIT LOG
     * =========================================================
     */

    v_stage := 'create treasury audit log';

    insert into public.audit_log (
        fiscal_year,
        period,
        user_id,
        country_code,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata,
        document_number
    )
    values (
        v_fiscal_year,
        v_period,
        v_executor.id,
        v_executor.country_code,
        v_audit_action,
        'treasury',
        v_treasury.id,

        jsonb_build_object(
            'treasury_balance_before',
            v_balance_before
        ),

        jsonb_build_object(
            'treasury_balance_after',
            v_balance_after
        ),

        jsonb_build_object(
            'document_number',
            v_document_number,

            'reference',
            case
                when v_is_reversal then
                    v_original_transaction.document_number
                else
                    null
            end,

            'ip_address',
            p_ip_address
        ),

        v_document_number
    );

    /*
     * =========================================================
     * RESPONSE
     * =========================================================
     */

    return jsonb_build_object(
        'success',
        true,

        'transaction_type',
        p_transaction_type,

        'document_number',
        v_document_number,

        'reference',
        case
            when v_is_reversal then
                v_original_transaction.document_number
            else
                v_document_number
        end,

        'reversal_of',
        case
            when v_is_reversal then
                v_original_transaction.document_number
            else
                null
        end,

        'currency_code',
        v_currency_code,

        'amount',
        v_amount::text,

        'treasury_id',
        v_treasury.id,

        'balance_before',
        v_balance_before::text,

        'balance_after',
        v_balance_after::text
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
                'TREASURY_FUNDING_FAILED at [%s]: %s',
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
                'Check the Treasury Funding stage reported in the error'
            );
end;
$function$;