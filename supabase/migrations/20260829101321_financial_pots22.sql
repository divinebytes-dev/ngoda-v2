CREATE OR REPLACE FUNCTION public.calculate_financial_behavior_snapshot(
  p_user_id text,
  p_country_code text,
  p_currency_code text,
  p_fiscal_year integer,
  p_period integer,
  p_scope financial_behavior_scope
)
RETURNS public.financial_behavior
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deposit numeric := 0;

  v_withdrawal numeric := 0;
  v_spending numeric := 0;

  v_saving numeric := 0;
  v_investment numeric := 0;
  v_borrowing numeric := 0;
  v_repayment numeric := 0;

  v_normal_deposit_inflow numeric := 0;
  v_behavior_saving numeric := 0;

  v_result_behavior financial_behavior_type;
  v_rule_id uuid;

  v_shop_score numeric := 0;
  v_save_score numeric := 0;
  v_invest_score numeric := 0;
  v_borrow_score numeric := 0;

  v_allocation_base numeric := 0;

  v_withdrawal_pct numeric := 0;
  v_spending_pct numeric := 0;
  v_saving_pct numeric := 0;
  v_investment_pct numeric := 0;
  v_repayment_pct numeric := 0;
  v_borrowing_pct numeric := 0;

  v_result public.financial_behavior;
