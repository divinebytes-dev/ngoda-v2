-- ============================================================
-- DROP EXISTING FINANCIAL INTELLIGENCE OBJECTS
-- ============================================================

DROP TABLE IF EXISTS public.user_financial_badge CASCADE;
DROP TABLE IF EXISTS public.financial_behavior CASCADE;
DROP TABLE IF EXISTS public.financial_pot_event CASCADE;
DROP TABLE IF EXISTS public.financial_pot CASCADE;
DROP TABLE IF EXISTS public.financial_behavior_rule CASCADE;
DROP TABLE IF EXISTS public.financial_badge CASCADE;


DROP TYPE IF EXISTS financial_activity_type CASCADE;
DROP TYPE IF EXISTS financial_badge_metric CASCADE;
DROP TYPE IF EXISTS financial_behavior_scope CASCADE;
DROP TYPE IF EXISTS financial_behavior_type CASCADE;

-- ============================================================
-- FINANCIAL INTELLIGENCE ENUMS
-- ============================================================

CREATE TYPE financial_behavior_type AS ENUM (
  'shopper',
  'saver',
  'investor',
  'borrower',
  'balanced'
);


CREATE TYPE financial_behavior_scope AS ENUM (
  'period',
  'fiscal_year'
);


CREATE TYPE financial_badge_metric AS ENUM (
  'spending',
  'saving',
  'investment',
  'borrowing'
);


CREATE TYPE financial_activity_type AS ENUM (
  'deposit',
  'withdrawal',
  'spending',

  'investment_buy',
  'investment_sell',
  'investment_transfer_in',
  'investment_transfer_out',

  'loan_disbursement',
  'loan_repayment',
  'loan_interest_accrual'
);

