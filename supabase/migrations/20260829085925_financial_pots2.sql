-- ============================================================
-- FINANCIAL BADGE DEFINITIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_badge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  code text NOT NULL UNIQUE,

  behavior financial_behavior_type NOT NULL,

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
    UNIQUE (behavior, level)
);


INSERT INTO public.financial_badge (
  code,
  behavior,
  level,
  threshold_usd,
  name,
  description
)
VALUES

-- ============================================================
-- SHOPPER
-- ============================================================

(
  'SHOPPER_10',
  'shopper',
  1,
  10,
  'Shopper 10',
  'Spent at least USD 10 equivalent through merchant payments.'
),
(
  'SHOPPER_20',
  'shopper',
  2,
  20,
  'Shopper 20',
  'Spent at least USD 20 equivalent through merchant payments.'
),
(
  'SHOPPER_50',
  'shopper',
  3,
  50,
  'Shopper 50',
  'Spent at least USD 50 equivalent through merchant payments.'
),
(
  'SHOPPER_100',
  'shopper',
  4,
  100,
  'Shopper 100',
  'Spent at least USD 100 equivalent through merchant payments.'
),
(
  'SHOPPER_500',
  'shopper',
  5,
  500,
  'Shopper 500',
  'Spent at least USD 500 equivalent through merchant payments.'
),
(
  'SHOPPER_1000',
  'shopper',
  6,
  1000,
  'Shopper 1,000',
  'Spent at least USD 1,000 equivalent through merchant payments.'
),

-- ============================================================
-- SAVER
-- ============================================================

(
  'SAVER_10',
  'saver',
  1,
  10,
  'Saver 10',
  'Saved at least USD 10 equivalent.'
),
(
  'SAVER_20',
  'saver',
  2,
  20,
  'Saver 20',
  'Saved at least USD 20 equivalent.'
),
(
  'SAVER_50',
  'saver',
  3,
  50,
  'Saver 50',
  'Saved at least USD 50 equivalent.'
),
(
  'SAVER_100',
  'saver',
  4,
  100,
  'Saver 100',
  'Saved at least USD 100 equivalent.'
),
(
  'SAVER_500',
  'saver',
  5,
  500,
  'Saver 500',
  'Saved at least USD 500 equivalent.'
),
(
  'SAVER_1000',
  'saver',
  6,
  1000,
  'Saver 1,000',
  'Saved at least USD 1,000 equivalent.'
),

-- ============================================================
-- INVESTOR
-- ============================================================

(
  'INVESTOR_100',
  'investor',
  1,
  100,
  'Investor 100',
  'Invested at least USD 100 equivalent in gold.'
),
(
  'INVESTOR_500',
  'investor',
  2,
  500,
  'Investor 500',
  'Invested at least USD 500 equivalent in gold.'
),
(
  'INVESTOR_1000',
  'investor',
  3,
  1000,
  'Investor 1,000',
  'Invested at least USD 1,000 equivalent in gold.'
),
(
  'INVESTOR_5000',
  'investor',
  4,
  5000,
  'Investor 5,000',
  'Invested at least USD 5,000 equivalent in gold.'
),
(
  'INVESTOR_10000',
  'investor',
  5,
  10000,
  'Investor 10,000',
  'Invested at least USD 10,000 equivalent in gold.'
)

ON CONFLICT (code)
DO UPDATE SET
  behavior = EXCLUDED.behavior,
  level = EXCLUDED.level,
  threshold_usd = EXCLUDED.threshold_usd,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_active = true,
  updated_at = now();