CREATE OR REPLACE FUNCTION public.resolve_financial_behavior(
  p_spending_usd numeric,
  p_saving_usd numeric,
  p_investment_usd numeric,
  p_borrowing_usd numeric
)
RETURNS TABLE (
  behavior financial_behavior_type,
  rule_id uuid,

  shopper_score_percentage numeric,
  saver_score_percentage numeric,
  investor_score_percentage numeric,
  borrower_score_percentage numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_total numeric := 0;

  v_shop numeric := 0;
  v_save numeric := 0;
  v_invest numeric := 0;
  v_borrow numeric := 0;

  v_top_one numeric := 0;
  v_top_two numeric := 0;

  v_rule record;
  v_metric_percentage numeric := 0;
BEGIN

  -- ==========================================================
  -- NORMALISE VALUES
  -- ==========================================================

  p_spending_usd :=
    GREATEST(
      COALESCE(p_spending_usd, 0),
      0
    );

  p_saving_usd :=
    GREATEST(
      COALESCE(p_saving_usd, 0),
      0
    );

  p_investment_usd :=
    GREATEST(
      COALESCE(p_investment_usd, 0),
      0
    );

  p_borrowing_usd :=
    GREATEST(
      COALESCE(p_borrowing_usd, 0),
      0
    );


  v_total :=
      p_spending_usd
    + p_saving_usd
    + p_investment_usd
    + p_borrowing_usd;


  -- ==========================================================
  -- BEHAVIOUR SCORES
  -- ==========================================================

  IF v_total > 0 THEN

    v_shop :=
      ROUND(
        p_spending_usd / v_total * 100,
        4
      );

    v_save :=
      ROUND(
        p_saving_usd / v_total * 100,
        4
      );

    v_invest :=
      ROUND(
        p_investment_usd / v_total * 100,
        4
      );

    v_borrow :=
      ROUND(
        p_borrowing_usd / v_total * 100,
        4
      );

  END IF;


  -- ==========================================================
  -- FIND STRONGEST TWO BEHAVIOURS
  -- ==========================================================

  SELECT
    MAX(
      CASE
        WHEN rn = 1
        THEN percentage
      END
    ),
    MAX(
      CASE
        WHEN rn = 2
        THEN percentage
      END
    )

  INTO
    v_top_one,
    v_top_two

  FROM (
    SELECT
      percentage,

      ROW_NUMBER() OVER (
        ORDER BY percentage DESC
      ) AS rn

    FROM (
      VALUES
        (v_shop),
        (v_save),
        (v_invest),
        (v_borrow)
    ) AS values_table(percentage)

  ) ranked;


  v_top_one :=
    COALESCE(v_top_one, 0);

  v_top_two :=
    COALESCE(v_top_two, 0);


  -- ==========================================================
  -- EVALUATE CONFIGURED RULES
  -- ==========================================================

  FOR v_rule IN

    SELECT *
    FROM public.financial_behavior_rule
    WHERE is_active = true
    ORDER BY priority ASC

  LOOP

    -- --------------------------------------------------------
    -- NEUTRAL
    -- --------------------------------------------------------

    IF v_rule.conditions->>'rule_type' = 'zero_activity'
       AND v_total = 0
    THEN

      behavior :=
        v_rule.behavior;

      rule_id :=
        v_rule.id;

      shopper_score_percentage := v_shop;
      saver_score_percentage := v_save;
      investor_score_percentage := v_invest;
      borrower_score_percentage := v_borrow;

      RETURN NEXT;
      RETURN;

    END IF;


    -- --------------------------------------------------------
    -- BALANCED
    -- --------------------------------------------------------

    IF v_rule.conditions->>'rule_type' = 'lead_gap'
       AND v_total > 0
       AND (
         v_top_one - v_top_two
       ) <= COALESCE(
         (
           v_rule.conditions
             ->>'maximum_lead_percentage'
         )::numeric,
         10
       )
    THEN

      behavior :=
        v_rule.behavior;

      rule_id :=
        v_rule.id;

      shopper_score_percentage := v_shop;
      saver_score_percentage := v_save;
      investor_score_percentage := v_invest;
      borrower_score_percentage := v_borrow;

      RETURN NEXT;
      RETURN;

    END IF;


    -- --------------------------------------------------------
    -- DOMINANT
    -- --------------------------------------------------------

    IF v_rule.conditions->>'rule_type' = 'dominant'
    THEN

      CASE v_rule.conditions->>'metric'

        WHEN 'spending' THEN
          v_metric_percentage := v_shop;

        WHEN 'saving' THEN
          v_metric_percentage := v_save;

        WHEN 'investment' THEN
          v_metric_percentage := v_invest;

        WHEN 'borrowing' THEN
          v_metric_percentage := v_borrow;

        ELSE
          v_metric_percentage := 0;

      END CASE;


      IF v_metric_percentage >=
        COALESCE(
          (
            v_rule.conditions
              ->>'minimum_percentage'
          )::numeric,
          30
        )

        AND v_metric_percentage = v_top_one
      THEN

        behavior :=
          v_rule.behavior;

        rule_id :=
          v_rule.id;

        shopper_score_percentage := v_shop;
        saver_score_percentage := v_save;
        investor_score_percentage := v_invest;
        borrower_score_percentage := v_borrow;

        RETURN NEXT;
        RETURN;

      END IF;

    END IF;

  END LOOP;


  -- ==========================================================
  -- SAFETY FALLBACK
  -- ==========================================================

  behavior :=
    'balanced';

  rule_id :=
    NULL;

  shopper_score_percentage := v_shop;
  saver_score_percentage := v_save;
  investor_score_percentage := v_invest;
  borrower_score_percentage := v_borrow;

  RETURN NEXT;

END;
$$;


CREATE OR REPLACE FUNCTION public.calculate_financial_pot_percentages(
  p_user_id text,
  p_currency_code text,
  p_fiscal_year integer,
  p_period integer
)
RETURNS public.financial_pot
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available_usd numeric := 0;

  v_withdrawal_usd numeric := 0;
  v_spending_usd numeric := 0;
  v_investment_usd numeric := 0;
  v_repayment_usd numeric := 0;

  v_borrowing_inflow_usd numeric := 0;
  v_total_inflow_usd numeric := 0;

  v_result public.financial_pot;
BEGIN

  SELECT
    opening_savings_usd
      + savings_inflow_usd,

    savings_inflow_usd,

    loan_disbursed_amount_usd

  INTO
    v_available_usd,
    v_total_inflow_usd,
    v_borrowing_inflow_usd

  FROM public.financial_pot

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  IF NOT FOUND THEN
    RAISE EXCEPTION 'FINANCIAL_POT_NOT_FOUND';
  END IF;


  -- ==========================================================
  -- USE ACTUAL CASH EFFECTS FROM EVENTS
  --
  -- Important because fees/tax may cause cash movement
  -- to differ from principal transaction amount.
  -- ==========================================================

  SELECT

    COALESCE(
      SUM(cash_amount_usd)
        FILTER (
          WHERE activity_type = 'withdrawal'
        ),
      0
    ),

    COALESCE(
      SUM(cash_amount_usd)
        FILTER (
          WHERE activity_type = 'spending'
        ),
      0
    ),

    COALESCE(
      SUM(cash_amount_usd)
        FILTER (
          WHERE activity_type = 'investment_buy'
        ),
      0
    ),

    COALESCE(
      SUM(cash_amount_usd)
        FILTER (
          WHERE activity_type = 'loan_repayment'
        ),
      0
    )

  INTO
    v_withdrawal_usd,
    v_spending_usd,
    v_investment_usd,
    v_repayment_usd

  FROM public.financial_pot_event

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  UPDATE public.financial_pot
  SET

    withdrawal_percentage =
      CASE
        WHEN v_available_usd > 0
        THEN ROUND(
          v_withdrawal_usd
          / v_available_usd
          * 100,
          4
        )
        ELSE 0
      END,


    spending_percentage =
      CASE
        WHEN v_available_usd > 0
        THEN ROUND(
          v_spending_usd
          / v_available_usd
          * 100,
          4
        )
        ELSE 0
      END,


    investment_percentage =
      CASE
        WHEN v_available_usd > 0
        THEN ROUND(
          v_investment_usd
          / v_available_usd
          * 100,
          4
        )
        ELSE 0
      END,


    repayment_percentage =
      CASE
        WHEN v_available_usd > 0
        THEN ROUND(
          v_repayment_usd
          / v_available_usd
          * 100,
          4
        )
        ELSE 0
      END,


    /*
     * For the allocation chart, Saving means:
     *
     * money still remaining in the Savings Pot.
     */
    saving_percentage =
      CASE
        WHEN v_available_usd > 0
        THEN ROUND(
          closing_savings_usd
          / v_available_usd
          * 100,
          4
        )
        ELSE 0
      END,


    /*
     * Borrowing is a funding-source percentage.
     *
     * It is intentionally NOT part of the allocation doughnut.
     */
    borrowing_percentage =
      CASE
        WHEN v_total_inflow_usd > 0
        THEN ROUND(
          v_borrowing_inflow_usd
          / v_total_inflow_usd
          * 100,
          4
        )
        ELSE 0
      END,


    updated_at = now()

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  SELECT *
  INTO v_result
  FROM public.financial_pot
  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  RETURN v_result;

END;
$$;

