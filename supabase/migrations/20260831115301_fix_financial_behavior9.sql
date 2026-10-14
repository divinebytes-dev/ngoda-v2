CREATE OR REPLACE FUNCTION public.get_my_financial_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_country_code text;

    v_fiscal_year integer;
    v_period integer;

    v_currencies jsonb;
    v_money_by_currency jsonb;
    v_money_in jsonb;
    v_distribution jsonb;
    v_gold jsonb;

    -- ==========================================================
    -- GOLD
    -- ==========================================================

    v_gold_opening numeric(20, 6) := 0;
    v_gold_purchased numeric(20, 6) := 0;
    v_gold_sold numeric(20, 6) := 0;
    v_gold_transferred_in numeric(20, 6) := 0;
    v_gold_transferred_out numeric(20, 6) := 0;
    v_gold_closing numeric(20, 6) := 0;

    -- ==========================================================
    -- FISCAL YEAR BEHAVIOR
    -- ==========================================================

    v_behavior public.financial_behavior_type :=
        'neutral'::public.financial_behavior_type;

    v_shopper_score_percentage numeric := 0;
    v_saver_score_percentage numeric := 0;
    v_investor_score_percentage numeric := 0;
    v_borrower_score_percentage numeric := 0;

    -- ==========================================================
    -- CURRENT PERIOD BEHAVIOR
    --
    -- Retained for response compatibility.
    -- The first/summary screen should use fiscal-year behavior.
    -- ==========================================================

    v_current_period_behavior public.financial_behavior_type :=
        'neutral'::public.financial_behavior_type;

    v_current_period_shopper_score_percentage numeric := 0;
    v_current_period_saver_score_percentage numeric := 0;
    v_current_period_investor_score_percentage numeric := 0;
    v_current_period_borrower_score_percentage numeric := 0;

