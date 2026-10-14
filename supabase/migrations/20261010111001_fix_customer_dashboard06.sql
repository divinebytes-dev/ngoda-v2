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
    v_result jsonb;

    v_agent_balances jsonb := '{}'::jsonb;
    v_customer_balances jsonb := '{}'::jsonb;
    v_merchant_balances jsonb := '{}'::jsonb;

    v_blockchain_balances jsonb := '[]'::jsonb;

    v_gold_total numeric := 0;
    v_gold_total_usd numeric := 0;
    v_customer_fiat_usd numeric := 0;

    v_item jsonb;
    v_code text;
    v_currency text;
    v_amount numeric;
    v_usd numeric;
BEGIN
    ------------------------------------------------------------
    -- 1. Authentication
    ------------------------------------------------------------

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- 2. Validate user and role
    ------------------------------------------------------------

    SELECT u.id
    INTO v_user_id
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) IN (
          'agent',
          'merchant',
          'vendor'
      )
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- 3. Validate blockchain balances input
    ------------------------------------------------------------

    IF p_blockchain_balances IS NULL
       OR jsonb_typeof(p_blockchain_balances) <> 'array'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_BALANCES';
    END IF;

    ------------------------------------------------------------
    -- 4. Fetch existing wallet balances
    ------------------------------------------------------------

    v_result :=
        public.get_multi_wallet_balances(v_user_id);

    ------------------------------------------------------------
    -- 5. Agent fiat balances
    ------------------------------------------------------------

    SELECT COALESCE(
        jsonb_object_agg(
            lower(btrim(item ->> 'currency_code')),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    INTO v_agent_balances
    FROM jsonb_array_elements(
        COALESCE(
            v_result #> '{agentWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) AS item
    WHERE NULLIF(
        btrim(item ->> 'currency_code'),
        ''
    ) IS NOT NULL
    AND lower(btrim(item ->> 'currency_code')) <> 'gold';

    ------------------------------------------------------------
    -- 6. Customer fiat balances
    ------------------------------------------------------------

    SELECT COALESCE(
        jsonb_object_agg(
            lower(btrim(item ->> 'currency_code')),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    INTO v_customer_balances
    FROM jsonb_array_elements(
        COALESCE(
            v_result #> '{customerWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) AS item
    WHERE NULLIF(
        btrim(item ->> 'currency_code'),
        ''
    ) IS NOT NULL
    AND lower(btrim(item ->> 'currency_code')) <> 'gold';

    ------------------------------------------------------------
    -- 7. Merchant fiat balances
    ------------------------------------------------------------

    SELECT COALESCE(
        jsonb_object_agg(
            lower(btrim(item ->> 'currency_code')),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    INTO v_merchant_balances
    FROM jsonb_array_elements(
        COALESCE(
            v_result #> '{merchantWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) AS item
    WHERE NULLIF(
        btrim(item ->> 'currency_code'),
        ''
    ) IS NOT NULL
    AND lower(btrim(item ->> 'currency_code')) <> 'gold';

    ------------------------------------------------------------
    -- 8. Process blockchain GOLD balances
    ------------------------------------------------------------

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_blockchain_balances)
    LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE';
        END IF;

        v_code := lower(
            btrim(
                COALESCE(
                    v_item ->> 'blockchain_code',
                    ''
                )
            )
        );

        v_currency := lower(
            btrim(
                COALESCE(
                    v_item ->> 'currency_code',
                    'gold'
                )
            )
        );

        IF v_code = '' THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_CODE_REQUIRED';
        END IF;

        IF v_currency <> 'gold' THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_CURRENCY';
        END IF;

        IF v_item ->> 'balance' IS NULL
           OR v_item ->> 'usd_value' IS NULL
        THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_BALANCE_VALUES_REQUIRED';
        END IF;

        v_amount :=
            (v_item ->> 'balance')::numeric;

        v_usd :=
            (v_item ->> 'usd_value')::numeric;

        IF v_amount < 0 OR v_usd < 0 THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE_VALUES';
        END IF;

        --------------------------------------------------------
        -- Prevent duplicate blockchain balances
        --------------------------------------------------------

        IF EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
                v_blockchain_balances
            ) AS b
            WHERE b ->> 'blockchain_code' = v_code
        ) THEN
            RAISE EXCEPTION
                'DUPLICATE_BLOCKCHAIN_BALANCE: %',
                v_code;
        END IF;

        --------------------------------------------------------
        -- Calculate GOLD totals
        --------------------------------------------------------

        v_gold_total :=
            v_gold_total + v_amount;

        v_gold_total_usd :=
            v_gold_total_usd + v_usd;

        --------------------------------------------------------
        -- Store balance by blockchain
        --------------------------------------------------------

        v_blockchain_balances :=
            v_blockchain_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'blockchain_code',
                    v_code,
                    'currency_code',
                    'gold',
                    'balance',
                    v_amount::text,
                    'usd_value',
                    v_usd::text
                )
            );
    END LOOP;

    ------------------------------------------------------------
    -- 9. Calculate customer fiat USD total
    ------------------------------------------------------------

    SELECT COALESCE(
        SUM(
            COALESCE(
                NULLIF(
                    value ->> 'usd_value',
                    ''
                )::numeric,
                0
            )
        ),
        0
    )
    INTO v_customer_fiat_usd
    FROM jsonb_each(v_customer_balances);

    ------------------------------------------------------------
    -- 10. Return wallet summaries
    ------------------------------------------------------------

    RETURN jsonb_build_object(

        'agentWallet',
        jsonb_build_object(
            'balances',
            v_agent_balances,
            'total_usd_value',
            COALESCE(
                v_result #> '{agentWallet,total_usd_value}',
                '0'::jsonb
            )
        ),

        'customerWallet',
        jsonb_build_object(
            'balances',
            v_customer_balances,

            'total_usd_value',
            (
                v_customer_fiat_usd +
                v_gold_total_usd
            )::text,

            'gold_total',
            jsonb_build_object(
                'balance',
                v_gold_total::text,
                'usd_value',
                v_gold_total_usd::text
            ),

            'blockchainBalances',
            v_blockchain_balances,

            'blockchains',
            v_blockchain_balances
        ),

        'merchantWallet',
        jsonb_build_object(
            'balances',
            v_merchant_balances,
            'total_usd_value',
            COALESCE(
                v_result #> '{merchantWallet,total_usd_value}',
                '0'::jsonb
            )
        )
    );
END;
$function$;