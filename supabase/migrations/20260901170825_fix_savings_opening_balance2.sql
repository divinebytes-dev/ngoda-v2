ALTER TABLE public.financial_pot

    /*
     * ==========================================================
     * CASH IN
     * ==========================================================
     *
     * Cash actually entering savings from:
     *
     * - cash_deposit
     * - credit_agent_cash_deposit
     * - customer_direct_deposit
     *
     * This is separate from deposit_amount because deposit_amount
     * represents the financial activity/business amount while this
     * represents the actual cash movement into savings.
     * ==========================================================
     */

    ADD COLUMN IF NOT EXISTS cash_in_amount numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS cash_in_amount_usd numeric NOT NULL DEFAULT 0,


    /*
     * ==========================================================
     * TRANSFER IN
     * ==========================================================
     *
     * Cash entering savings from an incoming cash_transfer.
     * ==========================================================
     */

    ADD COLUMN IF NOT EXISTS transfer_in_amount numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS transfer_in_amount_usd numeric NOT NULL DEFAULT 0,


    /*
     * ==========================================================
     * INVESTMENT PROCEEDS
     * ==========================================================
     *
     * Cash returned to savings from selling an investment,
     * currently gold_token_sell.
     * ==========================================================
     */

    ADD COLUMN IF NOT EXISTS investment_proceeds_amount numeric NOT NULL DEFAULT 0,

    ADD COLUMN IF NOT EXISTS investment_proceeds_amount_usd numeric NOT NULL DEFAULT 0;