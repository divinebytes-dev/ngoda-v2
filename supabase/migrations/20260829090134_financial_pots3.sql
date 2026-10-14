-- ============================================================
-- USER EARNED BADGES
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

  CONSTRAINT user_financial_badge_period_check
    CHECK (
      period IS NULL
      OR period BETWEEN 1 AND 12
    ),

  CONSTRAINT user_financial_badge_unique
    UNIQUE (user_id, badge_id)
);

-- ============================================================
-- FINANCIAL BEHAVIOUR RULES
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
  updated_at timestamptz NOT NULL DEFAULT now()
);