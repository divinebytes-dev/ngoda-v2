CREATE OR REPLACE FUNCTION public.build_my_agent_dashboard(
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
    v_blockchain_balances jsonb := '[]'::jsonb;

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

    v_item jsonb;
    v_blockchain_code text;
    v_balance numeric;
    v_seen_blockchains text[] := ARRAY[]::text[];

BEGIN
    ------------------------------------------------------------
    -- AUTHENTICATION
    ------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- RESOLVE AND AUTHORIZE ACTIVE AGENT
    ------------------------------------------------------------
    SELECT
        u.*
    INTO
        v_user
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) = 'agent'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'AGENT_NOT_AUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- CURRENT GOLD PRICE
    ------------------------------------------------------------
    SELECT
        r.rate_to_usd
    INTO
        v_gold_price
    FROM public.current_rates r
    WHERE lower(btrim(r.code)) = 'gold'
    LIMIT 1;

    v_gold_price :=
        coalesce(v_gold_price, 0);

    IF v_gold_price <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GOLD_RATE';
    END IF;

    ------------------------------------------------------------
    -- VALIDATE BLOCKCHAIN BALANCES
    ------------------------------------------------------------
    IF p_blockchain_balances IS NULL
       OR jsonb_typeof(p_blockchain_balances) <> 'array'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_BALANCES';
    END IF;

    ------------------------------------------------------------
    -- BUILD MULTI-CHAIN GOLD BALANCES
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
            nullif(
                lower(
                    btrim(
                        v_item ->> 'blockchain_code'
                    )
                ),
                ''
            );

        IF v_blockchain_code IS NULL THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_CODE_REQUIRED';
        END IF;

        IF v_blockchain_code = ANY(v_seen_blockchains) THEN
            RAISE EXCEPTION
                'DUPLICATE_BLOCKCHAIN_BALANCE_%',
                upper(v_blockchain_code);
        END IF;

        v_seen_blockchains :=
            array_append(
                v_seen_blockchains,
                v_blockchain_code
            );

        IF v_item ->> 'balance' IS NULL THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_BALANCE_REQUIRED';
        END IF;

        BEGIN
            v_balance :=
                (v_item ->> 'balance')::numeric;

        EXCEPTION
            WHEN invalid_text_representation
              OR numeric_value_out_of_range
            THEN
                RAISE EXCEPTION
                    'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
        END;

        IF v_balance < 0
           OR v_balance::text IN (
               'NaN',
               'Infinity',
               '-Infinity'
           )
        THEN
            RAISE EXCEPTION
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
        END IF;

        v_total_tokens :=
            v_total_tokens + v_balance;

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
                    (
                        v_balance *
                        v_gold_price
                    )::text
                )
            );
    END LOOP;

    ------------------------------------------------------------
    -- SUPPORTED CURRENCIES
    ------------------------------------------------------------
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    ------------------------------------------------------------
    -- WALLET BALANCES
    ------------------------------------------------------------
    v_wallet :=
        jsonb_build_object(
            'agent',
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

    ------------------------------------------------------------
    -- DAILY SUMMARY
    ------------------------------------------------------------
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    ------------------------------------------------------------
    -- LOYALTY
    ------------------------------------------------------------
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
    FROM public.loyalty_account a
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

    ------------------------------------------------------------
    -- CURRENT POOLED COLLATERAL
    ------------------------------------------------------------
    SELECT
        coalesce(
            c.locked_tokens,
            0
        )
    INTO
        v_locked_tokens
    FROM public.collateral c
    WHERE c.user_id = v_user.id
    LIMIT 1;

    v_locked_tokens :=
        greatest(
            coalesce(v_locked_tokens, 0),
            0
        );

    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_locked_tokens,
            0
        );

    ------------------------------------------------------------
    -- REQUIRED COLLATERAL
    ------------------------------------------------------------
    v_required_collateral :=
        public.calculate_required_collateral(
            v_user.id
        );

    ------------------------------------------------------------
    -- MAXIMUM ACTIVE LOANS CONFIGURATION
    ------------------------------------------------------------
    SELECT
        count(*),
        min(c.rate),
        max(c.rate)
    INTO
        v_active_loan_config_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    FROM public.loan_config c
    WHERE c.country_code =
          v_user.country_code
      AND lower(
          btrim(
              c.config_type::text
          )
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

    ------------------------------------------------------------
    -- ACTIVE LOAN BALANCES
    ------------------------------------------------------------
    SELECT
        count(
            distinct l.id
        )::bigint,

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

    FROM public.loan l
    LEFT JOIN public.loan_entry e
        ON e.loan_id = l.id
    WHERE l.user_id = v_user.id
      AND l.status =
          'active'::public."LoanStatus";

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

    ------------------------------------------------------------
    -- SVA ACCESS
    ------------------------------------------------------------
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

    ------------------------------------------------------------
    -- CURRENT COLLATERAL VALUE AND LTV
    ------------------------------------------------------------
    v_collateral_value :=
        v_locked_tokens *
        v_gold_price;

    IF v_collateral_value > 0 THEN
        v_ltv :=
            (
                v_principal +
                v_interest
            ) /
            v_collateral_value *
            100;
    ELSE
        v_ltv := 0;
    END IF;

    IF v_ltv >= 85 THEN
        v_health :=
            'LIQUIDATION_RISK';

    ELSIF v_ltv >= 70 THEN
        v_health :=
            'WARNING';

    ELSE
        v_health :=
            'SAFE';
    END IF;

    ------------------------------------------------------------
    -- LOAN SUMMARY
    ------------------------------------------------------------
    v_loan_summary :=
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(
                v_principal
            )::text,

            'interest_outstanding',
            trim_scale(
                v_interest
            )::text,

            'collateral_locked',
            trim_scale(
                v_locked_tokens
            )::text,

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
                        round(
                            v_total_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_total_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'locked',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(
                            v_locked_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_locked_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'available',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(
                            v_available_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_available_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                )
            )
        );

    ------------------------------------------------------------
    -- RETURN DASHBOARD
    ------------------------------------------------------------
    RETURN jsonb_build_object(
        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

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
        v_loan_summary,

        'blockchainBalances',
        v_blockchain_balances
    );
END;
$function$;

DROP FUNCTION IF EXISTS
    public.build_my_agent_dashboard(text);