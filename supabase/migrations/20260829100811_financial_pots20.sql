-- ============================================================
-- ADD NEUTRAL BEHAVIOUR
-- ============================================================

ALTER TYPE financial_behavior_type
ADD VALUE IF NOT EXISTS 'neutral';

-- ============================================================
-- BEHAVIOUR SCORE PERCENTAGES
--
-- These determine:
-- SHOPPER
-- SAVER
-- INVESTOR
-- BORROWER
--
-- They are deliberately separate from allocation percentages.
-- ============================================================

ALTER TABLE public.financial_behavior
ADD COLUMN shopper_score_percentage numeric(9, 4)
  NOT NULL DEFAULT 0,

ADD COLUMN saver_score_percentage numeric(9, 4)
  NOT NULL DEFAULT 0,

ADD COLUMN investor_score_percentage numeric(9, 4)
  NOT NULL DEFAULT 0,

ADD COLUMN borrower_score_percentage numeric(9, 4)
  NOT NULL DEFAULT 0;

  