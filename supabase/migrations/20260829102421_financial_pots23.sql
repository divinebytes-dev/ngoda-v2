CREATE OR REPLACE FUNCTION public.evaluate_financial_badges(
  p_user_id text,
  p_country_code text,
  p_fiscal_year integer,
  p_period integer
)
RETURNS TABLE (
  badge_id uuid,
  badge_code text,
  badge_name text,
  metric financial_badge_metric,
  achieved_value_usd numeric,
  newly_awarded boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_spending_usd numeric(20, 2) := 0;
  v_saving_usd numeric(20, 2) := 0;
  v_investment_usd numeric(20, 2) := 0;
  v_borrowing_usd numeric(20, 2) := 0;

  v_badge record;
  v_metric_value numeric(20, 2) := 0;

  v_inserted_id uuid;
BEGIN

  -- ==========================================================
  -- VALIDATION
  -- ==========================================================

  IF p_user_id IS NULL
     OR trim(p_user_id) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_BADGE_USER_REQUIRED';
  END IF;


  IF p_country_code IS NULL
     OR trim(p_country_code) = '' THEN
    RAISE EXCEPTION 'FINANCIAL_BADGE_COUNTRY_REQUIRED';
  END IF;


  IF p_period < 1
     OR p_period > 12 THEN
    RAISE EXCEPTION 'FINANCIAL_BADGE_INVALID_PERIOD';
  END IF;


  -- ==========================================================
  -- SHOPPER
  --
  -- Lifetime successful merchant-spending activity.
  --
  -- financial_pot_event is used because every event carries
  -- its frozen USD equivalent at transaction time.
  -- ==========================================================

  SELECT
    COALESCE(
      SUM(amount_usd),
      0
    )
  INTO v_spending_usd
  FROM public.financial_pot_event
  WHERE user_id = p_user_id
    AND country_code = lower(p_country_code)
    AND activity_type = 'spending';


  -- ==========================================================
  -- INVESTOR
  --
  -- Lifetime amount personally invested into gold.
  --
  -- Transfers received are deliberately excluded.
  -- ==========================================================

  SELECT
    COALESCE(
      SUM(amount_usd),
      0
    )
  INTO v_investment_usd
  FROM public.financial_pot_event
  WHERE user_id = p_user_id
    AND country_code = lower(p_country_code)
    AND activity_type = 'investment_buy';


  -- ==========================================================
  -- BORROWER
  --
  -- Lifetime loan principal disbursed.
  -- ==========================================================

  SELECT
    COALESCE(
      SUM(amount_usd),
      0
    )
  INTO v_borrowing_usd
  FROM public.financial_pot_event
  WHERE user_id = p_user_id
    AND country_code = lower(p_country_code)
    AND activity_type = 'loan_disbursement';


  -- ==========================================================
  -- SAVER
  --
  -- Use ALL-CURRENCY period behaviour snapshots.
  --
  -- saving_amount_usd on these rows is qualifying saving
  -- behaviour, not simply movement into the Savings Pot.
  --
  -- Therefore:
  -- - loan disbursement does not automatically create Saver
  -- - gold sale does not automatically create Saver
  --
  -- We sum positive period saving created over the user's
  -- lifetime.
  -- ==========================================================

  SELECT
    COALESCE(
      SUM(saving_amount_usd),
      0
    )
  INTO v_saving_usd
  FROM public.financial_behavior
  WHERE user_id = p_user_id
    AND country_code = lower(p_country_code)
    AND scope = 'period'
    AND currency_code IS NULL;


  -- ==========================================================
  -- EVALUATE EVERY ACTIVE BADGE
  -- ==========================================================

  FOR v_badge IN

    SELECT
      fb.id,
      fb.code,
      fb.name,
      fb.metric,
      fb.threshold_usd

    FROM public.financial_badge fb

    WHERE fb.is_active = true

    ORDER BY
      fb.metric,
      fb.level

  LOOP

    -- --------------------------------------------------------
    -- FIND CURRENT VALUE FOR BADGE METRIC
    -- --------------------------------------------------------

    CASE v_badge.metric

      WHEN 'spending' THEN
        v_metric_value := v_spending_usd;

      WHEN 'saving' THEN
        v_metric_value := v_saving_usd;

      WHEN 'investment' THEN
        v_metric_value := v_investment_usd;

      WHEN 'borrowing' THEN
        v_metric_value := v_borrowing_usd;

      ELSE
        v_metric_value := 0;

    END CASE;


    -- --------------------------------------------------------
    -- THRESHOLD NOT REACHED
    -- --------------------------------------------------------

    IF v_metric_value < v_badge.threshold_usd THEN
      CONTINUE;
    END IF;


    -- --------------------------------------------------------
    -- AWARD BADGE
    --
    -- Unique(user_id, badge_id) guarantees a badge can only
    -- ever be earned once.
    -- --------------------------------------------------------

    v_inserted_id := NULL;


    INSERT INTO public.user_financial_badge (
      user_id,
      badge_id,

      achieved_value_usd,

      fiscal_year,
      period,

      achieved_at
    )
    VALUES (
      p_user_id,
      v_badge.id,

      v_metric_value,

      p_fiscal_year,
      p_period,

      now()
    )
    ON CONFLICT (
      user_id,
      badge_id
    )
    DO NOTHING
    RETURNING id
    INTO v_inserted_id;


    -- --------------------------------------------------------
    -- RETURN BADGE STATUS
    -- --------------------------------------------------------

    badge_id :=
      v_badge.id;

    badge_code :=
      v_badge.code;

    badge_name :=
      v_badge.name;

    metric :=
      v_badge.metric;

    achieved_value_usd :=
      v_metric_value;

    newly_awarded :=
      v_inserted_id IS NOT NULL;

    RETURN NEXT;

  END LOOP;

END;
$function$;


REVOKE ALL
ON FUNCTION public.evaluate_financial_badges(
  text,
  text,
  integer,
  integer
)
FROM PUBLIC;


REVOKE ALL
ON FUNCTION public.evaluate_financial_badges(
  text,
  text,
  integer,
  integer
)
FROM authenticated;


GRANT EXECUTE
ON FUNCTION public.evaluate_financial_badges(
  text,
  text,
  integer,
  integer
)
TO service_role;


