-- ============================================================
-- FINANCIAL INTELLIGENCE ENUMS
-- ============================================================

DO $$
BEGIN
  CREATE TYPE financial_pot_type AS ENUM (
    'deposit',
    'withdrawal',
    'spending',
    'saving',
    'investment'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


DO $$
BEGIN
  CREATE TYPE financial_behavior_type AS ENUM (
    'shopper',
    'saver',
    'investor',
    'balanced'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


DO $$
BEGIN
  CREATE TYPE financial_behavior_scope AS ENUM (
    'period',
    'fiscal_year'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;