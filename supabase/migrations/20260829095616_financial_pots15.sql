-- ============================================================
-- FINANCIAL BADGE SEED DATA
-- ============================================================

INSERT INTO public.financial_badge (
  code,
  behavior,
  metric,
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
  'spending',
  1,
  10,
  'Shopper 10',
  'Spent at least USD 10 equivalent through merchant payments.'
),

(
  'SHOPPER_20',
  'shopper',
  'spending',
  2,
  20,
  'Shopper 20',
  'Spent at least USD 20 equivalent through merchant payments.'
),

(
  'SHOPPER_50',
  'shopper',
  'spending',
  3,
  50,
  'Shopper 50',
  'Spent at least USD 50 equivalent through merchant payments.'
),

(
  'SHOPPER_100',
  'shopper',
  'spending',
  4,
  100,
  'Shopper 100',
  'Spent at least USD 100 equivalent through merchant payments.'
),

(
  'SHOPPER_500',
  'shopper',
  'spending',
  5,
  500,
  'Shopper 500',
  'Spent at least USD 500 equivalent through merchant payments.'
),

(
  'SHOPPER_1000',
  'shopper',
  'spending',
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
  'saving',
  1,
  10,
  'Saver 10',
  'Saved at least USD 10 equivalent.'
),

(
  'SAVER_20',
  'saver',
  'saving',
  2,
  20,
  'Saver 20',
  'Saved at least USD 20 equivalent.'
),

(
  'SAVER_50',
  'saver',
  'saving',
  3,
  50,
  'Saver 50',
  'Saved at least USD 50 equivalent.'
),

(
  'SAVER_100',
  'saver',
  'saving',
  4,
  100,
  'Saver 100',
  'Saved at least USD 100 equivalent.'
),

(
  'SAVER_500',
  'saver',
  'saving',
  5,
  500,
  'Saver 500',
  'Saved at least USD 500 equivalent.'
),

(
  'SAVER_1000',
  'saver',
  'saving',
  6,
  1000,
  'Saver 1,000',
  'Saved at least USD 1,000 equivalent.'
),

(
  'SAVER_5000',
  'saver',
  'saving',
  7,
  5000,
  'Saver 5,000',
  'Saved at least USD 5,000 equivalent.'
),


-- ============================================================
-- INVESTOR
-- ============================================================

(
  'INVESTOR_100',
  'investor',
  'investment',
  1,
  100,
  'Investor 100',
  'Invested at least USD 100 equivalent in gold.'
),

(
  'INVESTOR_500',
  'investor',
  'investment',
  2,
  500,
  'Investor 500',
  'Invested at least USD 500 equivalent in gold.'
),

(
  'INVESTOR_1000',
  'investor',
  'investment',
  3,
  1000,
  'Investor 1,000',
  'Invested at least USD 1,000 equivalent in gold.'
),

(
  'INVESTOR_5000',
  'investor',
  'investment',
  4,
  5000,
  'Investor 5,000',
  'Invested at least USD 5,000 equivalent in gold.'
),

(
  'INVESTOR_10000',
  'investor',
  'investment',
  5,
  10000,
  'Investor 10,000',
  'Invested at least USD 10,000 equivalent in gold.'
),


-- ============================================================
-- BORROWER
-- ============================================================

(
  'BORROWER_100',
  'borrower',
  'borrowing',
  1,
  100,
  'Borrower 100',
  'Borrowed at least USD 100 equivalent while accessing liquidity.'
),

(
  'BORROWER_500',
  'borrower',
  'borrowing',
  2,
  500,
  'Borrower 500',
  'Borrowed at least USD 500 equivalent while accessing liquidity.'
),

(
  'BORROWER_1000',
  'borrower',
  'borrowing',
  3,
  1000,
  'Borrower 1,000',
  'Borrowed at least USD 1,000 equivalent while accessing liquidity.'
),

(
  'BORROWER_5000',
  'borrower',
  'borrowing',
  4,
  5000,
  'Borrower 5,000',
  'Borrowed at least USD 5,000 equivalent while accessing liquidity.'
),

(
  'BORROWER_10000',
  'borrower',
  'borrowing',
  5,
  10000,
  'Borrower 10,000',
  'Borrowed at least USD 10,000 equivalent while accessing liquidity.'
)

ON CONFLICT (code)
DO UPDATE SET

  behavior =
    EXCLUDED.behavior,

  metric =
    EXCLUDED.metric,

  level =
    EXCLUDED.level,

  threshold_usd =
    EXCLUDED.threshold_usd,

  name =
    EXCLUDED.name,

  description =
    EXCLUDED.description,

  is_active = true,

  updated_at = now();

  