-- ============================================================
-- FINANCIAL POT EVENT
--
-- Records the transaction contribution to a financial pot.
-- This prevents a transaction retry from updating a pot twice.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.financial_pot_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  reference text NOT NULL,
  user_id text NOT NULL,

  country_code text NOT NULL,
  currency_code text NOT NULL,

  fiscal_year integer NOT NULL,
  period integer NOT NULL,

  pot_type financial_pot_type NOT NULL,

  transaction_type text NOT NULL,

  amount numeric(20, 6) NOT NULL,
  amount_usd numeric(20, 2) NOT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT financial_pot_event_period_check
    CHECK (period BETWEEN 1 AND 12),

  CONSTRAINT financial_pot_event_amount_check
    CHECK (amount >= 0),

  CONSTRAINT financial_pot_event_amount_usd_check
    CHECK (amount_usd >= 0),

  /*
   * A transaction reference may affect different users.
   *
   * Example:
   * cash_transfer
   *
   * sender   -> withdrawal
   * receiver -> deposit
   *
   * Therefore user_id must be part of the unique key.
   */
  CONSTRAINT financial_pot_event_unique
    UNIQUE (
      reference,
      user_id,
      pot_type
    )
);


CREATE INDEX IF NOT EXISTS
financial_pot_event_user_period_idx
ON public.financial_pot_event (
  user_id,
  fiscal_year,
  period
);


CREATE INDEX IF NOT EXISTS
financial_pot_event_user_currency_period_idx
ON public.financial_pot_event (
  user_id,
  currency_code,
  fiscal_year,
  period
);

