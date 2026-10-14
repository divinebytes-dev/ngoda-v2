CREATE OR REPLACE FUNCTION public.calculate_financial_pot_percentages(
    p_user_id text,
    p_currency_code text,
    p_fiscal_year integer,
    p_period integer
)
RETURNS public.financial_pot
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_currency_code text;

    v_withdrawal_usd numeric(20, 6) := 0;
    v_spending_usd numeric(20, 6) := 0;
    v_investment_usd numeric(20, 6) := 0;
    v_repayment_usd numeric(20, 6) := 0;
    v_savings_usd numeric(20, 6) := 0;

    v_distribution_total_usd numeric(20, 6) := 0;

    v_withdrawal_percentage numeric(9, 4) := 0;
    v_spending_percentage numeric(9, 4) := 0;
    v_saving_percentage numeric(9, 4) := 0;
    v_investment_percentage numeric(9, 4) := 0;
    v_repayment_percentage numeric(9, 4) := 0;

    v_result public.financial_pot;
BEGIN

    -- ==========================================================
    -- VALIDATION
    -- ==========================================================

    IF p_user_id IS NULL
       OR trim(p_user_id) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_POT_USER_REQUIRED';
    END IF;

    IF p_currency_code IS NULL
       OR trim(p_currency_code) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_POT_CURRENCY_REQUIRED';
    END IF;

    IF p_fiscal_year IS NULL THEN
        RAISE EXCEPTION
            'FINANCIAL_POT_FISCAL_YEAR_REQUIRED';
    END IF;

    IF p_period IS NULL
       OR p_period < 1
       OR p_period > 12 THEN
        RAISE EXCEPTION
            'FINANCIAL_POT_INVALID_PERIOD';
    END IF;

    v_currency_code :=
        lower(trim(p_currency_code));


    -- ==========================================================
    -- CURRENT SAVINGS POSITION
    -- ==========================================================

    SELECT
        COALESCE(
            fp.closing_savings_usd,
            0
        )
    INTO
        v_savings_usd
    FROM public.financial_pot AS fp
    WHERE fp.user_id = p_user_id
      AND fp.currency_code = v_currency_code
      AND fp.fiscal_year = p_fiscal_year
      AND fp.period = p_period;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'FINANCIAL_POT_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- ACTUAL DISTRIBUTION CASH MOVEMENTS
    --
    -- Seed events represent opening state and must never count
    -- as current-period behavior.
    -- ==========================================================

    SELECT

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
        v_withdrawal_usd,
        v_spending_usd,
        v_investment_usd,
        v_repayment_usd

    FROM public.financial_pot_event AS e

    WHERE e.user_id = p_user_id
      AND e.currency_code = v_currency_code
      AND e.fiscal_year = p_fiscal_year
      AND e.period = p_period

      AND lower(e.transaction_type)
          NOT LIKE 'initial\_%' ESCAPE '\';


    -- ==========================================================
    -- DISTRIBUTION
    --
    -- 100% =
    --
    -- Withdrawal
    -- + Spending
    -- + Investment
    -- + Repayment
    -- + Closing Savings
    -- ==========================================================

    v_distribution_total_usd :=
          v_withdrawal_usd
        + v_spending_usd
        + v_investment_usd
        + v_repayment_usd
        + v_savings_usd;


    IF v_distribution_total_usd > 0 THEN

        v_withdrawal_percentage :=
            round(
                (
                    v_withdrawal_usd
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
                    v_spending_usd
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
                    v_investment_usd
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
                    v_repayment_usd
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
                    v_savings_usd
                    /
                    v_distribution_total_usd
                    *
                    100
                )::numeric,
                4
            );

    END IF;


    -- ==========================================================
    -- UPDATE POT
    --
    -- borrowing_percentage is deliberately zero.
    --
    -- Loan disbursement is a SOURCE of money, not a use and not
    -- the Borrower identity metric.
    -- ==========================================================

    UPDATE public.financial_pot
    SET
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

        updated_at =
            now()

    WHERE user_id = p_user_id
      AND currency_code = v_currency_code
      AND fiscal_year = p_fiscal_year
      AND period = p_period

    RETURNING *
    INTO v_result;


    RETURN v_result;

END;
$function$;