CREATE OR REPLACE FUNCTION public.record_financial_activity(p_reference text, p_user_id text, p_country_code text, p_currency_code text, p_fiscal_year integer, p_period integer, p_transaction_type text, p_activity_type financial_activity_type, p_amount numeric DEFAULT 0, p_amount_usd numeric DEFAULT 0, p_cash_amount numeric DEFAULT 0, p_cash_amount_usd numeric DEFAULT 0, p_gold_quantity numeric DEFAULT 0, p_investment_cost_usd numeric DEFAULT 0, p_principal_amount numeric DEFAULT 0, p_principal_amount_usd numeric DEFAULT 0, p_interest_amount numeric DEFAULT 0, p_interest_amount_usd numeric DEFAULT 0)
 RETURNS financial_pot
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event_id uuid;

  v_opening_savings numeric(20, 6) := 0;
  v_opening_savings_usd numeric(20, 2) := 0;

  v_opening_gold_quantity numeric(20, 6) := 0;
  v_opening_investment_usd numeric(20, 2) := 0;

  v_opening_loan_balance numeric(20, 6) := 0;
  v_opening_loan_balance_usd numeric(20, 2) := 0;

  v_result public.financial_pot;
BEGIN

  -- ==========================================================
  -- VALIDATION
  -- ==========================================================

  IF p_reference IS NULL
     OR trim(p_reference) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_REFERENCE_REQUIRED';
  END IF;


  IF p_user_id IS NULL
     OR trim(p_user_id) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_USER_REQUIRED';
  END IF;


  IF p_country_code IS NULL
     OR trim(p_country_code) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_COUNTRY_REQUIRED';
  END IF;


  IF p_currency_code IS NULL
     OR trim(p_currency_code) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_CURRENCY_REQUIRED';
  END IF;


  IF p_period < 1
     OR p_period > 12 THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_INVALID_PERIOD';
  END IF;


  IF COALESCE(p_amount, 0) < 0
     OR COALESCE(p_amount_usd, 0) < 0
     OR COALESCE(p_cash_amount, 0) < 0
     OR COALESCE(p_cash_amount_usd, 0) < 0
     OR COALESCE(p_gold_quantity, 0) < 0
     OR COALESCE(p_investment_cost_usd, 0) < 0
     OR COALESCE(p_principal_amount, 0) < 0
     OR COALESCE(p_principal_amount_usd, 0) < 0
     OR COALESCE(p_interest_amount, 0) < 0
     OR COALESCE(p_interest_amount_usd, 0) < 0
  THEN
    RAISE EXCEPTION 'FINANCIAL_ACTIVITY_NEGATIVE_VALUE';
  END IF;


  -- ==========================================================
  -- RECORD EVENT
  --
  -- reference + user + activity_type
  -- makes this idempotent.
  -- ==========================================================

  INSERT INTO public.financial_pot_event (
    reference,
    user_id,
    country_code,
    currency_code,
    fiscal_year,
    period,
    transaction_type,
    activity_type,

    amount,
    amount_usd,

    cash_amount,
    cash_amount_usd,

    gold_quantity,
    investment_cost_usd,

    principal_amount,
    principal_amount_usd,

    interest_amount,
    interest_amount_usd
  )
  VALUES (
    p_reference,
    p_user_id,
    lower(p_country_code),
    lower(p_currency_code),
    p_fiscal_year,
    p_period,
    lower(p_transaction_type),
    p_activity_type,

    COALESCE(p_amount, 0),
    COALESCE(p_amount_usd, 0),

    COALESCE(p_cash_amount, 0),
    COALESCE(p_cash_amount_usd, 0),

    COALESCE(p_gold_quantity, 0),
    COALESCE(p_investment_cost_usd, 0),

    COALESCE(p_principal_amount, 0),
    COALESCE(p_principal_amount_usd, 0),

    COALESCE(p_interest_amount, 0),
    COALESCE(p_interest_amount_usd, 0)
  )
  ON CONFLICT (
    reference,
    user_id,
    activity_type
  )
  DO NOTHING
  RETURNING id
  INTO v_event_id;


  -- ==========================================================
  -- ALREADY PROCESSED
  --
  -- Do not update financial activity again.
  --
  -- We still recalculate derived intelligence so retries can
  -- restore percentage/behaviour snapshots if needed.
  -- ==========================================================

  IF v_event_id IS NULL THEN

    PERFORM public.calculate_financial_behavior(
      p_user_id,
      lower(p_country_code),
      lower(p_currency_code),
      p_fiscal_year,
      p_period
    );

  PERFORM *
  FROM public.evaluate_financial_badges(
    p_user_id,
    lower(p_country_code),
    p_fiscal_year,
    p_period
  );
  
    SELECT *
    INTO v_result
    FROM public.financial_pot
    WHERE user_id = p_user_id
      AND currency_code = lower(p_currency_code)
      AND fiscal_year = p_fiscal_year
      AND period = p_period;


    RETURN v_result;

  END IF;


  -- ==========================================================
  -- GET PREVIOUS POSITION
  --
  -- Carries forward:
  --
  -- Savings
  -- Gold quantity
  -- Investment cost position
  -- Loan position
  -- ==========================================================

  SELECT
    closing_savings,
    closing_savings_usd,

    closing_gold_quantity,
    closing_investment_usd,

    closing_loan_balance,
    closing_loan_balance_usd

  INTO
    v_opening_savings,
    v_opening_savings_usd,

    v_opening_gold_quantity,
    v_opening_investment_usd,

    v_opening_loan_balance,
    v_opening_loan_balance_usd

  FROM public.financial_pot

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)

    AND (
      fiscal_year < p_fiscal_year

      OR (
        fiscal_year = p_fiscal_year
        AND period < p_period
      )
    )

  ORDER BY
    fiscal_year DESC,
    period DESC

  LIMIT 1;


  v_opening_savings :=
    COALESCE(v_opening_savings, 0);

  v_opening_savings_usd :=
    COALESCE(v_opening_savings_usd, 0);

  v_opening_gold_quantity :=
    COALESCE(v_opening_gold_quantity, 0);

  v_opening_investment_usd :=
    COALESCE(v_opening_investment_usd, 0);

  v_opening_loan_balance :=
    COALESCE(v_opening_loan_balance, 0);

  v_opening_loan_balance_usd :=
    COALESCE(v_opening_loan_balance_usd, 0);


  -- ==========================================================
  -- CREATE CURRENT PERIOD
  -- ==========================================================

  INSERT INTO public.financial_pot (
    user_id,
    country_code,
    currency_code,

    fiscal_year,
    period,

    opening_savings,
    opening_savings_usd,

    closing_savings,
    closing_savings_usd,

    opening_gold_quantity,
    closing_gold_quantity,

    opening_investment_usd,
    closing_investment_usd,

    opening_loan_balance,
    opening_loan_balance_usd,

    closing_loan_balance,
    closing_loan_balance_usd
  )
  VALUES (
    p_user_id,
    lower(p_country_code),
    lower(p_currency_code),

    p_fiscal_year,
    p_period,

    v_opening_savings,
    v_opening_savings_usd,

    v_opening_savings,
    v_opening_savings_usd,

    v_opening_gold_quantity,
    v_opening_gold_quantity,

    v_opening_investment_usd,
    v_opening_investment_usd,

    v_opening_loan_balance,
    v_opening_loan_balance_usd,

    v_opening_loan_balance,
    v_opening_loan_balance_usd
  )
  ON CONFLICT (
    user_id,
    currency_code,
    fiscal_year,
    period
  )
  DO NOTHING;


  -- ==========================================================
  -- APPLY FINANCIAL ACTIVITY
  -- ==========================================================

  CASE p_activity_type


    -- ========================================================
    -- DEPOSIT
    -- ========================================================

    WHEN 'deposit' THEN

      UPDATE public.financial_pot
      SET
        deposit_amount =
          deposit_amount + p_amount,

        deposit_amount_usd =
          deposit_amount_usd + p_amount_usd,

        savings_inflow =
          savings_inflow + p_cash_amount,

        savings_inflow_usd =
          savings_inflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- WITHDRAWAL
    -- ========================================================

    WHEN 'withdrawal' THEN

      UPDATE public.financial_pot
      SET
        withdrawal_amount =
          withdrawal_amount + p_amount,

        withdrawal_amount_usd =
          withdrawal_amount_usd + p_amount_usd,

        savings_outflow =
          savings_outflow + p_cash_amount,

        savings_outflow_usd =
          savings_outflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- SPENDING
    -- ========================================================

    WHEN 'spending' THEN

      UPDATE public.financial_pot
      SET
        spending_amount =
          spending_amount + p_amount,

        spending_amount_usd =
          spending_amount_usd + p_amount_usd,

        savings_outflow =
          savings_outflow + p_cash_amount,

        savings_outflow_usd =
          savings_outflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- GOLD BUY
    -- ========================================================

    WHEN 'investment_buy' THEN

      UPDATE public.financial_pot
      SET
        investment_purchase_amount =
          investment_purchase_amount + p_amount,

        investment_purchase_amount_usd =
          investment_purchase_amount_usd + p_amount_usd,

        gold_purchased =
          gold_purchased + p_gold_quantity,

        investment_inflow_usd =
          investment_inflow_usd + p_investment_cost_usd,

        savings_outflow =
          savings_outflow + p_cash_amount,

        savings_outflow_usd =
          savings_outflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- GOLD SELL
    -- ========================================================

    WHEN 'investment_sell' THEN

      UPDATE public.financial_pot
      SET
        investment_sale_amount =
          investment_sale_amount + p_amount,

        investment_sale_amount_usd =
          investment_sale_amount_usd + p_amount_usd,

        gold_sold =
          gold_sold + p_gold_quantity,

        investment_outflow_usd =
          investment_outflow_usd + p_investment_cost_usd,

        deposit_amount =
          deposit_amount + p_cash_amount,

        deposit_amount_usd =
          deposit_amount_usd + p_cash_amount_usd,

        savings_inflow =
          savings_inflow + p_cash_amount,

        savings_inflow_usd =
          savings_inflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- GOLD TRANSFER IN
    -- ========================================================

    WHEN 'investment_transfer_in' THEN

      UPDATE public.financial_pot
      SET
        gold_transferred_in =
          gold_transferred_in + p_gold_quantity,

        investment_inflow_usd =
          investment_inflow_usd + p_investment_cost_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- GOLD TRANSFER OUT
    -- ========================================================

    WHEN 'investment_transfer_out' THEN

      UPDATE public.financial_pot
      SET
        gold_transferred_out =
          gold_transferred_out + p_gold_quantity,

        investment_outflow_usd =
          investment_outflow_usd + p_investment_cost_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- LOAN DISBURSEMENT
    -- ========================================================

    WHEN 'loan_disbursement' THEN

      UPDATE public.financial_pot
      SET
        loan_disbursed_amount =
          loan_disbursed_amount + p_amount,

        loan_disbursed_amount_usd =
          loan_disbursed_amount_usd + p_amount_usd,

        deposit_amount =
          deposit_amount + p_cash_amount,

        deposit_amount_usd =
          deposit_amount_usd + p_cash_amount_usd,

        savings_inflow =
          savings_inflow + p_cash_amount,

        savings_inflow_usd =
          savings_inflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- LOAN REPAYMENT
    -- ========================================================

    WHEN 'loan_repayment' THEN

      UPDATE public.financial_pot
      SET
        loan_repayment_amount =
          loan_repayment_amount + p_amount,

        loan_repayment_amount_usd =
          loan_repayment_amount_usd + p_amount_usd,

        loan_principal_repaid =
          loan_principal_repaid + p_principal_amount,

        loan_principal_repaid_usd =
          loan_principal_repaid_usd
          + p_principal_amount_usd,

        loan_interest_repaid =
          loan_interest_repaid + p_interest_amount,

        loan_interest_repaid_usd =
          loan_interest_repaid_usd
          + p_interest_amount_usd,

        savings_outflow =
          savings_outflow + p_cash_amount,

        savings_outflow_usd =
          savings_outflow_usd + p_cash_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;


    -- ========================================================
    -- LOAN INTEREST ACCRUAL
    -- ========================================================

    WHEN 'loan_interest_accrual' THEN

      UPDATE public.financial_pot
      SET
        loan_interest_accrued =
          loan_interest_accrued + p_interest_amount,

        loan_interest_accrued_usd =
          loan_interest_accrued_usd
          + p_interest_amount_usd,

        updated_at = now()

      WHERE user_id = p_user_id
        AND currency_code = lower(p_currency_code)
        AND fiscal_year = p_fiscal_year
        AND period = p_period;

  END CASE;


  -- ==========================================================
  -- RECALCULATE POSITIONS
  -- ==========================================================

  UPDATE public.financial_pot
  SET

    -- --------------------------------------------------------
    -- SAVINGS POSITION
    -- --------------------------------------------------------

    closing_savings =
      GREATEST(
        opening_savings
        + savings_inflow
        - savings_outflow,
        0
      ),

    closing_savings_usd =
      GREATEST(
        opening_savings_usd
        + savings_inflow_usd
        - savings_outflow_usd,
        0
      ),


    -- --------------------------------------------------------
    -- SAVING CREATED THIS PERIOD
    -- --------------------------------------------------------

    saving_amount =
      GREATEST(
        savings_inflow
        - savings_outflow,
        0
      ),

    saving_amount_usd =
      GREATEST(
        savings_inflow_usd
        - savings_outflow_usd,
        0
      ),


    -- --------------------------------------------------------
    -- GOLD POSITION
    -- --------------------------------------------------------

    closing_gold_quantity =
      GREATEST(
        opening_gold_quantity
        + gold_purchased
        + gold_transferred_in
        - gold_sold
        - gold_transferred_out,
        0
      ),


    -- --------------------------------------------------------
    -- INVESTMENT COST POSITION
    -- --------------------------------------------------------

    closing_investment_usd =
      GREATEST(
        opening_investment_usd
        + investment_inflow_usd
        - investment_outflow_usd,
        0
      ),


    -- --------------------------------------------------------
    -- LOAN POSITION
    -- --------------------------------------------------------

    closing_loan_balance =
      GREATEST(
        opening_loan_balance
        + loan_disbursed_amount
        + loan_interest_accrued
        - loan_principal_repaid
        - loan_interest_repaid,
        0
      ),

    closing_loan_balance_usd =
      GREATEST(
        opening_loan_balance_usd
        + loan_disbursed_amount_usd
        + loan_interest_accrued_usd
        - loan_principal_repaid_usd
        - loan_interest_repaid_usd,
        0
      ),

    updated_at = now()

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  -- ==========================================================
  -- CALCULATE FINANCIAL INTELLIGENCE
  --
  -- Internally performs:
  --
  -- 1. Pot allocation percentages
  -- 2. Period behaviour / currency
  -- 3. Period behaviour / all currencies
  -- 4. Fiscal-year behaviour / currency
  -- 5. Fiscal-year behaviour / all currencies
  -- ==========================================================

  PERFORM public.calculate_financial_behavior(
    p_user_id,
    lower(p_country_code),
    lower(p_currency_code),
    p_fiscal_year,
    p_period
  );

-- ==========================================================
-- EVALUATE FINANCIAL BADGES
-- ==========================================================

    PERFORM *
    FROM public.evaluate_financial_badges(
    p_user_id,
    lower(p_country_code),
    p_fiscal_year,
    p_period
    );

  -- ==========================================================
  -- RETURN FINAL UPDATED POT
  --
  -- Read after behaviour calculation because that process
  -- also updates percentage fields on financial_pot.
  -- ==========================================================

  SELECT *
  INTO v_result
  FROM public.financial_pot
  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  RETURN v_result;

END;
$function$
