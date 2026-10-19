-- Run separately and commit BEFORE the master-data seed.
-- Preserves the supplied borrower badges' repayment-based metric.
ALTER TYPE public.financial_badge_metric ADD VALUE IF NOT EXISTS 'repayment';
