CREATE OR REPLACE FUNCTION public.calculate_financial_behavior_snapshot(
    p_user_id text,
    p_country_code text,
    p_currency_code text,
    p_fiscal_year integer,
    p_period integer,
    p_scope public.financial_behavior_scope
)
RETURNS public.financial_behavior
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_country_code text;
    v_currency_code text;

    v_deposit_amount_usd numeric(20, 6) := 0;

    v_withdrawal_amount_usd numeric(20, 6) := 0;
    v_spending_amount_usd numeric(20, 6) := 0;
    v_saving_amount_usd numeric(20, 6) := 0;
    v_investment_amount_usd numeric(20, 6) := 0;

    v_borrowing_amount_usd numeric(20, 6) := 0;
    v_repayment_amount_usd numeric(20, 6) := 0;

    v_distribution_total_usd numeric(20, 6) := 0;

    v_withdrawal_percentage numeric(9, 4) := 0;
    v_spending_percentage numeric(9, 4) := 0;
    v_saving_percentage numeric(9, 4) := 0;
    v_investment_percentage numeric(9, 4) := 0;
    v_borrowing_percentage numeric(9, 4) := 0;
    v_repayment_percentage numeric(9, 4) := 0;

    v_shopper_score numeric(9, 4) := 0;
    v_saver_score numeric(9, 4) := 0;
    v_investor_score numeric(9, 4) := 0;
    v_borrower_score numeric(9, 4) := 0;

    v_top_score numeric(9, 4) := 0;
    v_second_score numeric(9, 4) := 0;

    v_minimum_percentage numeric := 30;
    v_maximum_lead_percentage numeric := 10;

    v_behavior public.financial_behavior_type :=
        'neutral'::public.financial_behavior_type;

    v_rule_id uuid;

    v_result public.financial_behavior;