BEGIN

  -- ==========================================================
  -- VALIDATE SCOPE
  -- ==========================================================

  IF p_scope = 'period'
     AND (
       p_period IS NULL
       OR p_period < 1
       OR p_period > 12
     )
  THEN
    RAISE EXCEPTION 'FINANCIAL_BEHAVIOR_INVALID_PERIOD';
  END IF;


  -- ==========================================================
  -- AGGREGATE POTS
  --
  -- currency_code NULL = all currencies.
  -- ==========================================================

  SELECT

    COALESCE(
      SUM(deposit_amount_usd),
      0
    ),

    COALESCE(
      SUM(withdrawal_amount_usd),
      0
    ),

    COALESCE(
      SUM(spending_amount_usd),
      0
    ),

    COALESCE(
      SUM(investment_purchase_amount_usd),
      0
    ),

    COALESCE(
      SUM(loan_disbursed_amount_usd),
      0
    ),

    COALESCE(
      SUM(loan_repayment_amount_usd),
      0
    )

  INTO
    v_deposit,
    v_withdrawal,
    v_spending,
    v_investment,
    v_borrowing,
    v_repayment

  FROM public.financial_pot

  WHERE user_id = p_user_id

    AND country_code = lower(p_country_code)

    AND fiscal_year = p_fiscal_year

    AND (
      p_currency_code IS NULL
      OR currency_code = lower(p_currency_code)
    )

    AND (
      (
        p_scope = 'period'
        AND period = p_period
      )
      OR
      p_scope = 'fiscal_year'
    );


  -- ==========================================================
  -- QUALIFYING SAVER INFLOW
  --
  -- Only true deposit activity counts toward Saver behaviour.
  --
  -- This intentionally excludes:
  -- gold sale proceeds
  -- loan disbursements
  -- ==========================================================

  SELECT
    COALESCE(
      SUM(cash_amount_usd)
        FILTER (
          WHERE activity_type = 'deposit'
        ),
      0
    )

  INTO v_normal_deposit_inflow

  FROM public.financial_pot_event

  WHERE user_id = p_user_id

    AND country_code = lower(p_country_code)

    AND fiscal_year = p_fiscal_year

    AND (
      p_currency_code IS NULL
      OR currency_code = lower(p_currency_code)
    )

    AND (
      (
        p_scope = 'period'
        AND period = p_period
      )
      OR
      p_scope = 'fiscal_year'
    );


  -- ==========================================================
  -- SAVER BEHAVIOUR
  --
  -- Amount genuinely retained from qualifying incoming money.
  --
  -- Borrowing and gold sales can increase the Savings POSITION,
  -- but do not create Saver behaviour by themselves.
  -- ==========================================================

  v_behavior_saving :=
    GREATEST(
      v_normal_deposit_inflow

      - v_withdrawal
      - v_spending
      - v_investment
      - v_repayment,

      0
    );


  v_saving :=
    v_behavior_saving;


  -- ==========================================================
  -- RESOLVE PRIMARY BEHAVIOUR
  -- ==========================================================

  SELECT
    r.behavior,
    r.rule_id,
    r.shopper_score_percentage,
    r.saver_score_percentage,
    r.investor_score_percentage,
    r.borrower_score_percentage

  INTO
    v_result_behavior,
    v_rule_id,
    v_shop_score,
    v_save_score,
    v_invest_score,
    v_borrow_score

  FROM public.resolve_financial_behavior(
    v_spending,
    v_saving,
    v_investment,
    v_borrowing
  ) r;


  -- ==========================================================
  -- DISPLAY / ACTIVITY RATIOS
  --
  -- These are separate from behaviour scores.
  -- ==========================================================

  v_allocation_base :=
      v_withdrawal
    + v_spending
    + v_saving
    + v_investment
    + v_repayment;


  IF v_allocation_base > 0 THEN

    v_withdrawal_pct :=
      ROUND(
        v_withdrawal
        / v_allocation_base
        * 100,
        4
      );

    v_spending_pct :=
      ROUND(
        v_spending
        / v_allocation_base
        * 100,
        4
      );

    v_saving_pct :=
      ROUND(
        v_saving
        / v_allocation_base
        * 100,
        4
      );

    v_investment_pct :=
      ROUND(
        v_investment
        / v_allocation_base
        * 100,
        4
      );

    v_repayment_pct :=
      ROUND(
        v_repayment
        / v_allocation_base
        * 100,
        4
      );

  END IF;


  /*
   * Borrowing remains a funding-side ratio.
   */
  IF v_deposit > 0 THEN

    v_borrowing_pct :=
      ROUND(
        v_borrowing
        / v_deposit
        * 100,
        4
      );

  END IF;


  -- ==========================================================
  -- UPSERT PERIOD
  -- ==========================================================

  IF p_scope = 'period' THEN

    IF p_currency_code IS NULL THEN

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
        updated_at
      )
      VALUES (
        p_user_id,
        lower(p_country_code),
        NULL,

        p_fiscal_year,
        p_period,
        'period',

        v_result_behavior,

        v_deposit,
        v_withdrawal,
        v_spending,
        v_saving,
        v_investment,
        v_borrowing,
        v_repayment,

        v_withdrawal_pct,
        v_spending_pct,
        v_saving_pct,
        v_investment_pct,
        v_borrowing_pct,
        v_repayment_pct,

        v_shop_score,
        v_save_score,
        v_invest_score,
        v_borrow_score,

        v_rule_id,

        now(),
        now()
      )
      ON CONFLICT (
        user_id,
        fiscal_year,
        period
      )
      WHERE
        scope = 'period'
        AND currency_code IS NULL

      DO UPDATE SET

        behavior =
          EXCLUDED.behavior,

        deposit_amount_usd =
          EXCLUDED.deposit_amount_usd,

        withdrawal_amount_usd =
          EXCLUDED.withdrawal_amount_usd,

        spending_amount_usd =
          EXCLUDED.spending_amount_usd,

        saving_amount_usd =
          EXCLUDED.saving_amount_usd,

        investment_amount_usd =
          EXCLUDED.investment_amount_usd,

        borrowing_amount_usd =
          EXCLUDED.borrowing_amount_usd,

        repayment_amount_usd =
          EXCLUDED.repayment_amount_usd,

        withdrawal_percentage =
          EXCLUDED.withdrawal_percentage,

        spending_percentage =
          EXCLUDED.spending_percentage,

        saving_percentage =
          EXCLUDED.saving_percentage,

        investment_percentage =
          EXCLUDED.investment_percentage,

        borrowing_percentage =
          EXCLUDED.borrowing_percentage,

        repayment_percentage =
          EXCLUDED.repayment_percentage,

        shopper_score_percentage =
          EXCLUDED.shopper_score_percentage,

        saver_score_percentage =
          EXCLUDED.saver_score_percentage,

        investor_score_percentage =
          EXCLUDED.investor_score_percentage,

        borrower_score_percentage =
          EXCLUDED.borrower_score_percentage,

        rule_id =
          EXCLUDED.rule_id,

        calculated_at = now(),

        updated_at = now()

      RETURNING *
      INTO v_result;


    ELSE

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
        updated_at
      )
      VALUES (
        p_user_id,
        lower(p_country_code),
        lower(p_currency_code),

        p_fiscal_year,
        p_period,
        'period',

        v_result_behavior,

        v_deposit,
        v_withdrawal,
        v_spending,
        v_saving,
        v_investment,
        v_borrowing,
        v_repayment,

        v_withdrawal_pct,
        v_spending_pct,
        v_saving_pct,
        v_investment_pct,
        v_borrowing_pct,
        v_repayment_pct,

        v_shop_score,
        v_save_score,
        v_invest_score,
        v_borrow_score,

        v_rule_id,

        now(),
        now()
      )
      ON CONFLICT (
        user_id,
        currency_code,
        fiscal_year,
        period
      )
      WHERE
        scope = 'period'
        AND currency_code IS NOT NULL

      DO UPDATE SET

        behavior =
          EXCLUDED.behavior,

        deposit_amount_usd =
          EXCLUDED.deposit_amount_usd,

        withdrawal_amount_usd =
          EXCLUDED.withdrawal_amount_usd,

        spending_amount_usd =
          EXCLUDED.spending_amount_usd,

        saving_amount_usd =
          EXCLUDED.saving_amount_usd,

        investment_amount_usd =
          EXCLUDED.investment_amount_usd,

        borrowing_amount_usd =
          EXCLUDED.borrowing_amount_usd,

        repayment_amount_usd =
          EXCLUDED.repayment_amount_usd,

        withdrawal_percentage =
          EXCLUDED.withdrawal_percentage,

        spending_percentage =
          EXCLUDED.spending_percentage,

        saving_percentage =
          EXCLUDED.saving_percentage,

        investment_percentage =
          EXCLUDED.investment_percentage,

        borrowing_percentage =
          EXCLUDED.borrowing_percentage,

        repayment_percentage =
          EXCLUDED.repayment_percentage,

        shopper_score_percentage =
          EXCLUDED.shopper_score_percentage,

        saver_score_percentage =
          EXCLUDED.saver_score_percentage,

        investor_score_percentage =
          EXCLUDED.investor_score_percentage,

        borrower_score_percentage =
          EXCLUDED.borrower_score_percentage,

        rule_id =
          EXCLUDED.rule_id,

        calculated_at = now(),

        updated_at = now()

      RETURNING *
      INTO v_result;

    END IF;


  -- ==========================================================
  -- FISCAL YEAR
  -- ==========================================================

  ELSE

    IF p_currency_code IS NULL THEN

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
        updated_at
      )
      VALUES (
        p_user_id,
        lower(p_country_code),
        NULL,

        p_fiscal_year,
        NULL,
        'fiscal_year',

        v_result_behavior,

        v_deposit,
        v_withdrawal,
        v_spending,
        v_saving,
        v_investment,
        v_borrowing,
        v_repayment,

        v_withdrawal_pct,
        v_spending_pct,
        v_saving_pct,
        v_investment_pct,
        v_borrowing_pct,
        v_repayment_pct,

        v_shop_score,
        v_save_score,
        v_invest_score,
        v_borrow_score,

        v_rule_id,

        now(),
        now()
      )
      ON CONFLICT (
        user_id,
        fiscal_year
      )
      WHERE
        scope = 'fiscal_year'
        AND currency_code IS NULL

      DO UPDATE SET

        behavior =
          EXCLUDED.behavior,

        deposit_amount_usd =
          EXCLUDED.deposit_amount_usd,

        withdrawal_amount_usd =
          EXCLUDED.withdrawal_amount_usd,

        spending_amount_usd =
          EXCLUDED.spending_amount_usd,

        saving_amount_usd =
          EXCLUDED.saving_amount_usd,

        investment_amount_usd =
          EXCLUDED.investment_amount_usd,

        borrowing_amount_usd =
          EXCLUDED.borrowing_amount_usd,

        repayment_amount_usd =
          EXCLUDED.repayment_amount_usd,

        withdrawal_percentage =
          EXCLUDED.withdrawal_percentage,

        spending_percentage =
          EXCLUDED.spending_percentage,

        saving_percentage =
          EXCLUDED.saving_percentage,

        investment_percentage =
          EXCLUDED.investment_percentage,

        borrowing_percentage =
          EXCLUDED.borrowing_percentage,

        repayment_percentage =
          EXCLUDED.repayment_percentage,

        shopper_score_percentage =
          EXCLUDED.shopper_score_percentage,

        saver_score_percentage =
          EXCLUDED.saver_score_percentage,

        investor_score_percentage =
          EXCLUDED.investor_score_percentage,

        borrower_score_percentage =
          EXCLUDED.borrower_score_percentage,

        rule_id =
          EXCLUDED.rule_id,

        calculated_at = now(),

        updated_at = now()

      RETURNING *
      INTO v_result;


    ELSE

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
        updated_at
      )
      VALUES (
        p_user_id,
        lower(p_country_code),
        lower(p_currency_code),

        p_fiscal_year,
        NULL,
        'fiscal_year',

        v_result_behavior,

        v_deposit,
        v_withdrawal,
        v_spending,
        v_saving,
        v_investment,
        v_borrowing,
        v_repayment,

        v_withdrawal_pct,
        v_spending_pct,
        v_saving_pct,
        v_investment_pct,
        v_borrowing_pct,
        v_repayment_pct,

        v_shop_score,
        v_save_score,
        v_invest_score,
        v_borrow_score,

        v_rule_id,

        now(),
        now()
      )
      ON CONFLICT (
        user_id,
        currency_code,
        fiscal_year
      )
      WHERE
        scope = 'fiscal_year'
        AND currency_code IS NOT NULL

      DO UPDATE SET

        behavior =
          EXCLUDED.behavior,

        deposit_amount_usd =
          EXCLUDED.deposit_amount_usd,

        withdrawal_amount_usd =
          EXCLUDED.withdrawal_amount_usd,

        spending_amount_usd =
          EXCLUDED.spending_amount_usd,

        saving_amount_usd =
          EXCLUDED.saving_amount_usd,

        investment_amount_usd =
          EXCLUDED.investment_amount_usd,

        borrowing_amount_usd =
          EXCLUDED.borrowing_amount_usd,

        repayment_amount_usd =
          EXCLUDED.repayment_amount_usd,

        withdrawal_percentage =
          EXCLUDED.withdrawal_percentage,

        spending_percentage =
          EXCLUDED.spending_percentage,

        saving_percentage =
          EXCLUDED.saving_percentage,

        investment_percentage =
          EXCLUDED.investment_percentage,

        borrowing_percentage =
          EXCLUDED.borrowing_percentage,

        repayment_percentage =
          EXCLUDED.repayment_percentage,

        shopper_score_percentage =
          EXCLUDED.shopper_score_percentage,

        saver_score_percentage =
          EXCLUDED.saver_score_percentage,

        investor_score_percentage =
          EXCLUDED.investor_score_percentage,

        borrower_score_percentage =
          EXCLUDED.borrower_score_percentage,

        rule_id =
          EXCLUDED.rule_id,

        calculated_at = now(),

        updated_at = now()

      RETURNING *
      INTO v_result;

    END IF;

  END IF;


  RETURN v_result;

