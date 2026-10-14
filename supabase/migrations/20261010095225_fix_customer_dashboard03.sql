

DROP FUNCTION IF EXISTS
    public.build_my_vendor_dashboard(text)
RESTRICT;



CREATE OR REPLACE FUNCTION public.build_my_vendor_dashboard(
    p_blockchain_balances jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_currencies jsonb;
    v_wallet jsonb;
    v_daily_summary jsonb;
    v_loan_summary jsonb;

    v_blockchain record;
    v_blockchain_balances jsonb := '[]'::jsonb;
    v_blockchain_codes text[] := ARRAY[]::text[];

    v_blockchain_code text;
    v_chain_balance numeric;
    v_chain_supply numeric;
    v_chain_gas_balance numeric;

    v_total_tokens numeric := 0;
    v_locked_tokens numeric := 0;
    v_available_tokens numeric := 0;

    v_principal numeric := 0;
    v_interest numeric := 0;

    v_gold_price numeric := 0;
    v_collateral_value numeric := 0;
    v_ltv numeric := 0;
    v_health text := 'SAFE';

    v_required_collateral numeric := 0;

    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_min_max_active_loans numeric;
    v_max_max_active_loans numeric;
    v_max_active_loans integer;

    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;

BEGIN
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    /*
     * ==========================================================
     * RESOLVE AND AUTHORIZE ACTIVE VENDOR
     * ==========================================================
     */
    SELECT
        u.*
    INTO
        v_user
    FROM public.users AS u
    JOIN public.user_role AS r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) = 'vendor'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'VENDOR_NOT_AUTHORIZED';
    END IF;

    /*
     * ==========================================================
     * CURRENT GOLD PRICE
     * ==========================================================
     */
    SELECT
        coalesce(r.rate_to_usd, 0)
    INTO
        v_gold_price
    FROM public.current_rates AS r
    WHERE lower(btrim(r.code)) = 'gold'
    LIMIT 1;

    v_gold_price :=
        coalesce(v_gold_price, 0);

    IF v_gold_price <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GOLD_RATE';
    END IF;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN BALANCES
     * ==========================================================
     */
    IF p_blockchain_balances IS NULL
       OR jsonb_typeof(p_blockchain_balances) <> 'array'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_BALANCES';
    END IF;

    /*
     * ==========================================================
     * MULTI-CHAIN GOLD BALANCES
     * ==========================================================
     */
    FOR v_blockchain IN
        SELECT
            value AS data
        FROM jsonb_array_elements(
            p_blockchain_balances
        )
    LOOP
        IF jsonb_typeof(v_blockchain.data) <> 'object' THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE_ENTRY';
        END IF;

        v_blockchain_code :=
            lower(
                btrim(
                    coalesce(
                        v_blockchain.data ->> 'blockchain_code',
                        ''
                    )
                )
            );

        IF v_blockchain_code = '' THEN
            RAISE EXCEPTION
                'MISSING_BLOCKCHAIN_CODE';
        END IF;

        IF v_blockchain_code = ANY(v_blockchain_codes) THEN
            RAISE EXCEPTION
                'DUPLICATE_BLOCKCHAIN_CODE_%',
                upper(v_blockchain_code);
        END IF;

        v_blockchain_codes :=
            array_append(
                v_blockchain_codes,
                v_blockchain_code
            );

        BEGIN
            v_chain_balance :=
                coalesce(
                    nullif(
                        btrim(
                            v_blockchain.data ->> 'balance'
                        ),
                        ''
                    ),
                    '0'
                )::numeric;

            v_chain_supply :=
                coalesce(
                    nullif(
                        btrim(
                            v_blockchain.data ->> 'token_supply'
                        ),
                        ''
                    ),
                    '0'
                )::numeric;

            v_chain_gas_balance :=
                coalesce(
                    nullif(
                        btrim(
                            v_blockchain.data ->> 'gas_balance'
                        ),
                        ''
                    ),
                    '0'
                )::numeric;

        EXCEPTION
            WHEN invalid_text_representation
              OR numeric_value_out_of_range
            THEN
                RAISE EXCEPTION
                    'INVALID_BLOCKCHAIN_NUMERIC_BALANCE_%',
                    upper(v_blockchain_code);
        END;

        IF v_chain_balance < 0
           OR v_chain_supply < 0
           OR v_chain_gas_balance < 0
           OR v_chain_balance = 'NaN'::numeric
           OR v_chain_supply = 'NaN'::numeric
           OR v_chain_gas_balance = 'NaN'::numeric
           OR v_chain_balance = 'Infinity'::numeric
           OR v_chain_supply = 'Infinity'::numeric
           OR v_chain_gas_balance = 'Infinity'::numeric
        THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_BALANCE_%',
                upper(v_blockchain_code);
        END IF;

        /*
         * Combined GOLD balance across every chain.
         */
        v_total_tokens :=
            v_total_tokens + v_chain_balance;

        /*
         * Build entries compatible with
         * BlockchainWalletBalance.fromJson().
         */
        v_blockchain_balances :=
            v_blockchain_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'blockchain_code',
                    v_blockchain_code,

                    'currency_code',
                    'gold',

                    'balance',
                    trim_scale(v_chain_balance)::text,

                    'usd_value',
                    to_char(
                        round(
                            v_chain_balance * v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    ),

                    'chain_id',
                    v_blockchain.data ->> 'chain_id',

                    'gas_balance',
                    trim_scale(v_chain_gas_balance)::text,

                    'token_supply',
                    trim_scale(v_chain_supply)::text,

                    'native_currency_code',
                    v_blockchain.data ->> 'native_currency_code'
                )
            );
    END LOOP;

    /*
     * ==========================================================
     * SUPPORTED CURRENCIES
     * ==========================================================
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * ==========================================================
     * WALLET CONTAINERS
     * ==========================================================
     *
     * Preserve agent, merchant and customer wallets.
     * Fiat balances remain unchanged.
     */
    v_wallet :=
        jsonb_build_object(
            'agent',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),

            'merchant',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),

            'customer',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            )
        )
        ||
        public.build_user_wallet_balance(
            v_user.id
        );

    /*
     * ==========================================================
     * DAILY SUMMARY
     * ==========================================================
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     */
    SELECT
        a.available_points,
        a.tier_points,
        a.lifetime_earned_points,
        a.level_code,
        a.is_active
    INTO
        v_available_points,
        v_tier_points,
        v_lifetime_earned_points,
        v_loyalty_level,
        v_loyalty_account_active
    FROM public.loyalty_account AS a
    WHERE a.user_id = v_user.id
    LIMIT 1;

    v_available_points :=
        greatest(
            coalesce(v_available_points, 0),
            0
        );

    v_tier_points :=
        greatest(
            coalesce(v_tier_points, 0),
            0
        );

    v_lifetime_earned_points :=
        greatest(
            coalesce(v_lifetime_earned_points, 0),
            0
        );

    v_loyalty_level :=
        coalesce(
            nullif(
                btrim(v_loyalty_level),
                ''
            ),
            'bronze'
        );

    v_loyalty_account_active :=
        coalesce(
            v_loyalty_account_active,
            false
        );

    /*
     * ==========================================================
     * CURRENT POOLED COLLATERAL
     * ==========================================================
     */
    SELECT
        coalesce(c.locked_tokens, 0)
    INTO
        v_locked_tokens
    FROM public.collateral AS c
    WHERE c.user_id = v_user.id
    LIMIT 1;

    v_locked_tokens :=
        greatest(
            coalesce(v_locked_tokens, 0),
            0
        );

    v_available_tokens :=
        greatest(
            v_total_tokens - v_locked_tokens,
            0
        );

    /*
     * ==========================================================
     * REQUIRED COLLATERAL
     * ==========================================================
     */
    v_required_collateral :=
        public.calculate_required_collateral(
            v_user.id
        );

    /*
     * ==========================================================
     * MAXIMUM ACTIVE LOANS CONFIGURATION
     * ==========================================================
     */
    SELECT
        count(*),
        min(c.rate),
        max(c.rate)
    INTO
        v_active_loan_config_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    FROM public.loan_config AS c
    WHERE c.country_code = v_user.country_code
      AND lower(
          btrim(c.config_type::text)
      ) = 'max_active_loans'
      AND c.is_active = true;

    IF v_active_loan_config_rows = 0
       OR v_min_max_active_loans IS NULL
    THEN
        RAISE EXCEPTION
            'MAX_ACTIVE_LOANS_NOT_CONFIGURED';
    END IF;

    IF v_min_max_active_loans IS DISTINCT FROM
       v_max_max_active_loans
    THEN
        RAISE EXCEPTION
            'MAX_ACTIVE_LOANS_CONFIGURATION_AMBIGUOUS';
    END IF;

    IF v_min_max_active_loans <= 0
       OR trunc(v_min_max_active_loans) <>
          v_min_max_active_loans
    THEN
        RAISE EXCEPTION
            'INVALID_MAX_ACTIVE_LOANS';
    END IF;

    v_max_active_loans :=
        v_min_max_active_loans::integer;

    /*
     * ==========================================================
     * ACTIVE LOAN BALANCES
     * ==========================================================
     */
    SELECT
        count(DISTINCT l.id)::bigint,

        coalesce(
            sum(e.debit_principal),
            0
        ) -
        coalesce(
            sum(e.credit_principal),
            0
        ),

        coalesce(
            sum(e.debit_interest),
            0
        ) -
        coalesce(
            sum(e.credit_interest),
            0
        )
    INTO
        v_active_loans,
        v_principal,
        v_interest
    FROM public.loan AS l
    LEFT JOIN public.loan_entry AS e
        ON e.loan_id = l.id
    WHERE l.user_id = v_user.id
      AND l.status = 'active'::public."LoanStatus";

    v_active_loans :=
        greatest(
            coalesce(v_active_loans, 0),
            0
        );

    v_principal :=
        greatest(
            coalesce(v_principal, 0),
            0
        );

    v_interest :=
        greatest(
            coalesce(v_interest, 0),
            0
        );

    /*
     * ==========================================================
     * SVA ACCESS
     * ==========================================================
     */
    v_sva_access_utilisation :=
        round(
            (
                v_active_loans::numeric /
                v_max_active_loans::numeric
            ) * 100,
            2
        );

    v_can_access_sva :=
        v_sva_access_utilisation < 100;

    /*
     * ==========================================================
     * COLLATERAL VALUE AND LTV
     * ==========================================================
     */
    v_collateral_value :=
        v_locked_tokens * v_gold_price;

    IF v_collateral_value > 0 THEN
        v_ltv :=
            (
                v_principal +
                v_interest
            ) /
            v_collateral_value * 100;
    ELSE
        v_ltv := 0;
    END IF;

    IF v_ltv >= 85 THEN
        v_health := 'LIQUIDATION_RISK';

    ELSIF v_ltv >= 70 THEN
        v_health := 'WARNING';

    ELSE
        v_health := 'SAFE';
    END IF;

    /*
     * ==========================================================
     * LOAN SUMMARY
     * ==========================================================
     */
    v_loan_summary :=
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(v_principal)::text,

            'interest_outstanding',
            trim_scale(v_interest)::text,

            'collateral_locked',
            trim_scale(v_locked_tokens)::text,

            'required_collateral',
            to_char(
                v_required_collateral,
                'FM999999999999999999999999990.000000'
            ),

            'ltv_percent',
            to_char(
                round(v_ltv, 2),
                'FM999999999999999999999999990.00'
            ),

            'health',
            v_health,

            'sva_access',
            jsonb_build_object(
                'active_loans',
                v_active_loans,

                'max_active_loans',
                v_max_active_loans,

                'utilisation_percent',
                to_char(
                    v_sva_access_utilisation,
                    'FM999999999999999999999999990.00'
                ),

                'can_access',
                v_can_access_sva
            ),

            'gold',
            jsonb_build_object(
                'total',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_total_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_total_tokens * v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'locked',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_locked_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_locked_tokens * v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'available',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_available_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_available_tokens * v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                )
            )
        );

    /*
     * ==========================================================
     * RETURN VENDOR DASHBOARD
     * ==========================================================
     */
    RETURN jsonb_build_object(
        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

        'blockchainBalances',
        v_blockchain_balances,

        'dailySummary',
        v_daily_summary,

        'loyalty',
        jsonb_build_object(
            'available_points',
            v_available_points,

            'tier_points',
            v_tier_points,

            'lifetime_earned_points',
            v_lifetime_earned_points,

            'level_code',
            v_loyalty_level,

            'is_active',
            v_loyalty_account_active
        ),

        'loanSummary',
        v_loan_summary
    );
END;
$function$;