BEGIN

    -- ==========================================================
    -- VALIDATION / NORMALIZATION
    -- ==========================================================

    IF p_user_id IS NULL
       OR trim(p_user_id) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_USER_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR trim(p_country_code) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_COUNTRY_REQUIRED';
    END IF;

    IF p_fiscal_year IS NULL THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_FISCAL_YEAR_REQUIRED';
    END IF;

    IF p_scope IS NULL THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_SCOPE_REQUIRED';
    END IF;

    IF p_scope =
        'period'::public.financial_behavior_scope
       AND (
            p_period IS NULL
            OR p_period < 1
            OR p_period > 12
       )
    THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_INVALID_PERIOD';
    END IF;

    IF p_scope =
        'fiscal_year'::public.financial_behavior_scope
       AND p_period IS NOT NULL
    THEN
        RAISE EXCEPTION
            'FINANCIAL_BEHAVIOR_YEAR_PERIOD_MUST_BE_NULL';
    END IF;

    v_country_code :=
        lower(trim(p_country_code));

    v_currency_code :=
        CASE
            WHEN p_currency_code IS NULL
                THEN NULL
            ELSE lower(trim(p_currency_code))
        END;


    -- ==========================================================
    -- READ RULE CONFIGURATION
    -- ==========================================================

    SELECT
        COALESCE(
            (r.conditions ->> 'minimum_percentage')::numeric,
            30
        )
    INTO
        v_minimum_percentage
    FROM public.financial_behavior_rule AS r
    WHERE r.code = 'SAVER_V1'
      AND r.is_active = true
    LIMIT 1;

    v_minimum_percentage :=
        COALESCE(
            v_minimum_percentage,
            30
        );


    SELECT
        COALESCE(
            (
                r.conditions
                ->> 'maximum_lead_percentage'
            )::numeric,
            10
        )
    INTO
        v_maximum_lead_percentage
    FROM public.financial_behavior_rule AS r
    WHERE r.code = 'BALANCED_V1'
      AND r.is_active = true
    LIMIT 1;

    v_maximum_lead_percentage :=
        COALESCE(
            v_maximum_lead_percentage,
            10
        );


    -- ==========================================================
    -- ACTIVITY VALUES
    --
    -- amount_usd keeps the business/activity amount.
    --
    -- Cash-flow behavior uses cash_amount_usd.
    --
    -- Seed events are explicitly excluded.
    -- ==========================================================

    SELECT

        -- ------------------------------------------------------
        -- Deposit / source information
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'deposit'::public.financial_activity_type
                    THEN COALESCE(
                        NULLIF(e.cash_amount_usd, 0),
                        e.amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- Withdrawal
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'withdrawal'::public.financial_activity_type
                    THEN COALESCE(
                        NULLIF(e.cash_amount_usd, 0),
                        e.amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- Spending
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'spending'::public.financial_activity_type
                    THEN COALESCE(
                        NULLIF(e.cash_amount_usd, 0),
                        e.amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- Investment purchases
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'investment_buy'::public.financial_activity_type
                    THEN COALESCE(
                        NULLIF(e.cash_amount_usd, 0),
                        NULLIF(e.investment_cost_usd, 0),
                        e.amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- Loan disbursement
        --
        -- Retained as reporting data only.
        -- It is NOT a behavior score.
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'loan_disbursement'::public.financial_activity_type
                    THEN COALESCE(
                        e.amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- Repayment
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'loan_repayment'::public.financial_activity_type
                    THEN COALESCE(
                        NULLIF(e.cash_amount_usd, 0),
                        NULLIF(e.amount_usd, 0),
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
        )

    INTO
        v_deposit_amount_usd,
        v_withdrawal_amount_usd,
        v_spending_amount_usd,
        v_investment_amount_usd,
        v_borrowing_amount_usd,
        v_repayment_amount_usd

    FROM public.financial_pot_event AS e

    WHERE e.user_id = p_user_id

      AND e.country_code = v_country_code

      AND e.fiscal_year = p_fiscal_year

      AND (
            v_currency_code IS NULL
            OR e.currency_code = v_currency_code
      )

      AND (
            (
                p_scope =
                    'period'::public.financial_behavior_scope

                AND e.period =
                    p_period
            )

            OR

            (
                p_scope =
                    'fiscal_year'::public.financial_behavior_scope
            )
      )

      AND lower(e.transaction_type)
          NOT LIKE 'initial\_%' ESCAPE '\';


    -- ==========================================================
    -- CLOSING SAVINGS
    --
    -- Period:
    -- current period closing position.
    --
    -- Fiscal year:
    -- latest closing position for each currency, not a SUM of
    -- every period's closing balance.
    -- ==========================================================

    IF p_scope =
        'period'::public.financial_behavior_scope
    THEN

        SELECT
            COALESCE(
                SUM(fp.closing_savings_usd),
                0
            )
        INTO
            v_saving_amount_usd
        FROM public.financial_pot AS fp
        WHERE fp.user_id = p_user_id
          AND fp.fiscal_year = p_fiscal_year
          AND fp.period = p_period

          AND (
                v_currency_code IS NULL
                OR fp.currency_code =
                    v_currency_code
          );

    ELSE

        WITH ranked_pots AS (
            SELECT
                fp.currency_code,
                fp.closing_savings_usd,

                ROW_NUMBER() OVER (
                    PARTITION BY fp.currency_code
                    ORDER BY fp.period DESC
                ) AS row_number

            FROM public.financial_pot AS fp

            WHERE fp.user_id = p_user_id
              AND fp.fiscal_year = p_fiscal_year

              AND (
                    v_currency_code IS NULL
                    OR fp.currency_code =
                        v_currency_code
              )
        )

        SELECT
            COALESCE(
                SUM(rp.closing_savings_usd),
                0
            )
        INTO
            v_saving_amount_usd
        FROM ranked_pots AS rp
        WHERE rp.row_number = 1;

    END IF;


    -- ==========================================================
    -- DISTRIBUTION TOTAL
    --
    -- Withdrawal has no identity, but remains in denominator.
    -- ==========================================================

    v_distribution_total_usd :=
          v_withdrawal_amount_usd
        + v_spending_amount_usd
        + v_investment_amount_usd
        + v_repayment_amount_usd
        + v_saving_amount_usd;


    -- ==========================================================
    -- DISTRIBUTION PERCENTAGES
    -- ==========================================================

    IF v_distribution_total_usd > 0 THEN

        v_withdrawal_percentage :=
            round(
                (
                    v_withdrawal_amount_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

        v_spending_percentage :=
            round(
                (
                    v_spending_amount_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

        v_saving_percentage :=
            round(
                (
                    v_saving_amount_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

        v_investment_percentage :=
            round(
                (
                    v_investment_amount_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

        v_repayment_percentage :=
            round(
                (
                    v_repayment_amount_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

    END IF;


    -- ==========================================================
    -- IDENTITY SCORES
    --
    -- The identity values intentionally use the SAME percentages
    -- displayed in the allocation doughnut.
    --
    -- Withdrawal is therefore part of 100%, but not assigned an
    -- identity.
    -- ==========================================================

    v_shopper_score :=
        v_spending_percentage;

    v_saver_score :=
        v_saving_percentage;

    v_investor_score :=
        v_investment_percentage;

    v_borrower_score :=
        v_repayment_percentage;

    v_borrowing_percentage :=
        0;


    -- ==========================================================
    -- TOP TWO IDENTITY SCORES
    -- ==========================================================

    SELECT
        ranked.score
    INTO
        v_top_score
    FROM (
        VALUES
            (v_shopper_score),
            (v_saver_score),
            (v_investor_score),
            (v_borrower_score)
    ) AS ranked(score)
    ORDER BY ranked.score DESC
    LIMIT 1;


    SELECT
        ranked.score
    INTO
        v_second_score
    FROM (
        VALUES
            (v_shopper_score),
            (v_saver_score),
            (v_investor_score),
            (v_borrower_score)
    ) AS ranked(score)
    ORDER BY ranked.score DESC
    OFFSET 1
    LIMIT 1;


    v_top_score :=
        COALESCE(
            v_top_score,
            0
        );

    v_second_score :=
        COALESCE(
            v_second_score,
            0
        );


    -- ==========================================================
    -- CLASSIFICATION
    -- ==========================================================

    IF v_distribution_total_usd <= 0
       OR v_top_score <= 0
    THEN

        v_behavior :=
            'neutral'::public.financial_behavior_type;

    ELSIF v_top_score < v_minimum_percentage
    THEN

        v_behavior :=
            'neutral'::public.financial_behavior_type;

    ELSIF
        v_second_score > 0

        AND (
            v_top_score
            -
            v_second_score
        ) <= v_maximum_lead_percentage
    THEN

        v_behavior :=
            'balanced'::public.financial_behavior_type;

    ELSIF v_saver_score = v_top_score
    THEN

        v_behavior :=
            'saver'::public.financial_behavior_type;

    ELSIF v_investor_score = v_top_score
    THEN

        v_behavior :=
            'investor'::public.financial_behavior_type;

    ELSIF v_shopper_score = v_top_score
    THEN

        v_behavior :=
            'shopper'::public.financial_behavior_type;

    ELSE

        v_behavior :=
            'borrower'::public.financial_behavior_type;

    END IF;


    -- ==========================================================
    -- RULE
    -- ==========================================================

    SELECT
        r.id
    INTO
        v_rule_id
    FROM public.financial_behavior_rule AS r
    WHERE r.is_active = true
      AND r.behavior = v_behavior
    ORDER BY
        r.priority DESC,
        r.created_at ASC
    LIMIT 1;


    -- ==========================================================
    -- UPDATE EXISTING SNAPSHOT
    --
    -- Partial unique indexes cannot safely be targeted by one
    -- generic ON CONFLICT clause, so UPDATE + INSERT is clearer.
    -- ==========================================================

    UPDATE public.financial_behavior
    SET
        country_code =
            v_country_code,

        behavior =
            v_behavior,

        deposit_amount_usd =
            v_deposit_amount_usd,

        withdrawal_amount_usd =
            v_withdrawal_amount_usd,

        spending_amount_usd =
            v_spending_amount_usd,

        saving_amount_usd =
            v_saving_amount_usd,

        investment_amount_usd =
            v_investment_amount_usd,

        borrowing_amount_usd =
            v_borrowing_amount_usd,

        repayment_amount_usd =
            v_repayment_amount_usd,

        withdrawal_percentage =
            v_withdrawal_percentage,

        spending_percentage =
            v_spending_percentage,

        saving_percentage =
            v_saving_percentage,

        investment_percentage =
            v_investment_percentage,

        borrowing_percentage =
            0,

        repayment_percentage =
            v_repayment_percentage,

        shopper_score_percentage =
            v_shopper_score,

        saver_score_percentage =
            v_saver_score,

        investor_score_percentage =
            v_investor_score,

        borrower_score_percentage =
            v_borrower_score,

        rule_id =
            v_rule_id,

        calculated_at =
            now(),

        updated_at =
            now()

    WHERE user_id =
            p_user_id

      AND fiscal_year =
            p_fiscal_year

      AND scope =
            p_scope

      AND (
            (
                p_scope =
                    'period'::public.financial_behavior_scope

                AND period =
                    p_period
            )

            OR

            (
                p_scope =
                    'fiscal_year'::public.financial_behavior_scope

                AND period IS NULL
            )
      )

      AND (
            (
                v_currency_code IS NULL
                AND currency_code IS NULL
            )

            OR

            currency_code =
                v_currency_code
      )

    RETURNING *
    INTO v_result;


    -- ==========================================================
    -- INSERT IF MISSING
    -- ==========================================================

    IF NOT FOUND THEN

        INSERT INTO public.financial_behavior (
            user_id,
            country_code,
            currency_code,

            fiscal_year,
            period,
            scope,

            behavior,

            deposit_amount_usd,
            withdrawal_amount_usd,
            spending_amount_usd,
            saving_amount_usd,
            investment_amount_usd,
            borrowing_amount_usd,
            repayment_amount_usd,

            withdrawal_percentage,
            spending_percentage,
            saving_percentage,
            investment_percentage,
            borrowing_percentage,
            repayment_percentage,

            shopper_score_percentage,
            saver_score_percentage,
            investor_score_percentage,
            borrower_score_percentage,

            rule_id,

            calculated_at,
            created_at,
            updated_at
        )
        VALUES (
            p_user_id,
            v_country_code,
            v_currency_code,

            p_fiscal_year,

            CASE
                WHEN p_scope =
                    'period'::public.financial_behavior_scope
                THEN p_period

                ELSE NULL
            END,

            p_scope,

            v_behavior,

            v_deposit_amount_usd,
            v_withdrawal_amount_usd,
            v_spending_amount_usd,
            v_saving_amount_usd,
            v_investment_amount_usd,
            v_borrowing_amount_usd,
            v_repayment_amount_usd,

            v_withdrawal_percentage,
            v_spending_percentage,
            v_saving_percentage,
            v_investment_percentage,
            0,
            v_repayment_percentage,

            v_shopper_score,
            v_saver_score,
            v_investor_score,
            v_borrower_score,

            v_rule_id,

            now(),
            now(),
            now()
        )

        RETURNING *
        INTO v_result;

    END IF;


    RETURN v_result;

END;
$function$;