ALTER TABLE public.financial_pot_event
ADD COLUMN cash_amount numeric(20, 6) NOT NULL DEFAULT 0,
ADD COLUMN cash_amount_usd numeric(20, 2) NOT NULL DEFAULT 0;
