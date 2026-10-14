CREATE OR REPLACE FUNCTION public.get_my_multi_wallet_balances(
    p_blockchain_balances jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_context record;

    v_result jsonb;
    v_customer_wallet jsonb;
    v_customer_balances jsonb;

    v_blockchain_balances jsonb := '[]'::jsonb;

    v_item jsonb;
    v_currency_key text;
    v_currency_value jsonb;

    v_blockchain_code text;

    v_balance numeric;
    v_usd_value numeric;

    v_gold_rate numeric;
    v_gold_total_usd numeric := 0;
    v_fiat_total_usd numeric := 0;

    v_seen_codes text[] := ARRAY[]::text[];
BEGIN

    ------------------------------------------------------------
    -- 1. Authentication
    ------------------------------------------------------------

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    v_user_id := auth.uid()::text;

    ------------------------------------------------------------
    -- 2. Validate authenticated multi-wallet context
    ------------------------------------------------------------

    SELECT *
    INTO v_context
    FROM public.fetch_my_multi_wallet_context()
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- 3. Validate blockchain input
    ------------------------------------------------------------

    IF p_blockchain_balances IS NULL
       OR jsonb_typeof(p_blockchain_balances) <> 'array'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_BALANCES';
    END IF;

    ------------------------------------------------------------
    -- 4. Fetch existing multi-wallet balances
    ------------------------------------------------------------

    v_result :=
        public.get_multi_wallet_balances(
            v_user_id
        );

    IF v_result IS NULL
       OR jsonb_typeof(v_result) <> 'object'
    THEN
        RAISE EXCEPTION
            'INVALID_MULTI_WALLET_RESULT';
    END IF;

    ------------------------------------------------------------
    -- 5. Get current GOLD USD price
    ------------------------------------------------------------

    SELECT cr.rate_to_usd
    INTO v_gold_rate
    FROM public.current_rates cr
    WHERE lower(cr.currency_code) = 'gold'
    LIMIT 1;

    IF v_gold_rate IS NULL
       OR v_gold_rate <= 0
    THEN
        RAISE EXCEPTION
            'GOLD_RATE_NOT_AVAILABLE';
    END IF;

    ------------------------------------------------------------
    -- 6. Read Personal Wallet
    ------------------------------------------------------------

    v_customer_wallet :=
        COALESCE(
            v_result -> 'customerWallet',
            '{}'::jsonb
        );

    IF jsonb_typeof(v_customer_wallet) <> 'object' THEN
        RAISE EXCEPTION
            'INVALID_CUSTOMER_WALLET';
    END IF;

    v_customer_balances :=
        COALESCE(
            v_customer_wallet -> 'balances',
            '{}'::jsonb
        );

    IF jsonb_typeof(v_customer_balances) <> 'object' THEN
        RAISE EXCEPTION
            'INVALID_CUSTOMER_FIAT_BALANCES';
    END IF;

    ------------------------------------------------------------
    -- 7. Remove aggregate GOLD from fiat balances
    ------------------------------------------------------------

    SELECT COALESCE(
        jsonb_object_agg(key, value),
        '{}'::jsonb
    )
    INTO v_customer_balances
    FROM jsonb_each(v_customer_balances)
    WHERE lower(key) <> 'gold';

    ------------------------------------------------------------
    -- 8. Calculate fiat USD total
    ------------------------------------------------------------

    FOR v_currency_key, v_currency_value IN
        SELECT key, value
        FROM jsonb_each(v_customer_balances)
    LOOP
        IF jsonb_typeof(v_currency_value) <> 'object' THEN
            RAISE EXCEPTION
                'INVALID_FIAT_BALANCE: %',
                v_currency_key;
        END IF;

        v_fiat_total_usd :=
            v_fiat_total_usd +
            COALESCE(
                NULLIF(
                    v_currency_value ->> 'usd_value',
                    ''
                )::numeric,
                0
            );
    END LOOP;

    ------------------------------------------------------------
    -- 9. Process GOLD balances per blockchain
    ------------------------------------------------------------

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(
            p_blockchain_balances
        )
    LOOP

        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE';
        END IF;

        v_blockchain_code :=
            lower(
                btrim(
                    COALESCE(
                        v_item ->> 'blockchain_code',
                        ''
                    )
                )
            );

        IF v_blockchain_code = '' THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_CODE_REQUIRED';
        END IF;

        --------------------------------------------------------
        -- Reject duplicate blockchain entries
        --------------------------------------------------------

        IF v_blockchain_code = ANY(v_seen_codes) THEN
            RAISE EXCEPTION
                'DUPLICATE_BLOCKCHAIN_BALANCE: %',
                v_blockchain_code;
        END IF;

        v_seen_codes :=
            array_append(
                v_seen_codes,
                v_blockchain_code
            );

        --------------------------------------------------------
        -- Read GOLD balance from blockchain helper
        --
        -- usd_value is NOT expected from the Edge Function.
        --------------------------------------------------------

        IF NULLIF(
            btrim(v_item ->> 'balance'),
            ''
        ) IS NULL THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_BALANCE_REQUIRED';
        END IF;

        v_balance :=
            (v_item ->> 'balance')::numeric;

        IF v_balance < 0 THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE_VALUE';
        END IF;

        --------------------------------------------------------
        -- Calculate USD equivalent
        --------------------------------------------------------

        v_usd_value :=
            ROUND(
                v_balance * v_gold_rate,
                2
            );

        v_gold_total_usd :=
            v_gold_total_usd +
            v_usd_value;

        --------------------------------------------------------
        -- Preserve GOLD balance for each blockchain
        --------------------------------------------------------

        v_blockchain_balances :=
            v_blockchain_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'blockchain_code',
                    v_blockchain_code,
                    'currency_code',
                    'gold',
                    'balance',
                    v_balance::text,
                    'usd_value',
                    v_usd_value::text
                )
            );

    END LOOP;

    ------------------------------------------------------------
    -- 10. Preserve fiat balances
    ------------------------------------------------------------

    v_customer_wallet :=
        jsonb_set(
            v_customer_wallet,
            '{balances}',
            v_customer_balances,
            true
        );

    ------------------------------------------------------------
    -- 11. Add separate blockchain breakdown
    ------------------------------------------------------------

    v_customer_wallet :=
        jsonb_set(
            v_customer_wallet,
            '{blockchain_balances}',
            v_blockchain_balances,
            true
        );

    ------------------------------------------------------------
    -- 12. Set total USD value
    --
    -- Fiat + GOLD per blockchain
    ------------------------------------------------------------

    v_customer_wallet :=
        jsonb_set(
            v_customer_wallet,
            '{total_usd_value}',
            to_jsonb(
                (
                    v_fiat_total_usd +
                    v_gold_total_usd
                )::text
            ),
            true
        );

    ------------------------------------------------------------
    -- 13. Update only Personal Wallet
    --
    -- Agent and Merchant wallet objects are preserved.
    ------------------------------------------------------------

    v_result :=
        jsonb_set(
            v_result,
            '{customerWallet}',
            v_customer_wallet,
            true
        );

    RETURN v_result;

END;
$function$;