END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_financial_behavior(
  p_user_id text,
  p_country_code text,
  p_currency_code text,
  p_fiscal_year integer,
  p_period integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pot public.financial_pot;

  v_period_currency public.financial_behavior;
  v_period_all public.financial_behavior;

  v_year_currency public.financial_behavior;
  v_year_all public.financial_behavior;
BEGIN

  -- ==========================================================
  -- UPDATE CURRENT POT ALLOCATION
  -- ==========================================================

  SELECT *
  INTO v_pot
  FROM public.calculate_financial_pot_percentages(
    p_user_id,
    lower(p_currency_code),
    p_fiscal_year,
    p_period
  );


  -- ==========================================================
  -- CURRENT PERIOD / CURRENT CURRENCY
  -- ==========================================================

  SELECT *
  INTO v_period_currency
  FROM public.calculate_financial_behavior_snapshot(
    p_user_id,
    p_country_code,
    lower(p_currency_code),
    p_fiscal_year,
    p_period,
    'period'
  );


  -- ==========================================================
  -- CURRENT PERIOD / ALL CURRENCIES
  -- ==========================================================

  SELECT *
  INTO v_period_all
  FROM public.calculate_financial_behavior_snapshot(
    p_user_id,
    p_country_code,
    NULL,
    p_fiscal_year,
    p_period,
    'period'
  );


  -- ==========================================================
  -- FISCAL YEAR / CURRENT CURRENCY
  -- ==========================================================

  SELECT *
  INTO v_year_currency
  FROM public.calculate_financial_behavior_snapshot(
    p_user_id,
    p_country_code,
    lower(p_currency_code),
    p_fiscal_year,
    NULL,
    'fiscal_year'
  );


  -- ==========================================================
  -- FISCAL YEAR / ALL CURRENCIES
  -- ==========================================================

  SELECT *
  INTO v_year_all
  FROM public.calculate_financial_behavior_snapshot(
    p_user_id,
    p_country_code,
    NULL,
    p_fiscal_year,
    NULL,
    'fiscal_year'
  );


  RETURN jsonb_build_object(

    'pot',
      to_jsonb(v_pot),

    'period',
      jsonb_build_object(

        'currency',
          to_jsonb(v_period_currency),

        'all_currencies',
          to_jsonb(v_period_all)
      ),

    'fiscal_year',
      jsonb_build_object(

        'currency',
          to_jsonb(v_year_currency),

        'all_currencies',
          to_jsonb(v_year_all)
      )
  );

END;
$$;

