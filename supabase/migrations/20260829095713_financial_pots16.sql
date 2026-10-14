-- ============================================================
-- FINANCIAL BEHAVIOUR RULE SEED
-- ============================================================

INSERT INTO public.financial_behavior_rule (
  code,
  behavior,
  name,
  description,
  priority,
  conditions
)
VALUES

-- ============================================================
-- BALANCED
-- ============================================================

(
  'BALANCED_V1',
  'balanced',
  'Balanced',
  'No single core financial behaviour is sufficiently dominant.',
  10,
  '{
    "rule_type": "spread",

    "included_metrics": [
      "spending",
      "saving",
      "investment",
      "borrowing"
    ],

    "maximum_spread_percentage": 10
  }'::jsonb
),


-- ============================================================
-- INVESTOR
-- ============================================================

(
  'INVESTOR_V1',
  'investor',
  'Investor',
  'Investment is the dominant financial behaviour.',
  20,
  '{
    "rule_type": "dominant",

    "metric": "investment",

    "minimum_percentage": 30
  }'::jsonb
),


-- ============================================================
-- SAVER
-- ============================================================

(
  'SAVER_V1',
  'saver',
  'Saver',
  'Saving is the dominant financial behaviour.',
  30,
  '{
    "rule_type": "dominant",

    "metric": "saving",

    "minimum_percentage": 30
  }'::jsonb
),


-- ============================================================
-- BORROWER
-- ============================================================

(
  'BORROWER_V1',
  'borrower',
  'Borrower',
  'Borrowing is the dominant financial behaviour for the period.',
  40,
  '{
    "rule_type": "dominant",

    "metric": "borrowing",

    "minimum_percentage": 30
  }'::jsonb
),


-- ============================================================
-- SHOPPER
-- ============================================================

(
  'SHOPPER_V1',
  'shopper',
  'Shopper',
  'Merchant spending is the dominant financial behaviour.',
  50,
  '{
    "rule_type": "dominant",

    "metric": "spending",

    "minimum_percentage": 30
  }'::jsonb
)

ON CONFLICT (code)
DO UPDATE SET

  behavior =
    EXCLUDED.behavior,

  name =
    EXCLUDED.name,

  description =
    EXCLUDED.description,

  priority =
    EXCLUDED.priority,

  conditions =
    EXCLUDED.conditions,

  is_active = true,

  updated_at = now();


  -- ============================================================
-- ENABLE RLS
-- ============================================================

ALTER TABLE public.financial_badge
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_financial_badge
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.financial_behavior_rule
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.financial_pot
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.financial_pot_event
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.financial_behavior
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS
financial_badge_select_authenticated
ON public.financial_badge;


CREATE POLICY financial_badge_select_authenticated
ON public.financial_badge
FOR SELECT
TO authenticated
USING (
  is_active = true
);