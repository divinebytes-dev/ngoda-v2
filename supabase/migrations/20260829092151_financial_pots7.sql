CREATE OR REPLACE FUNCTION public.record_financial_pot_activity(
  p_reference text,
  p_user_id text,
  p_country_code text,
  p_currency_code text,
  p_fiscal_year integer,
  p_period integer,
  p_transaction_type text,
  p_pot_type financial_pot_type,
  p_amount numeric,
  p_amount_usd numeric
)
RETURNS public.financial_pot
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id uuid;

  v_opening_savings numeric(20, 6) := 0;
  v_opening_savings_usd numeric(20, 2) := 0;

  v_result public.financial_pot;
BEGIN

  -- ==========================================================
  -- VALIDATION
  -- ==========================================================

  IF p_reference IS NULL
     OR trim(p_reference) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_POT_REFERENCE_REQUIRED';
  END IF;


  IF p_user_id IS NULL
     OR trim(p_user_id) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_POT_USER_REQUIRED';
  END IF;


  IF p_currency_code IS NULL
     OR trim(p_currency_code) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_POT_CURRENCY_REQUIRED';
  END IF;


  IF p_period < 1
     OR p_period > 12 THEN
    RAISE EXCEPTION 'FINANCIAL_POT_INVALID_PERIOD';
  END IF;


  IF p_amount IS NULL
     OR p_amount < 0 THEN
    RAISE EXCEPTION 'FINANCIAL_POT_INVALID_AMOUNT';
  END IF;


  IF p_amount_usd IS NULL
     OR p_amount_usd < 0 THEN
    RAISE EXCEPTION 'FINANCIAL_POT_INVALID_USD_AMOUNT';
  END IF;


  -- ==========================================================
  -- IDEMPOTENCY
  --
  -- If this exact transaction/user/pot contribution was already
  -- processed, do nothing.
  -- ==========================================================

  INSERT INTO public.financial_pot_event (
    reference,
    user_id,
    country_code,
    currency_code,
    fiscal_year,
    period,
    pot_type,
    transaction_type,
    amount,
    amount_usd
  )
  VALUES (
    p_reference,
    p_user_id,
    lower(p_country_code),
    lower(p_currency_code),
    p_fiscal_year,
    p_period,
    p_pot_type,
    p_transaction_type,
    p_amount,
    p_amount_usd
  )
  ON CONFLICT (
    reference,
    user_id,
    pot_type
  )
  DO NOTHING
  RETURNING id
  INTO v_event_id;


  /*
   * Already processed.
   */
  IF v_event_id IS NULL THEN

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
  -- DETERMINE OPENING SAVINGS
  --
  -- Take the closing savings of the immediately preceding
  -- available financial-pot period for this user/currency.
  -- ==========================================================

  SELECT
    closing_savings,
    closing_savings_usd
  INTO
    v_opening_savings,
    v_opening_savings_usd
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
    COALESCE(
      v_opening_savings,
      0
    );

  v_opening_savings_usd :=
    COALESCE(
      v_opening_savings_usd,
      0
    );


  -- ==========================================================
  -- CREATE PERIOD IF IT DOES NOT EXIST
  -- ==========================================================

  INSERT INTO public.financial_pot (
    user_id,
    country_code,
    currency_code,
    fiscal_year,
    period,

    opening_savings,
    opening_savings_usd,

    deposit_amount,
    withdrawal_amount,
    spending_amount,
    investment_amount,

    deposit_amount_usd,
    withdrawal_amount_usd,
    spending_amount_usd,
    investment_amount_usd,

    saving_amount,
    saving_amount_usd,

    closing_savings,
    closing_savings_usd
  )
  VALUES (
    p_user_id,
    lower(p_country_code),
    lower(p_currency_code),
    p_fiscal_year,
    p_period,

    v_opening_savings,
    v_opening_savings_usd,

    0,
    0,
    0,
    0,

    0,
    0,
    0,
    0,

    0,
    0,

    v_opening_savings,
    v_opening_savings_usd
  )
  ON CONFLICT (
    user_id,
    currency_code,
    fiscal_year,
    period
  )
  DO NOTHING;


  -- ==========================================================
  -- APPLY TRANSACTION TO POT
  -- ==========================================================

  UPDATE public.financial_pot
  SET

    deposit_amount =
      deposit_amount
      +
      CASE
        WHEN p_pot_type = 'deposit'
          THEN p_amount
        ELSE 0
      END,

    withdrawal_amount =
      withdrawal_amount
      +
      CASE
        WHEN p_pot_type = 'withdrawal'
          THEN p_amount
        ELSE 0
      END,

    spending_amount =
      spending_amount
      +
      CASE
        WHEN p_pot_type = 'spending'
          THEN p_amount
        ELSE 0
      END,

    investment_amount =
      investment_amount
      +
      CASE
        WHEN p_pot_type = 'investment'
          THEN p_amount
        ELSE 0
      END,


    -- ========================================================
    -- USD
    -- ========================================================

    deposit_amount_usd =
      deposit_amount_usd
      +
      CASE
        WHEN p_pot_type = 'deposit'
          THEN p_amount_usd
        ELSE 0
      END,

    withdrawal_amount_usd =
      withdrawal_amount_usd
      +
      CASE
        WHEN p_pot_type = 'withdrawal'
          THEN p_amount_usd
        ELSE 0
      END,

    spending_amount_usd =
      spending_amount_usd
      +
      CASE
        WHEN p_pot_type = 'spending'
          THEN p_amount_usd
        ELSE 0
      END,

    investment_amount_usd =
      investment_amount_usd
      +
      CASE
        WHEN p_pot_type = 'investment'
          THEN p_amount_usd
        ELSE 0
      END,

    updated_at = now()

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  -- ==========================================================
  -- RECALCULATE SAVINGS
  --
  -- saving_amount:
  -- Amount retained from deposits made THIS PERIOD.
  --
  -- closing_savings:
  -- Accumulated savings carried between periods.
  -- ==========================================================

  UPDATE public.financial_pot
  SET

    saving_amount =
      GREATEST(
        deposit_amount
        - withdrawal_amount
        - spending_amount
        - investment_amount,
        0
      ),

    saving_amount_usd =
      GREATEST(
        deposit_amount_usd
        - withdrawal_amount_usd
        - spending_amount_usd
        - investment_amount_usd,
        0
      ),

    closing_savings =
      GREATEST(
        opening_savings
        + deposit_amount
        - withdrawal_amount
        - spending_amount
        - investment_amount,
        0
      ),

    closing_savings_usd =
      GREATEST(
        opening_savings_usd
        + deposit_amount_usd
        - withdrawal_amount_usd
        - spending_amount_usd
        - investment_amount_usd,
        0
      ),

    updated_at = now()

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  -- ==========================================================
  -- CALCULATE PERCENTAGES
  -- ==========================================================

  UPDATE public.financial_pot
  SET

    withdrawal_percentage =
      CASE
        WHEN deposit_amount_usd > 0
        THEN ROUND(
          (
            withdrawal_amount_usd
            / deposit_amount_usd
          ) * 100,
          4
        )
        ELSE 0
      END,

    spending_percentage =
      CASE
        WHEN deposit_amount_usd > 0
        THEN ROUND(
          (
            spending_amount_usd
            / deposit_amount_usd
          ) * 100,
          4
        )
        ELSE 0
      END,

    saving_percentage =
      CASE
        WHEN deposit_amount_usd > 0
        THEN ROUND(
          (
            saving_amount_usd
            / deposit_amount_usd
          ) * 100,
          4
        )
        ELSE 0
      END,

    investment_percentage =
      CASE
        WHEN deposit_amount_usd > 0
        THEN ROUND(
          (
            investment_amount_usd
            / deposit_amount_usd
          ) * 100,
          4
        )
        ELSE 0
      END,

    updated_at = now()

  WHERE user_id = p_user_id
    AND currency_code = lower(p_currency_code)
    AND fiscal_year = p_fiscal_year
    AND period = p_period;


  -- ==========================================================
  -- RETURN UPDATED POT
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
$$;



REVOKE ALL
ON FUNCTION public.record_financial_pot_activity(
  text,
  text,
  text,
  text,
  integer,
  integer,
  text,
  financial_pot_type,
  numeric,
  numeric
)
FROM PUBLIC;


REVOKE ALL
ON FUNCTION public.record_financial_pot_activity(
  text,
  text,
  text,
  text,
  integer,
  integer,
  text,
  financial_pot_type,
  numeric,
  numeric
)
FROM authenticated;


GRANT EXECUTE
ON FUNCTION public.record_financial_pot_activity(
  text,
  text,
  text,
  text,
  integer,
  integer,
  text,
  financial_pot_type,
  numeric,
  numeric
)
TO service_role;