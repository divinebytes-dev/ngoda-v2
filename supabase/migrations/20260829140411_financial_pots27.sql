-- ============================================================
-- FINANCIAL INTELLIGENCE
-- STANDARDISE ALL AMOUNTS TO NUMERIC(20,6)
-- ============================================================


-- ============================================================
-- 1. FINANCIAL BADGE
-- ============================================================

ALTER TABLE public.financial_badge
    ALTER COLUMN threshold_usd
        TYPE numeric(20,6);


-- ============================================================
-- 2. USER FINANCIAL BADGE
-- ============================================================

ALTER TABLE public.user_financial_badge
    ALTER COLUMN achieved_value_usd
        TYPE numeric(20,6);


-- ============================================================
-- 3. FINANCIAL POT
-- ============================================================

ALTER TABLE public.financial_pot

    -- Deposit
    ALTER COLUMN deposit_amount
        TYPE numeric(20,6),

    ALTER COLUMN deposit_amount_usd
        TYPE numeric(20,6),

    -- Withdrawal
    ALTER COLUMN withdrawal_amount
        TYPE numeric(20,6),

    ALTER COLUMN withdrawal_amount_usd
        TYPE numeric(20,6),

    -- Spending
    ALTER COLUMN spending_amount
        TYPE numeric(20,6),

    ALTER COLUMN spending_amount_usd
        TYPE numeric(20,6),

    -- Savings
    ALTER COLUMN opening_savings
        TYPE numeric(20,6),

    ALTER COLUMN savings_inflow
        TYPE numeric(20,6),

    ALTER COLUMN savings_outflow
        TYPE numeric(20,6),

    ALTER COLUMN closing_savings
        TYPE numeric(20,6),

    ALTER COLUMN opening_savings_usd
        TYPE numeric(20,6),

    ALTER COLUMN savings_inflow_usd
        TYPE numeric(20,6),

    ALTER COLUMN savings_outflow_usd
        TYPE numeric(20,6),

    ALTER COLUMN closing_savings_usd
        TYPE numeric(20,6),

    ALTER COLUMN saving_amount
        TYPE numeric(20,6),

    ALTER COLUMN saving_amount_usd
        TYPE numeric(20,6),

    -- Investment activity
    ALTER COLUMN investment_purchase_amount
        TYPE numeric(20,6),

    ALTER COLUMN investment_purchase_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN investment_sale_amount
        TYPE numeric(20,6),

    ALTER COLUMN investment_sale_amount_usd
        TYPE numeric(20,6),

    -- Gold
    ALTER COLUMN gold_purchased
        TYPE numeric(20,6),

    ALTER COLUMN gold_sold
        TYPE numeric(20,6),

    ALTER COLUMN gold_transferred_in
        TYPE numeric(20,6),

    ALTER COLUMN gold_transferred_out
        TYPE numeric(20,6),

    ALTER COLUMN opening_gold_quantity
        TYPE numeric(20,6),

    ALTER COLUMN closing_gold_quantity
        TYPE numeric(20,6),

    -- Investment position
    ALTER COLUMN opening_investment_usd
        TYPE numeric(20,6),

    ALTER COLUMN investment_inflow_usd
        TYPE numeric(20,6),

    ALTER COLUMN investment_outflow_usd
        TYPE numeric(20,6),

    ALTER COLUMN closing_investment_usd
        TYPE numeric(20,6),

    -- Loan
    ALTER COLUMN opening_loan_balance
        TYPE numeric(20,6),

    ALTER COLUMN loan_disbursed_amount
        TYPE numeric(20,6),

    ALTER COLUMN loan_repayment_amount
        TYPE numeric(20,6),

    ALTER COLUMN loan_interest_accrued
        TYPE numeric(20,6),

    ALTER COLUMN closing_loan_balance
        TYPE numeric(20,6),

    ALTER COLUMN opening_loan_balance_usd
        TYPE numeric(20,6),

    ALTER COLUMN loan_disbursed_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN loan_repayment_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN loan_interest_accrued_usd
        TYPE numeric(20,6),

    ALTER COLUMN closing_loan_balance_usd
        TYPE numeric(20,6),

    -- Loan repayment breakdown
    ALTER COLUMN loan_principal_repaid
        TYPE numeric(20,6),

    ALTER COLUMN loan_interest_repaid
        TYPE numeric(20,6),

    ALTER COLUMN loan_principal_repaid_usd
        TYPE numeric(20,6),

    ALTER COLUMN loan_interest_repaid_usd
        TYPE numeric(20,6);


-- ============================================================
-- 4. FINANCIAL POT EVENT
-- ============================================================

ALTER TABLE public.financial_pot_event

    ALTER COLUMN amount
        TYPE numeric(20,6),

    ALTER COLUMN amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN cash_amount
        TYPE numeric(20,6),

    ALTER COLUMN cash_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN gold_quantity
        TYPE numeric(20,6),

    ALTER COLUMN investment_cost_usd
        TYPE numeric(20,6),

    ALTER COLUMN principal_amount
        TYPE numeric(20,6),

    ALTER COLUMN principal_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN interest_amount
        TYPE numeric(20,6),

    ALTER COLUMN interest_amount_usd
        TYPE numeric(20,6);


-- ============================================================
-- 5. FINANCIAL BEHAVIOR
-- ============================================================

ALTER TABLE public.financial_behavior

    ALTER COLUMN deposit_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN withdrawal_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN spending_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN saving_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN investment_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN borrowing_amount_usd
        TYPE numeric(20,6),

    ALTER COLUMN repayment_amount_usd
        TYPE numeric(20,6);