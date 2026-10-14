-- ============================================================
-- FINANCIAL BADGE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_badge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  code text NOT NULL UNIQUE,

  behavior financial_behavior_type NOT NULL,

  metric financial_badge_metric NOT NULL,

  level integer NOT NULL,

  threshold_usd numeric(20, 2) NOT NULL,

  name text NOT NULL,

  description text,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT financial_badge_level_check
    CHECK (level > 0),

  CONSTRAINT financial_badge_threshold_check
    CHECK (threshold_usd > 0),

  CONSTRAINT financial_badge_behavior_level_unique
    UNIQUE (
      behavior,
      level
    )
);



-- ============================================================
-- USER FINANCIAL BADGE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_financial_badge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id text NOT NULL,

  badge_id uuid NOT NULL
    REFERENCES public.financial_badge(id),

  achieved_value_usd numeric(20, 2) NOT NULL,

  fiscal_year integer,

  period integer,

  achieved_at timestamptz NOT NULL DEFAULT now(),

  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT user_financial_badge_value_check
    CHECK (achieved_value_usd >= 0),

  CONSTRAINT user_financial_badge_period_check
    CHECK (
      period IS NULL
      OR period BETWEEN 1 AND 12
    ),

  CONSTRAINT user_financial_badge_unique
    UNIQUE (
      user_id,
      badge_id
    )
);

CREATE INDEX IF NOT EXISTS
user_financial_badge_user_idx
ON public.user_financial_badge (
  user_id
);


CREATE INDEX IF NOT EXISTS
user_financial_badge_user_year_idx
ON public.user_financial_badge (
  user_id,
  fiscal_year
);


-- ============================================================
-- FINANCIAL BEHAVIOUR RULE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_behavior_rule (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  code text NOT NULL UNIQUE,

  behavior financial_behavior_type NOT NULL,

  name text NOT NULL,

  description text,

  priority integer NOT NULL DEFAULT 100,

  conditions jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT financial_behavior_rule_priority_check
    CHECK (priority > 0)
);

