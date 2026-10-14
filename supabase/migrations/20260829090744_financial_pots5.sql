-- ============================================================
-- FINANCIAL POTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_pot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id text NOT NULL,

  country_code text NOT NULL,
  currency_code text NOT NULL,

  fiscal_year integer NOT NULL,
  period integer NOT NULL,

  -- ========================================================
  -- NATIVE CURRENCY
  -- ========================================================

  deposit_amount numeric(20, 6) NOT NULL DEFAULT 0,
  withdrawal_amount numeric(20, 6) NOT NULL DEFAULT 0,
  spending_amount numeric(20, 6) NOT NULL DEFAULT 0,
  saving_amount numeric(20, 6) NOT NULL DEFAULT 0,
  investment_amount numeric(20, 6) NOT NULL DEFAULT 0,

  -- Savings-pot continuity
  opening_savings numeric(20, 6) NOT NULL DEFAULT 0,
  closing_savings numeric(20, 6) NOT NULL DEFAULT 0,

  -- ========================================================
  -- USD EQUIVALENT
  -- ========================================================

  deposit_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  withdrawal_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  spending_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  saving_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  investment_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,

  opening_savings_usd numeric(20, 2) NOT NULL DEFAULT 0,
  closing_savings_usd numeric(20, 2) NOT NULL DEFAULT 0,

  -- ========================================================
  -- ALLOCATION PERCENTAGES
  -- ========================================================

  withdrawal_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  spending_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  saving_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  investment_percentage numeric(9, 4) NOT NULL DEFAULT 0,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT financial_pot_period_check
    CHECK (period BETWEEN 1 AND 12),

  CONSTRAINT financial_pot_amount_check
    CHECK (
      deposit_amount >= 0
      AND withdrawal_amount >= 0
      AND spending_amount >= 0
      AND investment_amount >= 0
    ),

  CONSTRAINT financial_pot_usd_amount_check
    CHECK (
      deposit_amount_usd >= 0
      AND withdrawal_amount_usd >= 0
      AND spending_amount_usd >= 0
      AND investment_amount_usd >= 0
    ),

  CONSTRAINT financial_pot_unique
    UNIQUE (
      user_id,
      currency_code,
      fiscal_year,
      period
    )
);


-- ============================================================
-- CALCULATED FINANCIAL BEHAVIOUR
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_behavior (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id text NOT NULL,

  country_code text NOT NULL,

  /*
   * NULL means:
   * all supported currencies combined using USD equivalents.
   */
  currency_code text,

  fiscal_year integer NOT NULL,

  /*
   * NULL for fiscal-year behaviour.
   * Required for period behaviour.
   */
  period integer,

  scope financial_behavior_scope NOT NULL,

  behavior financial_behavior_type NOT NULL,

  deposit_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,

  withdrawal_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  spending_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  saving_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,
  investment_amount_usd numeric(20, 2) NOT NULL DEFAULT 0,

  withdrawal_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  spending_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  saving_percentage numeric(9, 4) NOT NULL DEFAULT 0,
  investment_percentage numeric(9, 4) NOT NULL DEFAULT 0,

  rule_id uuid
    REFERENCES public.financial_behavior_rule(id),

  calculated_at timestamptz NOT NULL DEFAULT now(),

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT financial_behavior_period_check
    CHECK (
      (
        scope = 'period'
        AND period BETWEEN 1 AND 12
      )
      OR
      (
        scope = 'fiscal_year'
        AND period IS NULL
      )
    )
);


CREATE UNIQUE INDEX IF NOT EXISTS
financial_behavior_period_currency_unique
ON public.financial_behavior (
  user_id,
  currency_code,
  fiscal_year,
  period
)
WHERE
  scope = 'period'
  AND currency_code IS NOT NULL;


CREATE UNIQUE INDEX IF NOT EXISTS
financial_behavior_period_all_currency_unique
ON public.financial_behavior (
  user_id,
  fiscal_year,
  period
)
WHERE
  scope = 'period'
  AND currency_code IS NULL;


CREATE UNIQUE INDEX IF NOT EXISTS
financial_behavior_year_currency_unique
ON public.financial_behavior (
  user_id,
  currency_code,
  fiscal_year
)
WHERE
  scope = 'fiscal_year'
  AND currency_code IS NOT NULL;


CREATE UNIQUE INDEX IF NOT EXISTS
financial_behavior_year_all_currency_unique
ON public.financial_behavior (
  user_id,
  fiscal_year
)
WHERE
  scope = 'fiscal_year'
  AND currency_code IS NULL;