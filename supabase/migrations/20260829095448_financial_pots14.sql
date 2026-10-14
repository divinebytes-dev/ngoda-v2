-- ============================================================
-- FINANCIAL POT EVENT
--
-- Idempotent audit trail of successful financial activities.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_pot_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  reference text NOT NULL,

  user_id text NOT NULL,

  country_code text NOT NULL,

  currency_code text NOT NULL,

  fiscal_year integer NOT NULL,

  period integer NOT NULL,

  transaction_type text NOT NULL,

  activity_type financial_activity_type NOT NULL,


  -- ========================================================
  -- PRIMARY ACTIVITY AMOUNT
  -- ========================================================

  amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- GOLD
  -- ========================================================

  gold_quantity numeric(20, 6)
    NOT NULL DEFAULT 0,

  investment_cost_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- LOAN REPAYMENT COMPONENTS
  -- ========================================================

  principal_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  principal_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  interest_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  interest_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  created_at timestamptz NOT NULL DEFAULT now(),


  CONSTRAINT financial_pot_event_period_check
    CHECK (
      period BETWEEN 1 AND 12
    ),


  CONSTRAINT financial_pot_event_values_check
    CHECK (
      amount >= 0
      AND amount_usd >= 0

      AND gold_quantity >= 0

      AND investment_cost_usd >= 0

      AND principal_amount >= 0
      AND principal_amount_usd >= 0

      AND interest_amount >= 0
      AND interest_amount_usd >= 0
    ),


  /*
   * Same reference may legitimately affect:
   *
   * transfer sender
   * transfer receiver
   *
   * or different financial activities.
   */
  CONSTRAINT financial_pot_event_unique
    UNIQUE (
      reference,
      user_id,
      activity_type
    )
);

CREATE INDEX IF NOT EXISTS
financial_pot_event_user_idx
ON public.financial_pot_event (
  user_id
);


CREATE INDEX IF NOT EXISTS
financial_pot_event_user_period_idx
ON public.financial_pot_event (
  user_id,
  fiscal_year,
  period
);


CREATE INDEX IF NOT EXISTS
financial_pot_event_user_currency_period_idx
ON public.financial_pot_event (
  user_id,
  currency_code,
  fiscal_year,
  period
);

-- ============================================================
-- FINANCIAL BEHAVIOUR
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_behavior (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id text NOT NULL,

  country_code text NOT NULL,

  /*
   * NULL =
   * combined all-currency behaviour using USD equivalents.
   */
  currency_code text,

  fiscal_year integer NOT NULL,

  /*
   * NULL when scope = fiscal_year.
   */
  period integer,

  scope financial_behavior_scope NOT NULL,

  behavior financial_behavior_type NOT NULL,


  -- ========================================================
  -- BASE
  -- ========================================================

  deposit_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- BEHAVIOUR VALUES
  -- ========================================================

  withdrawal_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  spending_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  saving_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  investment_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  borrowing_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  repayment_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- PERCENTAGES
  -- ========================================================

  withdrawal_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,

  spending_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,

  saving_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,

  investment_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,

  borrowing_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,

  repayment_percentage numeric(9, 4)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- RULE USED
  -- ========================================================

  rule_id uuid
    REFERENCES public.financial_behavior_rule(id),


  calculated_at timestamptz NOT NULL DEFAULT now(),

  created_at timestamptz NOT NULL DEFAULT now(),

  updated_at timestamptz NOT NULL DEFAULT now(),


  CONSTRAINT financial_behavior_scope_period_check
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

-- ============================================================
-- PERIOD + CURRENCY
-- ============================================================

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


-- ============================================================
-- PERIOD + ALL CURRENCIES
-- ============================================================

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


-- ============================================================
-- YEAR + CURRENCY
-- ============================================================

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


-- ============================================================
-- YEAR + ALL CURRENCIES
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
financial_behavior_year_all_currency_unique
ON public.financial_behavior (
  user_id,
  fiscal_year
)
WHERE
  scope = 'fiscal_year'
  AND currency_code IS NULL;

CREATE INDEX IF NOT EXISTS
financial_behavior_user_year_idx
ON public.financial_behavior (
  user_id,
  fiscal_year
);
