-- ============================================================
-- FINANCIAL INTELLIGENCE ENUMS
-- ============================================================


-- ------------------------------------------------------------
-- Financial behaviour
-- ------------------------------------------------------------

DO $$
BEGIN
  CREATE TYPE financial_behavior_type AS ENUM (
    'shopper',
    'saver',
    'investor',
    'borrower',
    'balanced'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


-- ------------------------------------------------------------
-- Behaviour reporting scope
-- ------------------------------------------------------------

DO $$
BEGIN
  CREATE TYPE financial_behavior_scope AS ENUM (
    'period',
    'fiscal_year'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


-- ------------------------------------------------------------
-- Badge measurement
--
-- This determines which USD value is used when evaluating
-- a badge.
-- ------------------------------------------------------------

DO $$
BEGIN
  CREATE TYPE financial_badge_metric AS ENUM (
    'spending',
    'saving',
    'investment',
    'borrowing'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


-- ------------------------------------------------------------
-- Financial activity
--
-- These are events coming from successful transactions.
--
-- Saving itself is deliberately NOT an activity.
-- Savings is a position affected by other activities.
-- ------------------------------------------------------------

DO $$
BEGIN
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
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;