CREATE OR REPLACE FUNCTION public.prepare_gold_buy(
    p_user_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_code text
)
RETURNS TABLE(
    user_id text,
    country_code text,
    user_wallet_address text,
    treasury_id text,
    treasury_wallet_address text,
    treasury_wallet_index integer,
    fiscal_year integer,
    period integer,
    document_prefix text,
    input_amount text,
    input_currency text,
    gold_price text,
    token_quantity text,
    gross_token_quantity text,
    token_fee text,
    gross_amount text,
    spread text,
    blockchain_code text,
    chain_id bigint,
    rpc_url text,
    explorer_url text,
    contract_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_amount numeric;
    v_currency text;

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_fiscal_year integer;
    v_period integer;

    v_transaction_state public.transaction_state%rowtype;

    v_fiat_mappings public.transaction_gl_mapping[];
    v_token_mappings public.transaction_gl_mapping[];

    v_fiat_components public.posting_component[];
    v_token_components public.posting_component[];

    v_pricing public.pricing_result;

    v_gold_price numeric := 0;
    v_token_quantity numeric := 0;
    v_gross_token_quantity numeric := 0;
    v_token_fee numeric := 0;

    v_gross_amount numeric := 0;
    v_spread numeric := 0;

    v_document_prefix text;

    v_blockchain_code text;
    v_chain_id bigint;
    v_rpc_url text;
    v_explorer_url text;
    v_contract_address text;

    v_sub_transaction_type public."TransactionType" :=
        'gold_token_buy_sub_tx'::public."TransactionType";

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

    IF p_user_id IS NULL
       OR btrim(p_user_id) = ''
    THEN
        RAISE EXCEPTION 'USER_ID_REQUIRED';
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
    INTO v_transaction_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND state_record.created_by = p_user_id
      AND state_record.user_id = p_user_id
      AND state_record.country_code = p_country_code
      AND state_record.transaction_type =
          'gold_token_buy'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_transaction_state.transaction_data
       IS DISTINCT FROM p_transaction
    THEN
        RAISE EXCEPTION 'TRANSACTION_DATA_MISMATCH';
    END IF;

    IF lower(btrim(v_transaction_state.blockchain_code))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION 'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF p_transaction ->> 'v' IS DISTINCT FROM 'v7' THEN
        RAISE EXCEPTION 'OPERATION_NOT_ALLOWED';
    END IF;

    /*
     * ==========================================================
     * 4. RESOLVE ACTIVE BLOCKCHAIN NETWORK
     * ==========================================================
     */

    v_stage := 'BLOCKCHAIN_NETWORK_RESOLUTION';

    SELECT
        n.chain_id,
        n.rpc_url,
        n.explorer_url,
        b.contract_address
    INTO
        v_chain_id,
        v_rpc_url,
        v_explorer_url,
        v_contract_address
    FROM public.supported_blockchain AS b
    JOIN public.supported_blockchain_network AS n
        ON n.blockchain_id = b.id
    WHERE b.code = v_blockchain_code
      AND b.is_active = true
      AND n.is_active = true
    ORDER BY
        n.is_default DESC NULLS LAST,
        n.id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NETWORK_NOT_CONFIGURED';
    END IF;

    IF v_chain_id IS NULL
       OR v_rpc_url IS NULL
       OR btrim(v_rpc_url) = ''
       OR v_contract_address IS NULL
       OR btrim(v_contract_address) = ''
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CONFIGURATION_INCOMPLETE';
    END IF;

    /*
     * ==========================================================
     * 5. VALIDATE BUYER ROLE
     * ==========================================================
     */

    v_stage := 'BUYER_ROLE_VALIDATION';

    IF NOT public.user_has_role(
        p_user_id,
        ARRAY[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'USER_NOT_AUTHORIZED';
    END IF;

    /*
     * ==========================================================
     * 6. VALIDATE INPUT CURRENCY AND AMOUNT
     * ==========================================================
     */

    v_stage := 'INPUT_VALIDATION';

    v_currency :=
        lower(nullif(btrim(p_transaction ->> 'c'), ''));

    IF v_currency IS NULL THEN
        RAISE EXCEPTION 'CURRENCY_MISSING';
    END IF;

    IF v_currency NOT IN ('usd', 'gold') THEN
        RAISE EXCEPTION 'UNSUPPORTED_GOLD_BUY_CURRENCY';
    END IF;

    BEGIN
        v_amount :=
            (p_transaction ->> 'a')::numeric / 100;
    EXCEPTION
        WHEN invalid_text_representation
          OR numeric_value_out_of_range
        THEN
            RAISE EXCEPTION 'INVALID_AMOUNT';
    END;

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 7. CALCULATE GOLD BUY PRICING
     * ==========================================================
     */

    v_stage := 'GOLD_BUY_PRICING';

    v_pricing :=
        public.calculate_gold_buy_pricing(
            'gold_token_buy'::public."TransactionType",
            v_amount,
            p_country_code,
            v_currency
        );

    v_gold_price :=
        coalesce(v_pricing.gold_price, 0);

    IF v_gold_price <= 0 THEN
        RAISE EXCEPTION 'INVALID_GOLD_PRICE';
    END IF;

    /*
     * ==========================================================
     * 8. FETCH BUYER AND TREASURY
     * ==========================================================
     */

    v_stage := 'FETCH_BUYER_AND_TREASURY';

    v_user :=
        public.fetch_user_by_id(p_user_id);

    v_treasury :=
        public.fetch_country_treasury(p_country_code);

    IF v_user.id IS NULL THEN
        RAISE EXCEPTION 'BUYER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION 'TREASURY_NOT_FOUND';
    END IF;

    IF v_user.wallet_address IS NULL
       OR btrim(v_user.wallet_address) = ''
    THEN
        RAISE EXCEPTION 'USER_WALLET_NOT_CONFIGURED';
    END IF;

    IF v_treasury.wallet_address IS NULL
       OR btrim(v_treasury.wallet_address) = ''
       OR v_treasury.wallet_index IS NULL
    THEN
        RAISE EXCEPTION
            'TREASURY_WALLET_NOT_CONFIGURED';
    END IF;

    IF v_user.country_code IS DISTINCT FROM p_country_code THEN
        RAISE EXCEPTION 'OPERATION_NOT_ALLOWED';
    END IF;

    /*
     * ==========================================================
     * 9. FETCH FISCAL PERIOD
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
     * 10. FETCH FIAT GL MAPPINGS
     * ==========================================================
     */

    v_stage := 'FETCH_GOLD_BUY_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_fiat_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_buy'::public."TransactionType"
    ) AS mapping_record;

    IF v_fiat_mappings IS NULL
       OR cardinality(v_fiat_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_BUY_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 11. FETCH GOLD SUB-TRANSACTION GL MAPPINGS
     * ==========================================================
     */

    v_stage := 'FETCH_GOLD_SUB_TX_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_token_mappings
    FROM public.fetch_gl_mappings(
        v_sub_transaction_type
    ) AS mapping_record;

    IF v_token_mappings IS NULL
       OR cardinality(v_token_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_BUY_TOKEN_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 12. BUILD FIAT POSTING COMPONENTS
     * ==========================================================
     */

    v_stage := 'BUILD_FIAT_COMPONENTS';

    v_fiat_components :=
        public.build_posting_components(
            'gold_token_buy'::public."TransactionType",
            v_amount,
            v_fiat_mappings,
            p_country_code,
            v_currency,
            false
        );

    IF v_fiat_components IS NULL
       OR cardinality(v_fiat_components) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_BUY_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 13. BUILD GOLD POSTING COMPONENTS
     * ==========================================================
     */

    v_stage := 'BUILD_GOLD_COMPONENTS';

    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_amount,
            v_token_mappings,
            p_country_code,
            v_currency,
            true
        );

    IF v_token_components IS NULL
       OR cardinality(v_token_components) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_BUY_TOKEN_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 14. EXTRACT GOLD TOKEN QUANTITIES
     * ==========================================================
     */

    v_stage := 'EXTRACT_GOLD_QUANTITY';

    SELECT
        coalesce(component.debit_amount, 0),
        coalesce(component.credit_amount, 0)
    INTO
        v_token_quantity,
        v_gross_token_quantity
    FROM unnest(v_token_components) AS component(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component.component_type =
        'principal'::public."ComponentType"
    LIMIT 1;

    v_token_quantity :=
        public.round_down(
            coalesce(v_token_quantity, 0)
        );

    v_gross_token_quantity :=
        public.round_down(
            coalesce(v_gross_token_quantity, 0)
        );

    IF v_token_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY';
    END IF;

    /*
     * ==========================================================
     * 15. EXTRACT GOLD TOKEN FEE
     * ==========================================================
     */

    v_stage := 'EXTRACT_TOKEN_FEE';

    SELECT coalesce(component.debit_amount, 0)
    INTO v_token_fee
    FROM unnest(v_token_components) AS component(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component.component_type =
        'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_token_fee :=
        public.round_down(
            coalesce(v_token_fee, 0)
        );

    /*
     * ==========================================================
     * 16. EXTRACT FIAT GROSS AMOUNT
     * ==========================================================
     */

    v_stage := 'EXTRACT_GROSS_AMOUNT';

    SELECT coalesce(component.debit_amount, 0)
    INTO v_gross_amount
    FROM unnest(v_fiat_components) AS component(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component.component_type =
        'principal'::public."ComponentType"
    LIMIT 1;

    v_gross_amount :=
        coalesce(v_gross_amount, 0);

    IF v_gross_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_GROSS_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 17. EXTRACT TRADING SPREAD
     * ==========================================================
     */

    v_stage := 'EXTRACT_TRADING_SPREAD';

    SELECT coalesce(component.credit_amount, 0)
    INTO v_spread
    FROM unnest(v_fiat_components) AS component(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component.component_type =
        'trading_spread'::public."ComponentType"
    LIMIT 1;

    v_spread :=
        coalesce(v_spread, 0);

    /*
     * ==========================================================
     * 18. FETCH DOCUMENT PREFIX
     * ==========================================================
     */

    v_stage := 'FETCH_DOCUMENT_PREFIX';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_buy'::public."TransactionType"
        );

    /*
     * ==========================================================
     * 19. RETURN TRUSTED PREPARATION
     * ==========================================================
     */

    v_stage := 'RETURN_PREPARATION';

    RETURN QUERY
    SELECT
        v_user.id,
        p_country_code,
        v_user.wallet_address,

        v_treasury.id,
        v_treasury.wallet_address,
        v_treasury.wallet_index::integer,

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_amount::text,
        v_currency,
        v_gold_price::text,

        v_token_quantity::text,
        v_gross_token_quantity::text,
        v_token_fee::text,

        v_gross_amount::text,
        v_spread::text,

        v_blockchain_code,
        v_chain_id,
        v_rpc_url,
        v_explorer_url,
        v_contract_address;

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
                'PREPARE_GOLD_BUY_FAILED at [%s]: %s',
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
                'Check the Gold Buy preparation stage reported in the error'
            );
END;
$function$;