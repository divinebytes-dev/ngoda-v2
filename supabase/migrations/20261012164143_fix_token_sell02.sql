DROP FUNCTION IF EXISTS public.prepare_gold_sell(
    text,
    jsonb,
    text,
    text
);

CREATE OR REPLACE FUNCTION public.prepare_gold_sell(
    p_seller_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_code text
)
RETURNS TABLE(
    seller_id text,
    seller_wallet_address text,
    seller_wallet_index bigint,
    treasury_id text,
    treasury_wallet_address text,
    country_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,
    input_amount text,
    input_currency text,
    gold_price text,
    token_quantity text,
    token_fee_equivalent text,
    gross_amount text,
    net_amount text,
    fiat_fee text,
    trading_spread text,
    government_tax text,
    blockchain_code text,
    sell_mappings public.transaction_gl_mapping[],
    sell_components public.posting_component[],
    token_mappings public.transaction_gl_mapping[],
    token_components public.posting_component[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_state public.transaction_state%rowtype;
    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_reference text;
    v_input_currency text;
    v_blockchain_code text;

    v_raw_input_amount numeric;
    v_input_amount numeric;

    v_pricing public.pricing_result;
    v_gold_price numeric := 0;

    v_token_quantity numeric := 0;
    v_token_fee_equivalent numeric := 0;

    v_gross_amount numeric := 0;
    v_net_amount numeric := 0;
    v_fiat_fee numeric := 0;
    v_trading_spread numeric := 0;
    v_government_tax numeric := 0;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_sell_mappings public.transaction_gl_mapping[];
    v_sell_components public.posting_component[];

    v_token_mappings public.transaction_gl_mapping[];
    v_token_components public.posting_component[];

    v_seller_gold_balance numeric;
    v_seller_gold_wallet_active boolean;

    v_stage text := 'INITIALIZATION';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'SERVICE_ROLE_VALIDATION';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION 'TRANSACTION_DATA_IS_MISSING';
    END IF;

    IF p_seller_id IS NULL
       OR btrim(p_seller_id) = ''
    THEN
        RAISE EXCEPTION 'SELLER_ID_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION 'COUNTRY_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN
     * ==========================================================
     */
    v_stage := 'BLOCKCHAIN_VALIDATION';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Validate against the active blockchain and its
     * configured active network.
     *
     * Do not call fetch_active_supported_blockchain here,
     * because that RPC requires an authenticated user,
     * while this function is invoked with the service role.
     */
    PERFORM 1
    FROM public.supported_blockchain AS b
    WHERE b.code = v_blockchain_code
      AND b.is_active = true
      AND EXISTS (
          SELECT 1
          FROM public.supported_blockchain_network AS n
          WHERE n.blockchain_id = b.id
            AND n.is_active = true
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    /*
     * ==========================================================
     * 3. VALIDATE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'TRANSACTION_STATE_VALIDATION';

    SELECT state_record.*
    INTO v_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND state_record.created_by = p_seller_id
      AND state_record.user_id = p_seller_id
      AND state_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_state.transaction_data IS DISTINCT FROM p_transaction THEN
        RAISE EXCEPTION 'TRANSACTION_DATA_MISMATCH';
    END IF;

    IF lower(btrim(v_state.blockchain_code))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION 'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF p_transaction ->> 'v' IS DISTINCT FROM 'v7' THEN
        RAISE EXCEPTION 'OPERATION_NOT_ALLOWED';
    END IF;

    v_reference :=
        nullif(btrim(p_transaction ->> 'r'), '');

    IF v_reference IS NULL THEN
        RAISE EXCEPTION 'REFERENCE_IS_REQUIRED';
    END IF;

    IF v_state.reference IS DISTINCT FROM v_reference THEN
        RAISE EXCEPTION 'TRANSACTION_REFERENCE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 4. VALIDATE INPUT CURRENCY AND AMOUNT
     * ==========================================================
     */
    v_stage := 'INPUT_VALIDATION';

    v_input_currency :=
        lower(nullif(btrim(p_transaction ->> 'c'), ''));

    IF v_input_currency IS NULL THEN
        RAISE EXCEPTION 'CURRENCY_IS_REQUIRED';
    END IF;

    IF v_input_currency NOT IN ('usd', 'gold') THEN
        RAISE EXCEPTION 'UNSUPPORTED_GOLD_SELL_CURRENCY';
    END IF;

    /*
     * Preserve the existing signed transaction serialization.
     * transaction.a is divided by 100.
     */
    BEGIN
        v_raw_input_amount :=
            (p_transaction ->> 'a')::numeric / 100;
    EXCEPTION
        WHEN invalid_text_representation
          OR numeric_value_out_of_range
        THEN
            RAISE EXCEPTION 'INVALID_AMOUNT';
    END;

    IF v_raw_input_amount IS NULL
       OR v_raw_input_amount <= 0
    THEN
        RAISE EXCEPTION 'INVALID_AMOUNT';
    END IF;

    v_input_amount := v_raw_input_amount;

    /*
     * ==========================================================
     * 5. CALCULATE GOLD SELL PRICING
     * ==========================================================
     */
    v_stage := 'GOLD_SELL_PRICING';

    v_pricing :=
        public.calculate_gold_sell_pricing(
            'gold_token_sell'::public."TransactionType",
            v_input_amount,
            p_country_code,
            v_input_currency
        );

    v_gold_price :=
        coalesce(v_pricing.gold_price, 0);

    IF v_gold_price <= 0 THEN
        RAISE EXCEPTION 'INVALID_GOLD_PRICE';
    END IF;

    /*
     * ==========================================================
     * 6. FETCH SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'FETCH_SELLER_AND_TREASURY';

    v_seller :=
        public.fetch_user_by_id(p_seller_id);

    v_treasury :=
        public.fetch_country_treasury(p_country_code);

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION 'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION 'TREASURY_NOT_FOUND';
    END IF;

    IF v_seller.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION 'SELLER_NOT_ACTIVE';
    END IF;

    IF v_treasury.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION 'TREASURY_NOT_ACTIVE';
    END IF;

    IF lower(btrim(v_seller.country_code))
       IS DISTINCT FROM lower(btrim(p_country_code))
    THEN
        RAISE EXCEPTION 'SELLER_COUNTRY_MISMATCH';
    END IF;

    IF lower(btrim(v_treasury.country_code))
       IS DISTINCT FROM lower(btrim(p_country_code))
    THEN
        RAISE EXCEPTION 'TREASURY_COUNTRY_MISMATCH';
    END IF;

    IF v_seller.wallet_address IS NULL
       OR btrim(v_seller.wallet_address) = ''
    THEN
        RAISE EXCEPTION 'SELLER_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * Wallet index zero is valid.
     */
    IF v_seller.wallet_index IS NULL THEN
        RAISE EXCEPTION
            'SELLER_WALLET_INDEX_NOT_CONFIGURED';
    END IF;

    IF v_treasury.wallet_address IS NULL
       OR btrim(v_treasury.wallet_address) = ''
    THEN
        RAISE EXCEPTION 'TREASURY_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * ==========================================================
     * 7. FETCH FISCAL PERIOD
     * ==========================================================
     */
    v_stage := 'FETCH_FISCAL_PERIOD';

    SELECT
        fp.fiscal_year,
        fp.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        p_country_code
    ) AS fp;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FISCAL_PERIOD_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 8. FETCH GOLD SELL GL MAPPINGS
     * ==========================================================
     */
    v_stage := 'FETCH_GOLD_SELL_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_sell_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_sell'::public."TransactionType"
    ) AS mapping_record;

    IF v_sell_mappings IS NULL
       OR cardinality(v_sell_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 9. FETCH GOLD SUB-TRANSACTION GL MAPPINGS
     * ==========================================================
     */
    v_stage := 'FETCH_GOLD_SUB_TX_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_token_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_sell_sub_tx'::public."TransactionType"
    ) AS mapping_record;

    IF v_token_mappings IS NULL
       OR cardinality(v_token_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_SUB_TX_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 10. BUILD FIAT POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'BUILD_FIAT_COMPONENTS';

    v_sell_components :=
        public.build_posting_components(
            'gold_token_sell'::public."TransactionType",
            v_input_amount,
            v_sell_mappings,
            p_country_code,
            v_input_currency,
            false
        );

    IF v_sell_components IS NULL
       OR cardinality(v_sell_components) = 0
    THEN
        RAISE EXCEPTION 'GOLD_SELL_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 11. BUILD GOLD POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'BUILD_GOLD_COMPONENTS';

    /*
     * Reverse remains true because Gold tokens
     * are treated as assets in the posting calculation.
     */
    v_token_components :=
        public.build_posting_components(
            'gold_token_sell_sub_tx'::public."TransactionType",
            v_input_amount,
            v_token_mappings,
            p_country_code,
            v_input_currency,
            true
        );

    IF v_token_components IS NULL
       OR cardinality(v_token_components) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_TOKEN_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 12. EXTRACT GOLD TOKEN QUANTITY
     * ==========================================================
     */
    v_stage := 'EXTRACT_GOLD_QUANTITY';

    SELECT coalesce(
        component_record.credit_amount,
        0
    )
    INTO v_token_quantity
    FROM unnest(v_token_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'principal'::public."ComponentType"
    LIMIT 1;

    /*
     * Gold precision: six decimal places, rounded down.
     */
    v_token_quantity :=
        trunc(coalesce(v_token_quantity, 0), 6);

    IF v_token_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_TOKEN_QUANTITY';
    END IF;

    /*
     * ==========================================================
     * 13. VALIDATE SELLER GOLD WALLET ON SELECTED BLOCKCHAIN
     * ==========================================================
     */
    v_stage := 'VALIDATE_SELLER_GOLD_WALLET';

    /*
     * This is a preliminary balance validation.
     *
     * The definitive debit and sufficient-balance check
     * remain in post_wallet_entries, which locks the wallet
     * and performs the balance update atomically.
     */
    SELECT
        w.balance,
        w.is_active
    INTO
        v_seller_gold_balance,
        v_seller_gold_wallet_active
    FROM public.wallet AS w
    WHERE w.user_id = p_seller_id
      AND w.country_code = lower(btrim(p_country_code))
      AND w.currency_code = 'gold'
      AND w.owner_type =
          'customer'::public."WalletOwnerType"
      AND w.blockchain_code = v_blockchain_code
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SELLER_GOLD_WALLET_NOT_FOUND';
    END IF;

    IF v_seller_gold_wallet_active IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'SELLER_GOLD_WALLET_FROZEN';
    END IF;

    IF coalesce(v_seller_gold_balance, 0) <
       v_token_quantity
    THEN
        RAISE EXCEPTION 'INSUFFICIENT_GOLD_BALANCE';
    END IF;

    /*
     * ==========================================================
     * 14. EXTRACT GOLD-EQUIVALENT FEE
     * ==========================================================
     */
    v_stage := 'EXTRACT_TOKEN_FEE';

    /*
     * This is reporting/calculation data.
     * It is not added to the on-chain transfer quantity.
     */
    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_token_fee_equivalent
    FROM unnest(v_token_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_token_fee_equivalent :=
        trunc(coalesce(v_token_fee_equivalent, 0), 6);

    /*
     * ==========================================================
     * 15. EXTRACT GROSS AND NET FIAT VALUES
     * ==========================================================
     */
    v_stage := 'EXTRACT_GROSS_AND_NET';

    SELECT
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    INTO
        v_gross_amount,
        v_net_amount
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'principal'::public."ComponentType"
    LIMIT 1;

    v_gross_amount := coalesce(v_gross_amount, 0);
    v_net_amount := coalesce(v_net_amount, 0);

    IF v_gross_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_GROSS_AMOUNT';
    END IF;

    IF v_net_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_NET_AMOUNT';
    END IF;

    IF v_net_amount > v_gross_amount THEN
        RAISE EXCEPTION
            'NET_AMOUNT_EXCEEDS_GROSS_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 16. EXTRACT FIAT TRANSACTION FEE
     * ==========================================================
     */
    v_stage := 'EXTRACT_FIAT_FEE';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_fiat_fee
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_fiat_fee := coalesce(v_fiat_fee, 0);

    IF v_fiat_fee < 0 THEN
        RAISE EXCEPTION 'INVALID_FIAT_FEE';
    END IF;

    /*
     * ==========================================================
     * 17. EXTRACT TRADING SPREAD
     * ==========================================================
     */
    v_stage := 'EXTRACT_TRADING_SPREAD';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_trading_spread
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'trading_spread'::public."ComponentType"
    LIMIT 1;

    v_trading_spread :=
        coalesce(v_trading_spread, 0);

    IF v_trading_spread < 0 THEN
        RAISE EXCEPTION 'INVALID_TRADING_SPREAD';
    END IF;

    /*
     * ==========================================================
     * 18. EXTRACT GOVERNMENT TAX
     * ==========================================================
     */
    v_stage := 'EXTRACT_GOVERNMENT_TAX';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_government_tax
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'government_tax'::public."ComponentType"
    LIMIT 1;

    v_government_tax :=
        coalesce(v_government_tax, 0);

    IF v_government_tax < 0 THEN
        RAISE EXCEPTION 'INVALID_GOVERNMENT_TAX';
    END IF;

    /*
     * ==========================================================
     * 19. VALIDATE POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'VALIDATE_POSTING_COMPONENTS';

    v_sell_components :=
        public.validate_components(
            v_sell_components
        );

    v_token_components :=
        public.validate_components(
            v_token_components
        );

    /*
     * ==========================================================
     * 20. FETCH DOCUMENT PREFIX
     * ==========================================================
     */
    v_stage := 'FETCH_DOCUMENT_PREFIX';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_sell'::public."TransactionType"
        );

    IF v_document_prefix IS NULL
       OR btrim(v_document_prefix) = ''
    THEN
        RAISE EXCEPTION 'DOCUMENT_PREFIX_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 21. RETURN TRUSTED PREPARATION
     * ==========================================================
     */
    v_stage := 'RETURN_PREPARATION';

    RETURN QUERY
    SELECT
        v_seller.id,
        v_seller.wallet_address,
        v_seller.wallet_index::bigint,

        v_treasury.id,
        v_treasury.wallet_address,

        lower(btrim(p_country_code)),

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_input_amount::text,
        v_input_currency,
        v_gold_price::text,

        v_token_quantity::text,
        v_token_fee_equivalent::text,

        v_gross_amount::text,
        v_net_amount::text,
        v_fiat_fee::text,
        v_trading_spread::text,
        v_government_tax::text,

        v_blockchain_code,

        v_sell_mappings,
        v_sell_components,

        v_token_mappings,
        v_token_components;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'PREPARE_GOLD_SELL_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the Gold Sell preparation stage reported in the error'
            );
END;
$function$;