BEGIN

    -- ==========================================================
    -- AUTHENTICATION
    -- ==========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    -- ==========================================================
    -- AUTHORIZED USER + COUNTRY
    -- ==========================================================

    SELECT
        u.id,
        lower(u.country_code)
    INTO
        v_user_id,
        v_country_code
    FROM public.users AS u

    JOIN public.user_role AS r
        ON r.id = u.role_id

    WHERE u.id = auth.uid()::text

      AND u.status =
          'active'::public."UserStatus"

      AND lower(r.name::text) IN (
          'customer',
          'vendor',
          'agent'
      )

    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE =
                'FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED';
    END IF;


    IF v_country_code IS NULL
       OR trim(v_country_code) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE =
                'USER_COUNTRY_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- CURRENT FISCAL PERIOD
    -- ==========================================================

    SELECT
        fiscal_period.fiscal_year,
        fiscal_period.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fiscal_period;


    IF NOT FOUND
       OR v_fiscal_year IS NULL
       OR v_period IS NULL
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE =
                'FISCAL_PERIOD_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- FISCAL YEAR CONSOLIDATED BEHAVIOR
    --
    -- This is the behavior used by the first / summary report.
    -- ==========================================================

    SELECT
        fb.behavior,

        COALESCE(
            fb.shopper_score_percentage,
            0
        ),

        COALESCE(
            fb.saver_score_percentage,
            0
        ),

        COALESCE(
            fb.investor_score_percentage,
            0
        ),

        COALESCE(
            fb.borrower_score_percentage,
            0
        )

    INTO
        v_behavior,
        v_shopper_score_percentage,
        v_saver_score_percentage,
        v_investor_score_percentage,
        v_borrower_score_percentage

    FROM public.financial_behavior AS fb

    WHERE fb.user_id =
          v_user_id

      AND fb.country_code =
          v_country_code

      AND fb.fiscal_year =
          v_fiscal_year

      AND fb.scope =
          'fiscal_year'::public.financial_behavior_scope

      AND fb.period IS NULL

      AND fb.currency_code IS NULL

    LIMIT 1;


    IF NOT FOUND THEN

        v_behavior :=
            'neutral'::public.financial_behavior_type;

        v_shopper_score_percentage := 0;
        v_saver_score_percentage := 0;
        v_investor_score_percentage := 0;
        v_borrower_score_percentage := 0;

    END IF;


    -- ==========================================================
    -- CURRENT PERIOD CONSOLIDATED BEHAVIOR
    --
    -- Retained for compatibility and possible drill-down use.
    -- ==========================================================

    SELECT
        fb.behavior,

        COALESCE(
            fb.shopper_score_percentage,
            0
        ),

        COALESCE(
            fb.saver_score_percentage,
            0
        ),

        COALESCE(
            fb.investor_score_percentage,
            0
        ),

        COALESCE(
            fb.borrower_score_percentage,
            0
        )

    INTO
        v_current_period_behavior,
        v_current_period_shopper_score_percentage,
        v_current_period_saver_score_percentage,
        v_current_period_investor_score_percentage,
        v_current_period_borrower_score_percentage

    FROM public.financial_behavior AS fb

    WHERE fb.user_id =
          v_user_id

      AND fb.country_code =
          v_country_code

      AND fb.fiscal_year =
          v_fiscal_year

      AND fb.period =
          v_period

      AND fb.scope =
          'period'::public.financial_behavior_scope

      AND fb.currency_code IS NULL

    LIMIT 1;


    IF NOT FOUND THEN

        v_current_period_behavior :=
            'neutral'::public.financial_behavior_type;

        v_current_period_shopper_score_percentage := 0;
        v_current_period_saver_score_percentage := 0;
        v_current_period_investor_score_percentage := 0;
        v_current_period_borrower_score_percentage := 0;

    END IF;


    -- ==========================================================
    -- FY-TO-DATE MONEY BY CURRENCY
    --
    -- The first report is now a fiscal-year-to-date summary.
    --
    -- FLOW VALUES:
    --
    --     Cash In
    --     Transfer In
    --     Loan Disbursement
    --     Investment Proceeds
    --     Withdrawal
    --     Spending
    --     Investment
    --     Repayment
    --
    -- are accumulated from period 1 through v_period.
    --
    -- STATE VALUES:
    --
    --     Savings B/F
    --
    -- comes from the first FY-to-date position.
    --
    --     Savings
    --
    -- comes from the latest FY-to-date closing position.
    --
    -- Both native and USD-equivalent values are returned.
    -- ==========================================================

    WITH
    pot_ranked AS (

        SELECT
            fp.*,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period ASC
            ) AS first_period_row,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period DESC
            ) AS last_period_row

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.country_code =
              v_country_code

          AND fp.fiscal_year =
              v_fiscal_year

          AND fp.period <=
              v_period
    ),

    pot_positions AS (

        SELECT
            pr.currency_code,

            -- ==================================================
            -- BEGINNING OF FY-TO-DATE POSITION
            -- ==================================================

            COALESCE(
                MAX(pr.opening_savings)
                FILTER (
                    WHERE pr.first_period_row = 1
                ),
                0
            ) AS opening_savings,

            COALESCE(
                MAX(pr.opening_savings_usd)
                FILTER (
                    WHERE pr.first_period_row = 1
                ),
                0
            ) AS opening_savings_usd,

            -- ==================================================
            -- LATEST FY-TO-DATE POSITION
            -- ==================================================

            COALESCE(
                MAX(pr.closing_savings)
                FILTER (
                    WHERE pr.last_period_row = 1
                ),
                0
            ) AS closing_savings,

            COALESCE(
                MAX(pr.closing_savings_usd)
                FILTER (
                    WHERE pr.last_period_row = 1
                ),
                0
            ) AS closing_savings_usd

        FROM pot_ranked AS pr

        GROUP BY
            pr.currency_code
    ),

    -- ==========================================================
    -- HISTORICAL SAVINGS SEED
    --
    -- A savings seed establishes state.
    -- It is not Cash In for the current fiscal year.
    --
    -- We deliberately use amount / amount_usd here instead of
    -- cash_amount fallback logic because a seed can correctly
    -- have zero cash movement.
    -- ==========================================================

    seed_savings AS (

        SELECT
            e.currency_code,

            COALESCE(
                SUM(
                    COALESCE(
                        e.amount,
                        0
                    )
                ),
                0
            ) AS amount,

            COALESCE(
                SUM(
                    COALESCE(
                        e.amount_usd,
                        0
                    )
                ),
                0
            ) AS amount_usd

        FROM public.financial_pot_event AS e

        WHERE e.user_id =
              v_user_id

          AND e.country_code =
              v_country_code

          AND e.fiscal_year =
              v_fiscal_year

          AND e.period <=
              v_period

          AND lower(e.transaction_type) =
              'initial_savings_seed'

        GROUP BY
            e.currency_code
    ),

    -- ==========================================================
    -- FY-TO-DATE CASH FLOW ACTIVITY
    -- ==========================================================

    event_activity AS (

        SELECT
            e.currency_code,

            -- ==================================================
            -- CASH IN
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'deposit'::public.financial_activity_type

                         AND lower(e.transaction_type) <>
                             'cash_transfer'

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS cash_in,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'deposit'::public.financial_activity_type

                         AND lower(e.transaction_type) <>
                             'cash_transfer'

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS cash_in_usd,


            -- ==================================================
            -- TRANSFER IN
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'deposit'::public.financial_activity_type

                         AND lower(e.transaction_type) =
                             'cash_transfer'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS transfer_in,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'deposit'::public.financial_activity_type

                         AND lower(e.transaction_type) =
                             'cash_transfer'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS transfer_in_usd,


            -- ==================================================
            -- LOAN DISBURSEMENT
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'loan_disbursement'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS loan_disbursement,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'loan_disbursement'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS loan_disbursement_usd,


            -- ==================================================
            -- INVESTMENT PROCEEDS
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'investment_sell'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS investment_proceeds,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'investment_sell'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS investment_proceeds_usd,


            -- ==================================================
            -- WITHDRAWAL
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'withdrawal'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS withdrawal,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'withdrawal'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS withdrawal_usd,


            -- ==================================================
            -- SPENDING
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'spending'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS spending,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'spending'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS spending_usd,


            -- ==================================================
            -- INVESTMENT PURCHASE
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'investment_buy'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS investment,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'investment_buy'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                NULLIF(
                                    e.investment_cost_usd,
                                    0
                                ),
                                e.amount_usd,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS investment_usd,


            -- ==================================================
            -- REPAYMENT
            -- ==================================================

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'loan_repayment'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount,
                                    0
                                ),
                                e.amount,
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS repayment,

            COALESCE(
                SUM(
                    CASE

                        WHEN e.activity_type =
                            'loan_repayment'::public.financial_activity_type

                         AND lower(e.transaction_type)
                             NOT LIKE 'initial\_%' ESCAPE '\'

                        THEN
                            COALESCE(
                                NULLIF(
                                    e.cash_amount_usd,
                                    0
                                ),
                                NULLIF(
                                    e.amount_usd,
                                    0
                                ),
                                COALESCE(
                                    e.principal_amount_usd,
                                    0
                                )
                                +
                                COALESCE(
                                    e.interest_amount_usd,
                                    0
                                ),
                                0
                            )

                        ELSE 0

                    END
                ),
                0
            ) AS repayment_usd

        FROM public.financial_pot_event AS e

        WHERE e.user_id =
              v_user_id

          AND e.country_code =
              v_country_code

          AND e.fiscal_year =
              v_fiscal_year

          AND e.period <=
              v_period

        GROUP BY
            e.currency_code
    ),

    -- ==========================================================
    -- COMPLETE CURRENCY SET
    -- ==========================================================

    currency_keys AS (

        SELECT
            pp.currency_code
        FROM pot_positions AS pp

        UNION

        SELECT
            ss.currency_code
        FROM seed_savings AS ss

        UNION

        SELECT
            ea.currency_code
        FROM event_activity AS ea
    ),

    -- ==========================================================
    -- FY-TO-DATE MONEY BY CURRENCY
    -- ==========================================================

    currency_money AS (

        SELECT
            ck.currency_code,


            -- ==================================================
            -- SAVINGS BROUGHT FORWARD
            --
            -- Normal:
            --     first FY-to-date pot opening balance.
            --
            -- Historical fallback:
            --     initial_savings_seed.
            -- ==================================================

            CASE

                WHEN COALESCE(
                    pp.opening_savings,
                    0
                ) > 0

                THEN
                    pp.opening_savings

                ELSE
                    COALESCE(
                        ss.amount,
                        0
                    )

            END AS savings_brought_forward,

            CASE

                WHEN COALESCE(
                    pp.opening_savings_usd,
                    0
                ) > 0

                THEN
                    pp.opening_savings_usd

                ELSE
                    COALESCE(
                        ss.amount_usd,
                        0
                    )

            END AS savings_brought_forward_usd,


            -- ==================================================
            -- FY-TO-DATE SOURCE FLOWS
            -- ==================================================

            COALESCE(
                ea.cash_in,
                0
            ) AS cash_in,

            COALESCE(
                ea.cash_in_usd,
                0
            ) AS cash_in_usd,

            COALESCE(
                ea.transfer_in,
                0
            ) AS transfer_in,

            COALESCE(
                ea.transfer_in_usd,
                0
            ) AS transfer_in_usd,

            COALESCE(
                ea.loan_disbursement,
                0
            ) AS loan_disbursement,

            COALESCE(
                ea.loan_disbursement_usd,
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                ea.investment_proceeds,
                0
            ) AS investment_proceeds,

            COALESCE(
                ea.investment_proceeds_usd,
                0
            ) AS investment_proceeds_usd,


            -- ==================================================
            -- FY-TO-DATE DISTRIBUTION FLOWS
            -- ==================================================

            COALESCE(
                ea.withdrawal,
                0
            ) AS withdrawal,

            COALESCE(
                ea.withdrawal_usd,
                0
            ) AS withdrawal_usd,

            COALESCE(
                ea.spending,
                0
            ) AS spending,

            COALESCE(
                ea.spending_usd,
                0
            ) AS spending_usd,

            COALESCE(
                ea.investment,
                0
            ) AS investment,

            COALESCE(
                ea.investment_usd,
                0
            ) AS investment_usd,

            COALESCE(
                ea.repayment,
                0
            ) AS repayment,

            COALESCE(
                ea.repayment_usd,
                0
            ) AS repayment_usd,


            -- ==================================================
            -- CURRENT / LATEST CLOSING SAVINGS
            --
            -- This is a state and is therefore NOT summed.
            -- ==================================================

            COALESCE(
                pp.closing_savings,
                0
            ) AS savings,

            COALESCE(
                pp.closing_savings_usd,
                0
            ) AS savings_usd

        FROM currency_keys AS ck

        LEFT JOIN pot_positions AS pp
            ON pp.currency_code =
               ck.currency_code

        LEFT JOIN seed_savings AS ss
            ON ss.currency_code =
               ck.currency_code

        LEFT JOIN event_activity AS ea
            ON ea.currency_code =
               ck.currency_code
    ),

    currency_totals AS (

        SELECT
            cm.*,

            (
                  cm.savings_brought_forward
                + cm.cash_in
                + cm.transfer_in
                + cm.loan_disbursement
                + cm.investment_proceeds
            ) AS available_money,

            (
                  cm.savings_brought_forward_usd
                + cm.cash_in_usd
                + cm.transfer_in_usd
                + cm.loan_disbursement_usd
                + cm.investment_proceeds_usd
            ) AS available_money_usd,

            (
                  cm.withdrawal
                + cm.spending
                + cm.investment
                + cm.repayment
                + cm.savings
            ) AS distribution_total,

            (
                  cm.withdrawal_usd
                + cm.spending_usd
                + cm.investment_usd
                + cm.repayment_usd
                + cm.savings_usd
            ) AS distribution_total_usd

        FROM currency_money AS cm
    )

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        ct.currency_code,

                    'money_in',
                        jsonb_build_object(

                            'savings_brought_forward',
                                ct.savings_brought_forward,

                            'savings_brought_forward_usd',
                                ct.savings_brought_forward_usd,

                            'cash_in',
                                ct.cash_in,

                            'cash_in_usd',
                                ct.cash_in_usd,

                            'transfer_in',
                                ct.transfer_in,

                            'transfer_in_usd',
                                ct.transfer_in_usd,

                            'loan_disbursement',
                                ct.loan_disbursement,

                            'loan_disbursement_usd',
                                ct.loan_disbursement_usd,

                            'investment_proceeds',
                                ct.investment_proceeds,

                            'investment_proceeds_usd',
                                ct.investment_proceeds_usd,

                            'total',
                                ct.available_money,

                            'total_usd',
                                ct.available_money_usd
                        ),

                    'distribution',
                        jsonb_build_object(

                            'withdrawal',
                                ct.withdrawal,

                            'withdrawal_usd',
                                ct.withdrawal_usd,

                            'spending',
                                ct.spending,

                            'spending_usd',
                                ct.spending_usd,

                            'investment',
                                ct.investment,

                            'investment_usd',
                                ct.investment_usd,

                            'repayment',
                                ct.repayment,

                            'repayment_usd',
                                ct.repayment_usd,

                            'savings',
                                ct.savings,

                            'savings_usd',
                                ct.savings_usd,

                            'total',
                                ct.distribution_total,

                            'total_usd',
                                ct.distribution_total_usd
                        )
                )
                ORDER BY
                    ct.currency_code
            ),
            '[]'::jsonb
        )

    INTO
        v_money_by_currency

    FROM currency_totals AS ct;


    -- ==========================================================
    -- CONSOLIDATED FY-TO-DATE MONEY IN
    --
    -- ALL selector.
    --
    -- Never sum native currencies together.
    -- Only USD equivalents are consolidated.
    -- ==========================================================

    WITH source AS (

        SELECT
            item

        FROM jsonb_array_elements(
            v_money_by_currency
        ) AS item
    ),

    totals AS (

        SELECT
            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'savings_brought_forward_usd'
                    )::numeric
                ),
                0
            ) AS savings_brought_forward_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'cash_in_usd'
                    )::numeric
                ),
                0
            ) AS cash_in_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'transfer_in_usd'
                    )::numeric
                ),
                0
            ) AS transfer_in_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'loan_disbursement_usd'
                    )::numeric
                ),
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'investment_proceeds_usd'
                    )::numeric
                ),
                0
            ) AS investment_proceeds_usd

        FROM source
    )

    SELECT
        jsonb_build_object(

            'savings_brought_forward_usd',
                t.savings_brought_forward_usd,

            'cash_in_usd',
                t.cash_in_usd,

            'transfer_in_usd',
                t.transfer_in_usd,

            'loan_disbursement_usd',
                t.loan_disbursement_usd,

            'investment_proceeds_usd',
                t.investment_proceeds_usd,

            'total_usd',
                  t.savings_brought_forward_usd
                + t.cash_in_usd
                + t.transfer_in_usd
                + t.loan_disbursement_usd
                + t.investment_proceeds_usd
        )

    INTO
        v_money_in

    FROM totals AS t;


    -- ==========================================================
    -- CONSOLIDATED FY-TO-DATE DISTRIBUTION
    --
    -- ALL selector.
    --
    -- Flow values have already been aggregated through the
    -- current period.
    --
    -- Savings is the latest closing position for each currency.
    -- ==========================================================

    WITH source AS (

        SELECT
            item

        FROM jsonb_array_elements(
            v_money_by_currency
        ) AS item
    ),

    totals AS (

        SELECT
            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'withdrawal_usd'
                    )::numeric
                ),
                0
            ) AS withdrawal_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'spending_usd'
                    )::numeric
                ),
                0
            ) AS spending_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'investment_usd'
                    )::numeric
                ),
                0
            ) AS investment_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'repayment_usd'
                    )::numeric
                ),
                0
            ) AS repayment_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'savings_usd'
                    )::numeric
                ),
                0
            ) AS savings_usd

        FROM source
    )

    SELECT
        jsonb_build_object(

            'withdrawal_usd',
                t.withdrawal_usd,

            'spending_usd',
                t.spending_usd,

            'investment_usd',
                t.investment_usd,

            'repayment_usd',
                t.repayment_usd,

            'savings_usd',
                t.savings_usd,

            'total_usd',
                  t.withdrawal_usd
                + t.spending_usd
                + t.investment_usd
                + t.repayment_usd
                + t.savings_usd
        )

    INTO
        v_distribution

    FROM totals AS t;


    -- ==========================================================
    -- EXISTING FY-TO-DATE CURRENCY SUMMARY
    --
    -- Flow fields are accumulated.
    -- Opening position = first completed period.
    -- Closing position = latest completed period.
    -- ==========================================================

    WITH currency_periods AS (

        SELECT
            fp.*,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period ASC
            ) AS first_period_row,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period DESC
            ) AS last_period_row

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.country_code =
              v_country_code

          AND fp.fiscal_year =
              v_fiscal_year

          AND fp.period <=
              v_period
    ),

    currency_summary AS (

        SELECT
            cp.currency_code,

            SUM(
                cp.deposit_amount
            ) AS deposit_amount,

            SUM(
                cp.deposit_amount_usd
            ) AS deposit_amount_usd,

            SUM(
                cp.withdrawal_amount
            ) AS withdrawal_amount,

            SUM(
                cp.withdrawal_amount_usd
            ) AS withdrawal_amount_usd,

            SUM(
                cp.spending_amount
            ) AS spending_amount,

            SUM(
                cp.spending_amount_usd
            ) AS spending_amount_usd,

            SUM(
                cp.savings_inflow
            ) AS savings_inflow,

            SUM(
                cp.savings_inflow_usd
            ) AS savings_inflow_usd,

            SUM(
                cp.savings_outflow
            ) AS savings_outflow,

            SUM(
                cp.savings_outflow_usd
            ) AS savings_outflow_usd,

            /*
             * Retained as the existing accumulated savings activity
             * field for compatibility.
             *
             * Closing savings below remains the actual latest state.
             */
            SUM(
                cp.saving_amount
            ) AS saving_amount,

            SUM(
                cp.saving_amount_usd
            ) AS saving_amount_usd,

            MAX(
                cp.opening_savings
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_savings,

            MAX(
                cp.opening_savings_usd
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_savings_usd,

            MAX(
                cp.closing_savings
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_savings,

            MAX(
                cp.closing_savings_usd
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_savings_usd,

            SUM(
                cp.investment_purchase_amount
            ) AS investment_purchase_amount,

            SUM(
                cp.investment_purchase_amount_usd
            ) AS investment_purchase_amount_usd,

            SUM(
                cp.investment_sale_amount
            ) AS investment_sale_amount,

            SUM(
                cp.investment_sale_amount_usd
            ) AS investment_sale_amount_usd,

            SUM(
                cp.loan_disbursed_amount
            ) AS loan_disbursed_amount,

            SUM(
                cp.loan_disbursed_amount_usd
            ) AS loan_disbursed_amount_usd,

            SUM(
                cp.loan_repayment_amount
            ) AS loan_repayment_amount,

            SUM(
                cp.loan_repayment_amount_usd
            ) AS loan_repayment_amount_usd,

            SUM(
                cp.loan_principal_repaid
            ) AS loan_principal_repaid,

            SUM(
                cp.loan_principal_repaid_usd
            ) AS loan_principal_repaid_usd,

            SUM(
                cp.loan_interest_repaid
            ) AS loan_interest_repaid,

            SUM(
                cp.loan_interest_repaid_usd
            ) AS loan_interest_repaid_usd,

            SUM(
                cp.loan_interest_accrued
            ) AS loan_interest_accrued,

            SUM(
                cp.loan_interest_accrued_usd
            ) AS loan_interest_accrued_usd,

            MAX(
                cp.opening_loan_balance
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_loan_balance,

            MAX(
                cp.opening_loan_balance_usd
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_loan_balance_usd,

            MAX(
                cp.closing_loan_balance
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_loan_balance,

            MAX(
                cp.closing_loan_balance_usd
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_loan_balance_usd

        FROM currency_periods AS cp

        GROUP BY
            cp.currency_code
    )

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        cs.currency_code,

                    'deposit',
                        jsonb_build_object(

                            'amount',
                                COALESCE(
                                    cs.deposit_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.deposit_amount_usd,
                                    0
                                )
                        ),

                    'withdrawal',
                        jsonb_build_object(

                            'amount',
                                COALESCE(
                                    cs.withdrawal_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.withdrawal_amount_usd,
                                    0
                                )
                        ),

                    'spending',
                        jsonb_build_object(

                            'amount',
                                COALESCE(
                                    cs.spending_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.spending_amount_usd,
                                    0
                                )
                        ),

                    'savings',
                        jsonb_build_object(

                            'opening',
                                COALESCE(
                                    cs.opening_savings,
                                    0
                                ),

                            'opening_usd',
                                COALESCE(
                                    cs.opening_savings_usd,
                                    0
                                ),

                            'inflow',
                                COALESCE(
                                    cs.savings_inflow,
                                    0
                                ),

                            'inflow_usd',
                                COALESCE(
                                    cs.savings_inflow_usd,
                                    0
                                ),

                            'outflow',
                                COALESCE(
                                    cs.savings_outflow,
                                    0
                                ),

                            'outflow_usd',
                                COALESCE(
                                    cs.savings_outflow_usd,
                                    0
                                ),

                            'saved',
                                COALESCE(
                                    cs.saving_amount,
                                    0
                                ),

                            'saved_usd',
                                COALESCE(
                                    cs.saving_amount_usd,
                                    0
                                ),

                            'closing',
                                COALESCE(
                                    cs.closing_savings,
                                    0
                                ),

                            'closing_usd',
                                COALESCE(
                                    cs.closing_savings_usd,
                                    0
                                )
                        ),

                    'investment',
                        jsonb_build_object(

                            'purchased',
                                COALESCE(
                                    cs.investment_purchase_amount,
                                    0
                                ),

                            'purchased_usd',
                                COALESCE(
                                    cs.investment_purchase_amount_usd,
                                    0
                                ),

                            'sold',
                                COALESCE(
                                    cs.investment_sale_amount,
                                    0
                                ),

                            'sold_usd',
                                COALESCE(
                                    cs.investment_sale_amount_usd,
                                    0
                                )
                        ),

                    'loan',
                        jsonb_build_object(

                            'opening_balance',
                                COALESCE(
                                    cs.opening_loan_balance,
                                    0
                                ),

                            'opening_balance_usd',
                                COALESCE(
                                    cs.opening_loan_balance_usd,
                                    0
                                ),

                            'disbursed',
                                COALESCE(
                                    cs.loan_disbursed_amount,
                                    0
                                ),

                            'disbursed_usd',
                                COALESCE(
                                    cs.loan_disbursed_amount_usd,
                                    0
                                ),

                            'repaid',
                                COALESCE(
                                    cs.loan_repayment_amount,
                                    0
                                ),

                            'repaid_usd',
                                COALESCE(
                                    cs.loan_repayment_amount_usd,
                                    0
                                ),

                            'principal_repaid',
                                COALESCE(
                                    cs.loan_principal_repaid,
                                    0
                                ),

                            'principal_repaid_usd',
                                COALESCE(
                                    cs.loan_principal_repaid_usd,
                                    0
                                ),

                            'interest_repaid',
                                COALESCE(
                                    cs.loan_interest_repaid,
                                    0
                                ),

                            'interest_repaid_usd',
                                COALESCE(
                                    cs.loan_interest_repaid_usd,
                                    0
                                ),

                            'interest_accrued',
                                COALESCE(
                                    cs.loan_interest_accrued,
                                    0
                                ),

                            'interest_accrued_usd',
                                COALESCE(
                                    cs.loan_interest_accrued_usd,
                                    0
                                ),

                            'closing_balance',
                                COALESCE(
                                    cs.closing_loan_balance,
                                    0
                                ),

                            'closing_balance_usd',
                                COALESCE(
                                    cs.closing_loan_balance_usd,
                                    0
                                )
                        )
                )
                ORDER BY
                    cs.currency_code
            ),
            '[]'::jsonb
        )

    INTO
        v_currencies

    FROM currency_summary AS cs;


    -- ==========================================================
    -- GOLD ACTIVITY - FISCAL YEAR TO DATE
    --
    -- Only periods up to the current fiscal period are included.
    -- Initial seed events are state initialization and therefore
    -- are excluded from purchase/sale/transfer activity.
    -- ==========================================================

    SELECT

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'investment_buy'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN e.gold_quantity

                    ELSE 0

                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'investment_sell'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN e.gold_quantity

                    ELSE 0

                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'investment_transfer_in'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN e.gold_quantity

                    ELSE 0

                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'investment_transfer_out'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN e.gold_quantity

                    ELSE 0

                END
            ),
            0
        )

    INTO
        v_gold_purchased,
        v_gold_sold,
        v_gold_transferred_in,
        v_gold_transferred_out

    FROM public.financial_pot_event AS e

    WHERE e.user_id =
          v_user_id

      AND e.country_code =
          v_country_code

      AND e.fiscal_year =
          v_fiscal_year

      AND e.period <=
          v_period;


    -- ==========================================================
    -- GOLD OPENING POSITION
    --
    -- Historical position before this fiscal year.
    -- ==========================================================

    SELECT
        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type IN (
                        'investment_buy'::public.financial_activity_type,
                        'investment_transfer_in'::public.financial_activity_type
                    )
                    THEN e.gold_quantity

                    WHEN e.activity_type IN (
                        'investment_sell'::public.financial_activity_type,
                        'investment_transfer_out'::public.financial_activity_type
                    )
                    THEN -e.gold_quantity

                    ELSE 0

                END
            ),
            0
        )

    INTO
        v_gold_opening

    FROM public.financial_pot_event AS e

    WHERE e.user_id =
          v_user_id

      AND e.country_code =
          v_country_code

      AND e.fiscal_year <
          v_fiscal_year;


    -- ==========================================================
    -- GOLD CLOSING POSITION
    -- ==========================================================

    v_gold_closing :=
          v_gold_opening
        + v_gold_purchased
        + v_gold_transferred_in
        - v_gold_sold
        - v_gold_transferred_out;


    v_gold :=
        jsonb_build_object(

            'opening_quantity',
                v_gold_opening,

            'purchased',
                v_gold_purchased,

            'sold',
                v_gold_sold,

            'transferred_in',
                v_gold_transferred_in,

            'transferred_out',
                v_gold_transferred_out,

            'closing_quantity',
                v_gold_closing
        );


    -- ==========================================================
    -- RESPONSE
    -- ==========================================================

    RETURN jsonb_build_object(

        'fiscal_year',
            v_fiscal_year,

        'current_period',
            v_period,


        -- ======================================================
        -- FY-TO-DATE ALL CURRENCIES - USD EQUIVALENT
        -- ======================================================

        'money_in',
            v_money_in,

        'distribution',
            v_distribution,


        -- ======================================================
        -- FY-TO-DATE PER CURRENCY - NATIVE + USD
        -- ======================================================

        'money_by_currency',
            v_money_by_currency,


        -- ======================================================
        -- FISCAL YEAR BEHAVIOR
        --
        -- This is the identity for the first / summary report.
        -- ======================================================

        'behavior',
            v_behavior,

        'behavior_scores',
            jsonb_build_object(

                'shopper_percentage',
                    v_shopper_score_percentage,

                'saver_percentage',
                    v_saver_score_percentage,

                'investor_percentage',
                    v_investor_score_percentage,

                'borrower_percentage',
                    v_borrower_score_percentage
            ),


        -- ======================================================
        -- CURRENT PERIOD BEHAVIOR
        --
        -- Retained for compatibility.
        -- ======================================================

        'current_period_behavior',
            v_current_period_behavior,

        'current_period_behavior_scores',
            jsonb_build_object(

                'shopper_percentage',
                    v_current_period_shopper_score_percentage,

                'saver_percentage',
                    v_current_period_saver_score_percentage,

                'investor_percentage',
                    v_current_period_investor_score_percentage,

                'borrower_percentage',
                    v_current_period_borrower_score_percentage
            ),


        -- ======================================================
        -- FY-TO-DATE DETAIL DATA
        -- ======================================================

        'currencies',
            v_currencies,

        'gold',
            v_gold
    );

END;
$function$;