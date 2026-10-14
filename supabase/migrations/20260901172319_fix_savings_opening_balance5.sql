ALTER TABLE public.financial_pot

    /*
     * Actual cash removed from savings by withdrawals.
     */
    ADD COLUMN IF NOT EXISTS withdrawal_cash_amount
        numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS withdrawal_cash_amount_usd
        numeric NOT NULL DEFAULT 0,


    /*
     * Actual cash removed from savings by spending.
     */
    ADD COLUMN IF NOT EXISTS spending_cash_amount
        numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS spending_cash_amount_usd
        numeric NOT NULL DEFAULT 0,


    /*
     * Actual cash removed from savings to buy investments.
     */
    ADD COLUMN IF NOT EXISTS investment_cash_amount
        numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS investment_cash_amount_usd
        numeric NOT NULL DEFAULT 0,


    /*
     * Actual cash removed from savings for loan repayments.
     */
    ADD COLUMN IF NOT EXISTS repayment_cash_amount
        numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS repayment_cash_amount_usd
        numeric NOT NULL DEFAULT 0;