-- ============================================================
-- FINANCIAL POT
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_pot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id text NOT NULL,

  country_code text NOT NULL,

  currency_code text NOT NULL,

  fiscal_year integer NOT NULL,

  period integer NOT NULL,


  -- ========================================================
  -- DEPOSIT
  --
  -- Money entering the user's available financial position.
  --
  -- Examples:
  -- cash_deposit
  -- cash_transfer received
  -- gold_token_sell proceeds
  -- loan_disbursement
  -- ========================================================

  deposit_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  deposit_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- WITHDRAWAL
  --
  -- Examples:
  -- cash_withdrawal
  -- cash_transfer sent
  -- ========================================================

  withdrawal_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  withdrawal_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- SPENDING
  --
  -- merchant_payment
  -- ========================================================

  spending_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  spending_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- SAVINGS POSITION
  --
  -- Savings is NOT wallet.balance.
  --
  -- It is the Financial Pots retained-money position.
  -- ========================================================

  opening_savings numeric(20, 6)
    NOT NULL DEFAULT 0,

  savings_inflow numeric(20, 6)
    NOT NULL DEFAULT 0,

  savings_outflow numeric(20, 6)
    NOT NULL DEFAULT 0,

  closing_savings numeric(20, 6)
    NOT NULL DEFAULT 0,


  opening_savings_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  savings_inflow_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  savings_outflow_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  closing_savings_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- SAVED DURING THIS PERIOD
  --
  -- This is useful for:
  -- Saver behaviour
  -- Saver badges
  --
  -- It is different from closing_savings.
  -- ========================================================

  saving_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  saving_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- INVESTMENT ACTIVITY
  -- ========================================================

  investment_purchase_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  investment_purchase_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  investment_sale_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  investment_sale_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- GOLD QUANTITY
  -- ========================================================

  gold_purchased numeric(20, 6)
    NOT NULL DEFAULT 0,

  gold_sold numeric(20, 6)
    NOT NULL DEFAULT 0,

  gold_transferred_in numeric(20, 6)
    NOT NULL DEFAULT 0,

  gold_transferred_out numeric(20, 6)
    NOT NULL DEFAULT 0,


  opening_gold_quantity numeric(20, 6)
    NOT NULL DEFAULT 0,

  closing_gold_quantity numeric(20, 6)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- INVESTMENT POSITION
  --
  -- USD cost / position values.
  --
  -- Current market valuation will be calculated separately
  -- using current gold price.
  -- ========================================================

  opening_investment_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  investment_inflow_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  investment_outflow_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  closing_investment_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- LOANS
  -- ========================================================

  opening_loan_balance numeric(20, 6)
    NOT NULL DEFAULT 0,

  loan_disbursed_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  loan_repayment_amount numeric(20, 6)
    NOT NULL DEFAULT 0,

  loan_interest_accrued numeric(20, 6)
    NOT NULL DEFAULT 0,

  closing_loan_balance numeric(20, 6)
    NOT NULL DEFAULT 0,


  opening_loan_balance_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  loan_disbursed_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  loan_repayment_amount_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  loan_interest_accrued_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  closing_loan_balance_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- REPAYMENT DETAIL
  -- ========================================================

  loan_principal_repaid numeric(20, 6)
    NOT NULL DEFAULT 0,

  loan_interest_repaid numeric(20, 6)
    NOT NULL DEFAULT 0,

  loan_principal_repaid_usd numeric(20, 2)
    NOT NULL DEFAULT 0,

  loan_interest_repaid_usd numeric(20, 2)
    NOT NULL DEFAULT 0,


  -- ========================================================
  -- BEHAVIOUR / ALLOCATION PERCENTAGES
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


  created_at timestamptz NOT NULL DEFAULT now(),

  updated_at timestamptz NOT NULL DEFAULT now(),


  CONSTRAINT financial_pot_period_check
    CHECK (
      period BETWEEN 1 AND 12
    ),


  CONSTRAINT financial_pot_unique
    UNIQUE (
      user_id,
      currency_code,
      fiscal_year,
      period
    ),


  CONSTRAINT financial_pot_non_negative_activity_check
    CHECK (
      deposit_amount >= 0
      AND deposit_amount_usd >= 0

      AND withdrawal_amount >= 0
      AND withdrawal_amount_usd >= 0

      AND spending_amount >= 0
      AND spending_amount_usd >= 0

      AND savings_inflow >= 0
      AND savings_inflow_usd >= 0

      AND savings_outflow >= 0
      AND savings_outflow_usd >= 0

      AND saving_amount >= 0
      AND saving_amount_usd >= 0

      AND investment_purchase_amount >= 0
      AND investment_purchase_amount_usd >= 0

      AND investment_sale_amount >= 0
      AND investment_sale_amount_usd >= 0

      AND gold_purchased >= 0
      AND gold_sold >= 0
      AND gold_transferred_in >= 0
      AND gold_transferred_out >= 0

      AND investment_inflow_usd >= 0
      AND investment_outflow_usd >= 0

      AND loan_disbursed_amount >= 0
      AND loan_disbursed_amount_usd >= 0

      AND loan_repayment_amount >= 0
      AND loan_repayment_amount_usd >= 0

      AND loan_interest_accrued >= 0
      AND loan_interest_accrued_usd >= 0

      AND loan_principal_repaid >= 0
      AND loan_principal_repaid_usd >= 0

      AND loan_interest_repaid >= 0
      AND loan_interest_repaid_usd >= 0
    )
);

CREATE INDEX IF NOT EXISTS
financial_pot_user_idx
ON public.financial_pot (
  user_id
);


CREATE INDEX IF NOT EXISTS
financial_pot_user_year_idx
ON public.financial_pot (
  user_id,
  fiscal_year
);


CREATE INDEX IF NOT EXISTS
financial_pot_user_currency_year_idx
ON public.financial_pot (
  user_id,
  currency_code,
  fiscal_year
);

