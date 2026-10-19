-- Ngoda consolidated master-data seed.
-- Run against a database with the required tables, enums, defaults, and
-- functions already created. Uses plain INSERT; intended for unseeded tables.
-- Use this file INSTEAD OF the 30 individual seed files, not in addition.
-- All SQL seed writes are enclosed in one transaction.
-- Source values and previously agreed adjustments are retained.
-- Admin Auth seeding is separate; run seed_super_admin.ts after COMMIT.
--
-- Run 00_badge_repayment_metric.sql first, as a separate committed migration.
-- Requires the reviewed schema and its latest fiscal/history/KYC corrections.
-- Fresh QA only: existing master rows are not cleared or silently overwritten.
-- Pending and verified limits are included below; do not run their separate seeds too.
-- Verified max/day/month caps are proposed QA settings: 5x pending, minimum unchanged.
-- Supplied chain configuration is Chiado TESTNET; verify contract and treasury ownership.
--
-- Loyalty/financial badge thresholds remain as agreed.
-- Borrower badges are aligned to repayment by the behavior-rule section.
-- Network parent resolves using code='gnosis'; is_default remains false.

BEGIN;

-- 01. user_role
-- Source: 20261014092800_seed_user_role.sql
INSERT INTO public.user_role (
    name, description, created_at, updated_at, updated_by
) VALUES
    ('accounts', 'Accounts team responsible for financial statements', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('admin', 'System administrator with full access', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('agent', 'Agent handling deposits and withdrawals', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('audit', 'Auditor', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('compliance', 'Compliance with government regulations', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('customer', 'Standard end user', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('employee', 'Company employee', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('finance', 'Finance team responsible for GL and settlements', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('merchant', 'User handling payments, deposits and withdrawals', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('operations', 'Platform operations', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('reserve_bank', 'Reserve bank monitoring team', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('treasury', 'Treasury operations and asset management', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null),
    ('vendor', 'User handling payments, deposits and withdrawals', '2026-07-20 15:10:33.071+00', '2026-07-20 15:10:33.071+00', null);

-- 02. supported_currency
-- Source: 20261014092900_seed_supported_currency.sql
INSERT INTO public.supported_currency (
    currency_code, name, decimals, currency_category, symbol, rate_api, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    ('gold', 'Gold Token', 6, 'token', 'GOLD', 'https://api.gold-api.com/price/XAU', true, 'admin', '2026-07-20 15:10:30.734+00', '2026-07-20 15:10:30.734', null),
    ('usd', 'US Dollar', 2, 'fiat', '$', 'https://api.coinbase.com/v2/prices/USD-USD/buy', true, 'admin', '2026-07-20 15:10:30.734+00', '2026-07-20 15:10:30.734', null),
    ('zig', 'Zimbabwe Gold', 2, 'fiat', 'ZiG', 'https://api.coinbase.com/v2/prices/USD-ZIG/buy', true, 'admin', '2026-07-20 15:10:30.734+00', '2026-07-20 15:10:30.734', null),
    ('zar', 'South African Rand', 2, 'fiat', 'R', 'https://api.coinbase.com/v2/prices/USD-ZAR/buy', true, 'admin', '2026-07-20 15:10:30.734+00', '2026-07-20 15:10:30.734', null),
    ('bwp', 'Botswana Pula', 2, 'fiat', 'P', 'https://api.coinbase.com/v2/prices/USD-BWP/buy', true, 'admin', '2026-07-20 15:10:30.734+00', '2026-07-20 15:10:30.734', null);

-- 03. operational_country
-- Source: 20261014093000_seed_operational_country.sql
INSERT INTO public.operational_country (
    country_code, name, is_active,
    created_by, created_at, updated_at, updated_by, calling_code
) VALUES
    ('bw', 'Botswana', false, 'admin', '2026-07-20 15:10:31.903+00', '2026-07-20 15:10:31.903', null, '267'),
    ('za', 'South Africa', false, 'admin', '2026-07-20 15:10:31.903+00', '2026-07-20 15:10:31.903', null, '27'),
    ('zw', 'Zimbabwe', true, 'admin', '2026-07-20 15:10:31.903+00', '2026-07-20 15:10:31.903', null, '263');

-- 04. supported_language
-- Source: 20261014093100_seed_supported_language.sql
INSERT INTO public.supported_language (
    code, name, is_active, is_default,
    created_by, created_at, updated_at, updated_by
) VALUES
    ('en', 'English', true, true, 'admin', '2026-07-20 15:10:31.321+00', '2026-07-20 15:10:31.321', null),
    ('sn', 'Shona', true, false, 'admin', '2026-07-20 15:10:31.321+00', '2026-07-20 15:10:31.321', null);

-- 05. transaction_types
-- Source: 20261014093200_seed_transaction_types.sql
INSERT INTO public.transaction_types (transaction_type, description, is_active, created_by, created_at, updated_at, updated_by) VALUES ('external_funding', 'Receive external funding ', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('treasury_funding', 'Finance treasury cash float', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_deposit', 'Agent deposit cash into company bank', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_funding', 'Treasury fund agent cash float', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_settlement', 'Agent returns float back to treasury', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_settlement_sub_tx', 'Treasury deposit cash into agent bank', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_commission_settlement', 'Settlement payment of agent commissions', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('customer_direct_deposit', 'Customer deposit cash via bank into wallet', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_funding', 'Company funds high volume agents on credit', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_deposit', 'Customer deposit at a credit agent', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_withdrawal', 'Customer withdrawals at a credit agent', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_settlement', 'Credit agent deposits company cash', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_settlement', 'Credit agent returns all the float', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_deposit', 'Customer deposit cash via agent into wallet', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_transfer', 'Cash transfer between customers', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_withdrawal', 'Cash withdrawal via agent', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_payment', 'Customer pays a merchant', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_withdrawal', 'Merchant withdraws cash', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_commission_settlement', 'Settlement payment of merchant commissions', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_buy', 'Customer buys gold tokens (Cash movement – customer to treasury)', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_sell', 'Customer sells gold tokens (Cash movement – treasury to customer)', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_transfer', 'Gold tokens transfer between customers', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_buy_sub_tx', 'Customer buys gold tokens (Token movement – customer to treasury)', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_sell_sub_tx', 'Customer sells gold tokens (Token movement – treasury to customer)', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_inventory_purchase', 'Treasury purchase physical gold for inventory', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_inventory_sell', 'Treasury sell physical gold inventory', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_disbursement', 'Loan principal disbursement to customers', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_repayment', 'Loan repayment by customers', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_interest_accrual', 'Accrued daily loan interest posting', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_liquidation', 'Loan liquidation via collateral', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_liquidation_sub_tx', 'Loan liquidation token movement', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_mint', 'Minting of gold tokens by treasury', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_burn', 'Burning of gold tokens by treasury', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('referral_commission_settlement', 'Settlement payment of referral commission', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gl_adjustment', 'Manual GL adjustment entry', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('government_tax_clearing', 'Settlement payment of government tax', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('external_funding_reversal', 'Receive external funding reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('treasury_funding_reversal', 'Finance treasury cash float reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_deposit_reversal', 'Agent deposit cash into company bank reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_funding_reversal', 'Treasury fund agent cash float reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_settlement_reversal', 'Agent returns float back to treasury reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_settlement_sub_tx_reversal', 'Treasury deposit cash into agent bank reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('agent_commission_settlement_reversal', 'Settlement payment of agent commissions reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('customer_direct_deposit_reversal', 'Customer deposit cash via bank into wallet reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_funding_reversal', 'Company funds high volume agents on credit reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_deposit_reversal', 'Customer deposit at a credit agent reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_withdrawal_reversal', 'Customer withdrawals at a credit agent reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_cash_settlement_reversal', 'Credit agent deposits company cash reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('credit_agent_settlement_reversal', 'Credit agent returns all the float reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_deposit_reversal', 'Customer deposit cash via agent into wallet reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_transfer_reversal', 'Cash transfer between customers reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('cash_withdrawal_reversal', 'Cash withdrawal via agent reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_payment_reversal', 'Customer pays a merchant reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_withdrawal_reversal', 'Merchant withdraws cash reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('merchant_commission_settlement_reversal', 'Settlement payment of merchant commissions reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_buy_reversal', 'Customer buys gold tokens (Cash movement – customer to treasury) reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_sell_reversal', 'Customer sells gold tokens (Cash movement – treasury to customer) reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_transfer_reversal', 'Gold tokens transfer between customers reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_buy_sub_tx_reversal', 'Customer buys gold tokens (Token movement – customer to treasury) reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_sell_sub_tx_reversal', 'Customer sells gold tokens (Token movement – treasury to customer) reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_inventory_purchase_reversal', 'Treasury purchase physical gold for inventory reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_inventory_sell_reversal', 'Treasury sell physical gold inventory reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_disbursement_reversal', 'Loan principal disbursement to customers reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_repayment_reversal', 'Loan repayment by customers reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_interest_accrual_reversal', 'Accrued daily loan interest posting reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_liquidation_reversal', 'Loan liquidation via collateral reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('loan_liquidation_sub_tx_reversal', 'Loan liquidation token movement reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_mint_reversal', 'Minting of gold tokens by treasury reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gold_token_burn_reversal', 'Burning of gold tokens by treasury reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('referral_commission_settlement_reversal', 'Settlement payment of referral commission reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('gl_adjustment_reversal', 'Manual GL adjustment entry reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null), ('government_tax_clearing_reversal', 'Settlement payment of government tax reversal', true, 'admin', '2026-07-20 15:10:36.505+00', '2026-07-20 15:10:36.505', null);

-- 06. supported_blockchain
-- Source: 20261014112009_seed_supported_blockchain.sql
INSERT INTO public.supported_blockchain (
    code, name, blockchain_type, native_currency_code, is_active,
    created_at, updated_at, contract_address
) VALUES (
    'gnosis', 'Gnosis', 'evm', 'XDAI', true,
    '2026-10-09 12:42:54.094355',
    '2026-10-09 13:29:48.98228',
    '0x1824a96A6A17C15641F76a113A098945c0D75F43'
);

-- 07. supported_blockchain_network
-- Source: 20261014112410_seed_supported_blockchain_network.sql
INSERT INTO public.supported_blockchain_network (
    blockchain_id,
    network_name,
    environment,
    chain_id,
    rpc_url,
    explorer_url,
    is_active,
    is_default,
    created_at,
    updated_at,
    treasury_wallet_address
) VALUES (
    (SELECT id FROM public.supported_blockchain WHERE code = 'gnosis'),
    'Gnosis Chiado',
    'testnet',
    10200,
    'https://rpc.chiadochain.net',
    'https://gnosis-chiado.blockscout.com',
    true,
    false,
    '2026-10-09 12:42:54.094355',
    '2026-10-09 12:42:54.094355',
    '0x99c5a4a0e4f42a59dF6151f69229a3d510c69E52'
);

-- 08. country_currencies
-- Source: 20261014094513_seed_country_currencies.sql
INSERT INTO public.country_currencies (
    currency_code, country_code, is_active, is_reporting,
    created_by, created_at, updated_at, updated_by
) VALUES
    ('bwp', 'zw', true, false, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null),
    ('bwp', 'bw', true, false, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null),
    ('zig', 'zw', true, false, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null),
    ('usd', 'zw', true, false, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null),
    ('zar', 'zw', true, false, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null),
    ('usd', 'bw', true, true, 'admin', '2026-07-20 15:10:32.486+00', '2026-07-20 15:10:32.486', null);

-- 09. fiscal_period_config
-- Source: 20261014100019_seed_fiscal_period_config.sql
INSERT INTO public.fiscal_period_config (
    fiscal_year, period, country_code, period_name,
    opening_date, closing_date, is_closed,
    created_at, created_by, updated_at, updated_by
) VALUES
    (2026, 1, 'zw', 'Jan', '2025-12-31 22:00:00', '2026-01-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 2, 'zw', 'Feb', '2026-01-31 22:00:00', '2026-02-28 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 3, 'zw', 'Mar', '2026-02-28 22:00:00', '2026-03-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 4, 'zw', 'Apr', '2026-03-31 22:00:00', '2026-04-30 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 5, 'zw', 'May', '2026-04-30 22:00:00', '2026-05-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 6, 'zw', 'Jun', '2026-05-31 22:00:00', '2026-06-30 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 7, 'zw', 'Jul', '2026-06-30 22:00:00', '2026-07-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 8, 'zw', 'Aug', '2026-07-31 22:00:00', '2026-08-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 9, 'zw', 'Sep', '2026-08-31 22:00:00', '2026-09-30 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 10, 'zw', 'Oct', '2026-09-30 22:00:00', '2026-10-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 11, 'zw', 'Nov', '2026-10-31 22:00:00', '2026-11-30 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null),
    (2026, 12, 'zw', 'Dec', '2026-11-30 22:00:00', '2026-12-31 21:59:59', false, '2026-07-20 15:10:35.324', 'admin', '2026-07-20 15:10:35.324', null);

-- 10. gl_account
-- Source: 20261014100424_seed_gl_account.sql
INSERT INTO public.gl_account (
    code, description, type, currency_category, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    ('1001000', 'Bank', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1002000', 'Treasury Float', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1003000', 'Agent Float', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1004000', 'Gold Inventory', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1005000', 'Loan Receivable', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1006000', 'Interest Receivable', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1007000', 'Agent Receivable (Credit Agents)', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('1008000', 'Agent Cash Holding (Cash with credit agent)', 'asset', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2001000', 'Agent Float Payable', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2002000', 'Customer Deposits', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2003000', 'Government Tax Payable', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2004000', 'Agent Commission Payable', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2005000', 'Gold Token Conversion', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2006000', 'Merchant Commission Payable', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('2007000', 'Referral Commission Payable', 'liability', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('3001000', 'Share Capital', 'equity', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('3002000', 'Current Year Profit', 'equity', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('3003000', 'Retained Earnings', 'equity', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4001000', 'Transfer Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4002000', 'Withdrawal Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4003000', 'Loan Initiation Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4004000', 'Loan Interest Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4005000', 'Loan Liquidation Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4006000', 'Rounding Gain', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4007000', 'Deposit Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4008000', 'Payment Fee Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('4009000', 'Gold Token Trading Spread Revenue', 'revenue', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5001000', 'Agent Commission Expense', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5002000', 'Rounding Loss', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5003000', 'Compliance Expenses', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5004000', 'Gold Handling Expenses', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5005000', 'Merchant Commission Expense', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5006000', 'Referral Commission Expense', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('5007000', 'Hosting Platform Service Expense', 'expense', 'fiat', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1001000', 'Gold Token Supply', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1002000', 'Treasury Gold Tokens', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1003000', 'Customer Gold Tokens', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1004000', 'Gold Token Transaction Fee Revenue', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1005000', 'Gold Token Rounding Gain Revenue', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null),
    ('T1006000', 'Gold Token Rounding Loss', 'token', 'token', true, 'admin', '2026-07-20 15:10:35.913+00', '2026-07-20 15:10:35.913', null);

-- 11. transaction_gl_mapping
-- Source: 20261014113534_seed_transaction_gl_mapping.sql
INSERT INTO public.transaction_gl_mapping (transaction_type, component_type, debit_gl, credit_gl, is_active, created_by, created_at, updated_at, updated_by) VALUES ('cash_transfer_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_sub_tx_reversal', 'transaction_fee', 'T1003000', 'T1004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement_reversal', 'principal', '2002000', '1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_settlement_reversal', 'principal', '1008000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('referral_commission_settlement', 'principal', '2007000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('government_tax_clearing', 'principal', '2003000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_reversal', 'trading_spread', '4009000', '2005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx_reversal', 'principal', 'T1003000', 'T1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_sub_tx_reversal', 'rounding_adjustment', 'T1006000', 'T1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer_reversal', 'government_tax', '2003000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment', 'loan_interest', '2002000', '4004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer', 'principal', 'T1003000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal_reversal', 'agent_commission', '2004000', '5001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal_reversal', 'principal', '1008000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment', 'payment_fee', '2002000', '4008000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal', 'withdrawal_fee', '2002000', '4002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer_reversal', 'principal', '2002000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_mint_reversal', 'principal', 'T1001000', 'T1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_withdrawal_reversal', 'principal', '1001000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_burn_reversal', 'principal', 'T1002000', 'T1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_commission_settlement_reversal', 'principal', '1002000', '2006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_interest_accrual_reversal', 'principal', '4004000', '1006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx_reversal', 'rounding_adjustment', 'T1006000', 'T1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_sub_tx', 'rounding_adjustment', 'T1005000', 'T1006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_inventory_sell_reversal', 'principal', '1004000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal', 'agent_commission', '5001000', '2004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_sub_tx', 'transaction_fee', 'T1004000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment_reversal', 'principal', '2002000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_deposit', 'principal', '2001000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_sub_tx_reversal', 'principal', 'T1002000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('external_funding', 'principal', '1001000', '3001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer_reversal', 'principal', 'T1003000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx_reversal', 'transaction_fee', 'T1003000', 'T1004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_reversal', 'liquidation_fee', '4005000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment_reversal', 'principal', '1005000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_funding', 'principal', '1003000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation', 'principal', '1002000', '1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'withdrawal_fee', '2002000', '4002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx', 'rounding_adjustment', 'T1005000', 'T1006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('treasury_funding', 'principal', '1002000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_settlement_reversal', 'principal', '1003000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer', 'principal', '2002000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit_reversal', 'deposit_fee', '4007000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'principal', '2002000', '1008000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer_reversal', 'transfer_fee', '4001000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_settlement_sub_tx', 'principal', '2001000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer', 'rounding_adjustment', 'T1005000', 'T1006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_reversal', 'loan_interest', '4004000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell', 'principal', '2005000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('treasury_funding_reversal', 'principal', '1001000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_mint', 'principal', 'T1002000', 'T1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_commission_settlement', 'principal', '2004000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement', 'principal', '1005000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_settlement_reversal', 'principal', '1007000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_settlement', 'principal', '1001000', '1007000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_burn', 'principal', 'T1001000', 'T1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal_reversal', 'principal', '2001000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal_reversal', 'government_tax', '2003000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_settlement', 'principal', '1002000', '1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment', 'principal', '2002000', '1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit_reversal', 'principal', '2002000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_deposit_reversal', 'principal', '2001000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_reversal', 'principal', '1005000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_funding_reversal', 'principal', '1001000', '1007000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy', 'trading_spread', '2002000', '4009000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_inventory_sell', 'principal', '1001000', '1004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_funding', 'principal', '1007000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_withdrawal', 'principal', '2002000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation_sub_tx', 'principal', 'T1003000', 'T1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_deposit_reversal', 'principal', '2002000', '1008000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_settlement', 'principal', '1001000', '1008000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy', 'principal', '2002000', '2005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_deposit', 'principal', '1008000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal_reversal', 'withdrawal_fee', '4002000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement', 'loan_fee', '1005000', '4003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment', 'principal', '2002000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit', 'deposit_fee', '1001000', '4007000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'agent_commission', '5001000', '2004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_sub_tx', 'principal', 'T1003000', 'T1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer', 'transaction_fee', 'T1004000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_repayment_reversal', 'loan_interest', '4004000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_deposit', 'principal', '1001000', '2001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer_reversal', 'transaction_fee', 'T1003000', 'T1004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_payment_reversal', 'payment_fee', '4008000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('merchant_commission_settlement', 'principal', '2006000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'government_tax', '2002000', '2003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null);
INSERT INTO public.transaction_gl_mapping (transaction_type, component_type, debit_gl, credit_gl, is_active, created_by, created_at, updated_at, updated_by) VALUES ('gold_token_buy_sub_tx_reversal', 'principal', 'T1002000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation', 'liquidation_fee', '1002000', '4005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal', 'principal', '2002000', '2001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('credit_agent_cash_withdrawal', 'credit_agent_receivable', '2002000', '1007000', true, 'admin', '2026-08-10 20:00:22.57289+00', '2026-08-10 20:00:22.573', null), ('gold_token_sell', 'trading_spread', '2005000', '4009000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit_reversal', 'rounding_adjustment', '4006000', '5002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_inventory_purchase', 'principal', '1004000', '1002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_deposit_reversal', 'principal', '2002000', '2001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_interest_accrual', 'principal', '1006000', '4004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('referral_commission_settlement_reversal', 'principal', '1002000', '2007000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx', 'transaction_fee', 'T1004000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_sub_tx', 'principal', 'T1002000', 'T1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_commission_settlement_reversal', 'principal', '1002000', '2004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer', 'government_tax', '2002000', '2003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_funding_reversal', 'principal', '1002000', '1003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_inventory_purchase_reversal', 'principal', '1002000', '1004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_disbursement_reversal', 'loan_fee', '4003000', '1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_withdrawal', 'government_tax', '2002000', '2003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation', 'loan_interest', '1002000', '4004000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer', 'transfer_fee', '2002000', '4001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('customer_direct_deposit', 'principal', '1001000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_transfer_reversal', 'rounding_adjustment', 'T1006000', 'T1005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_reversal', 'principal', '2005000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('external_funding_reversal', 'principal', '3001000', '1001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_sell_reversal', 'principal', '2002000', '2005000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('loan_liquidation', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('government_tax_clearing_reversal', 'principal', '1002000', '2003000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('cash_transfer', 'rounding_adjustment', '5002000', '4006000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('agent_settlement_sub_tx_reversal', 'principal', '1001000', '2001000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null), ('gold_token_buy_reversal', 'trading_spread', '4009000', '2002000', true, 'admin', '2026-07-20 15:10:37.103+00', '2026-07-20 15:10:37.103', null);

-- 12. transaction_type_document_number_prefix
-- Source: 20261014113924_seed_transaction_type_document_number_prefix.sql
INSERT INTO public.transaction_type_document_number_prefix (
    transaction_type, document_number
) VALUES
    ('credit_agent_cash_settlement', 'CASH-SETLMNT-CA'),
    ('credit_agent_cash_withdrawal', 'CASH-WTHDRL-CA'),
    ('credit_agent_cash_deposit', 'CASH-DEP-CA'),
    ('gold_token_transfer', 'GOLD-TRNF'),
    ('loan_disbursement', 'LOAN-ISSUE'),
    ('external_funding_reversal', 'REV-EXTERNAL-FUND'),
    ('gold_inventory_purchase', 'GOLD-INV-PURCHASE'),
    ('agent_deposit', 'AGENT-DEP'),
    ('credit_agent_funding', 'CREDIT-AGENT-FUND'),
    ('agent_funding', 'FUND-AGENT'),
    ('external_funding', 'EXTERNAL-FUND'),
    ('gold_token_burn', 'GOLD-BURNING'),
    ('customer_direct_deposit', 'DIR-CUST-DEP'),
    ('cash_withdrawal', 'CASH-WTHDRL'),
    ('gold_token_mint', 'GOLD-MINTING'),
    ('merchant_payment', 'MERCHANT-PAYMT'),
    ('gold_token_buy', 'GOLD-BUY'),
    ('loan_repayment', 'LOAN-PAYMT'),
    ('loan_interest_accrual', 'LOAN-INT'),
    ('agent_commission_settlement', 'SETTLE-COMM'),
    ('agent_funding_reversal', 'REV-FUND-AGENT'),
    ('loan_liquidation', 'LOAN-LIQ'),
    ('government_tax_clearing', 'SETTLE-GVT-TAX'),
    ('gold_token_sell', 'GOLD-SELL'),
    ('cash_transfer', 'CASH-TRNF'),
    ('gold_inventory_purchase_reversal', 'REV-GOLD-INV-PURCHASE'),
    ('agent_deposit_reversal', 'REV-AGENT-DEP'),
    ('cash_deposit', 'CASH-DEP');

-- 13. transaction_type_wallet_owner
-- Source: 20261014114151_seed_transaction_type_wallet_owner.sql
INSERT INTO public.transaction_type_wallet_owner (
    transaction_type, sender_wallet_owner, receiver_wallet_owner, audit_action_type
) VALUES
    ('credit_agent_cash_withdrawal', 'customer', 'agent', 'credit_agent_cash_withdrawn'),
    ('gold_token_transfer', 'customer', 'customer', 'token_transferred'),
    ('credit_agent_cash_deposit', 'agent', 'customer', 'credit_agent_cash_deposited'),
    ('loan_liquidation_sub_tx', 'customer', 'treasury', 'loan_liquidated'),
    ('gold_token_buy', 'customer', 'treasury', 'token_bought'),
    ('agent_commission_settlement', 'treasury', 'customer', 'agent_commission_settled'),
    ('gold_token_sell', 'treasury', 'customer', 'token_sold'),
    ('credit_agent_funding', 'treasury', 'agent', 'credit_agent_funded');

-- 14. transaction_v
-- Source: 20261014114341_seed_transaction_v.sql
INSERT INTO public.transaction_v (
    v, "time", created_by, created_at, updated_at, updated_by
) VALUES
    ('v0', 604800, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v1', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v2', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v3', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v4', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v5', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v6', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v7', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null),
    ('v8', 30, 'admin', '2026-07-20 15:10:42.378+00', '2026-07-20 15:10:42.378', null);

-- 15. aml_config
-- Source: 20261014093711_seed_aml_config.sql
INSERT INTO public.aml_config (
    period, fiscal_year, transaction_type, country_code, currency_code,
    threshold_amount, is_active, created_by, created_at, updated_at, updated_by
) VALUES
    (3, 2026, 'cash_transfer', 'zw', 'zig', '1000000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_withdrawal', 'zw', 'usd', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_withdrawal', 'zw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_deposit', 'zw', 'zar', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_transfer', 'zw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_withdrawal', 'zw', 'zig', '1000000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_deposit', 'zw', 'usd', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_withdrawal', 'zw', 'zar', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_transfer', 'zw', 'zar', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_deposit', 'bw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_deposit', 'zw', 'zig', '1000000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_transfer', 'bw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_withdrawal', 'bw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_transfer', 'zw', 'usd', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null),
    (3, 2026, 'cash_deposit', 'zw', 'bwp', '100000.000000', true, 'admin', '2026-07-20 15:10:44.026+00', '2026-07-20 15:10:44.026', null);

-- 16. government_tax_config
-- Source: 20261014100634_seed_government_tax_config.sql
INSERT INTO public.government_tax_config (
    period, fiscal_year, transaction_type, country_code,
    rate, fixed_amount, min_amount, max_amount, currency_code, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    (7, 2026, 'cash_withdrawal', 'zw', 2.00, null, null, null, 'usd', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'cash_withdrawal', 'zw', 2.00, null, null, null, 'zig', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'cash_withdrawal', 'zw', 2.00, null, null, null, 'zar', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'cash_withdrawal', 'zw', 2.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'cash_withdrawal', 'bw', 2.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'credit_agent_cash_withdrawal', 'zw', 2.00, null, null, null, 'usd', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'credit_agent_cash_withdrawal', 'zw', 2.00, null, null, null, 'zig', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'credit_agent_cash_withdrawal', 'zw', 2.00, null, null, null, 'zar', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'credit_agent_cash_withdrawal', 'zw', 2.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null),
    (7, 2026, 'credit_agent_cash_withdrawal', 'bw', 2.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:40.619+00', '2026-07-20 15:10:40.619', null);

-- 17. loan_config
-- Source: 20261014100916_seed_loan_config.sql
INSERT INTO public.loan_config (
    period, fiscal_year, config_type, country_code, rate, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    (7, 2026, 'loan_ltv', 'bw', 60.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'liquidation_ltv', 'bw', 75.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'loan_liquidation', 'bw', 70.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'liquidation_penalty', 'bw', 10.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'loan_interest', 'bw', 12.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'max_active_loans', 'bw', 4.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'loan_ltv', 'zw', 60.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'liquidation_ltv', 'zw', 75.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'loan_liquidation', 'zw', 70.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'liquidation_penalty', 'zw', 10.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'loan_interest', 'zw', 12.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null),
    (7, 2026, 'max_active_loans', 'zw', 4.00, true, 'admin', '2026-07-20 15:10:38.87+00', '2026-07-20 15:10:38.87', null);

-- 18. spread_config
-- Source: 20261014111817_seed_spread_config.sql
INSERT INTO public.spread_config (
    period, fiscal_year, asset, direction, rate, fixed_amount, is_active, created_at
) VALUES
    (7, 2026, 'gold', 'buy', 2.00, 0.000000, true, '2026-07-20 15:10:38.288'),
    (7, 2026, 'gold', 'sell', 2.00, 0.000000, true, '2026-07-20 15:10:38.288');

-- 19. transaction_type_fee_config
-- Source: 20261014114034_seed_transaction_type_fee_config.sql
INSERT INTO public.transaction_type_fee_config (
    fiscal_year, period, transaction_type, country_code, rate, currency_code,
    fixed_amount, min_amount, max_amount, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    (2026, 3, 'merchant_payment', 'zw', 0.00, 'usd', 0.010000, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'merchant_payment', 'zw', 0.00, 'bwp', 0.100000, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'merchant_payment', 'zw', 0.00, 'zig', 1.000000, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'merchant_payment', 'zw', 0.00, 'zar', 0.200000, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'merchant_payment', 'bw', 0.00, 'bwp', 0.100000, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy', 'bw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy', 'bw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy', 'zw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy', 'zw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell', 'bw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell', 'bw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell', 'zw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell', 'zw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy_sub_tx', 'bw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy_sub_tx', 'bw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy_sub_tx', 'zw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_buy_sub_tx', 'zw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell_sub_tx', 'bw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell_sub_tx', 'bw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell_sub_tx', 'zw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_sell_sub_tx', 'zw', 0.50, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_transfer', 'bw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'gold_token_transfer', 'zw', 0.50, 'gold', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_transfer', 'zw', 1.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_transfer', 'zw', 1.00, 'zar', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_transfer', 'zw', 1.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_transfer', 'zw', 1.00, 'zig', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_transfer', 'bw', 2.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_withdrawal', 'zw', 2.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_withdrawal', 'zw', 2.00, 'zar', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_withdrawal', 'zw', 2.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_withdrawal', 'zw', 2.00, 'zig', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'cash_withdrawal', 'bw', 2.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'credit_agent_cash_withdrawal', 'zw', 2.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'credit_agent_cash_withdrawal', 'zw', 2.00, 'zar', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'credit_agent_cash_withdrawal', 'zw', 2.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'credit_agent_cash_withdrawal', 'zw', 2.00, 'zig', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'credit_agent_cash_withdrawal', 'bw', 2.00, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'loan_disbursement', 'bw', 1.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'loan_disbursement', 'zw', 1.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'loan_liquidation', 'bw', 1.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'loan_liquidation', 'zw', 1.00, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'customer_direct_deposit', 'zw', 1.20, 'usd', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'customer_direct_deposit', 'zw', 1.20, 'zig', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'customer_direct_deposit', 'zw', 1.20, 'bwp', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'customer_direct_deposit', 'zw', 1.20, 'zar', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null),
    (2026, 3, 'customer_direct_deposit', 'bw', 1.20, 'zar', null, null, null, true, 'admin', '2026-07-20 15:10:37.701+00', '2026-07-20 15:10:37.701', null);

-- Agent fee splitting: supplied 25% shares; fiscal fields are audit tags.
INSERT INTO public.agent_fee_splitting_config (id,period,fiscal_year,transaction_type,country_code,currency_code,rate,is_active,created_by,created_at,updated_at,updated_by) VALUES
    ('0aa86639-097b-4d1c-8f12-fd0bf7db999f',7,2026,'cash_withdrawal','zw','zig',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('0f5ced02-bd8e-4d55-adb7-9f2534a45942',7,2026,'cash_withdrawal','zw','zar',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('22200edb-8698-4dbb-b0a2-28e361510547',7,2026,'credit_agent_cash_withdrawal','zw','zar',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('2221dca9-db11-47af-ba17-0d3e7c8cd7b3',7,2026,'cash_withdrawal','bw','bwp',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('4e3e7b77-8ed7-4494-b8e9-1a0e92ffe74c',7,2026,'cash_withdrawal','zw','bwp',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('4f13dde1-3a33-4dac-83a3-ffa3637bf352',7,2026,'cash_withdrawal','zw','usd',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('5b15ab9a-cc36-4d2d-b26d-820664327ec6',7,2026,'credit_agent_cash_withdrawal','zw','zig',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('cc666ae5-45d4-477f-9b84-182a8adb3e4b',7,2026,'credit_agent_cash_withdrawal','zw','usd',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('e1244464-4650-4593-94bf-4621c210aaa5',7,2026,'credit_agent_cash_withdrawal','zw','bwp',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null),
    ('eb1ee380-5d64-438f-84e8-24dd610f76c5',7,2026,'credit_agent_cash_withdrawal','bw','bwp',25.00,true,'admin','2026-07-20 15:10:39.453+00','2026-07-20 15:10:39.453',null);

-- 20. merchant_fee_splitting_config
-- Source: 20261014110728_seed_merchant_fee_splitting_config.sql
INSERT INTO public.merchant_fee_splitting_config (
    period, fiscal_year, transaction_type, country_code, currency_code,
    merchant_rate, company_rate, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    (7, 2026, 'merchant_payment', 'zw', 'zar', 45.00, 50.00, true, 'admin', '2026-07-20 15:10:40.036+00', '2026-07-20 15:10:40.036', null),
    (7, 2026, 'merchant_payment', 'zw', 'zig', 45.00, 50.00, true, 'admin', '2026-07-20 15:10:40.036+00', '2026-07-20 15:10:40.036', null),
    (7, 2026, 'merchant_payment', 'zw', 'bwp', 45.00, 50.00, true, 'admin', '2026-07-20 15:10:40.036+00', '2026-07-20 15:10:40.036', null),
    (7, 2026, 'merchant_payment', 'bw', 'bwp', 45.00, 50.00, true, 'admin', '2026-07-20 15:10:40.036+00', '2026-07-20 15:10:40.036', null),
    (7, 2026, 'merchant_payment', 'zw', 'usd', 45.00, 50.00, true, 'admin', '2026-07-20 15:10:40.036+00', '2026-07-20 15:10:40.036', null);

-- 21. referral_earnings_config
-- Source: 20261014111655_seed_referral_earnings_config.sql
INSERT INTO public.referral_earnings_config (
    period, fiscal_year, country_code, transaction_type, rate,
    fixed_amount, min_amount, max_amount, currency_code, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    (7, 2026, 'zw', 'cash_transfer', 5.00, null, null, null, 'usd', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'zw', 'merchant_payment', 5.00, null, null, null, 'usd', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'zw', 'merchant_payment', 5.00, null, null, null, 'zig', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'zw', 'cash_transfer', 5.00, null, null, null, 'zig', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'bw', 'cash_transfer', 5.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'bw', 'merchant_payment', 5.00, null, null, null, 'bwp', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'zw', 'cash_withdrawal', 5.00, null, null, null, 'usd', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null),
    (7, 2026, 'zw', 'cash_withdrawal', 5.00, null, null, null, 'zig', true, 'admin', '2026-07-20 15:10:41.203+00', '2026-07-20 15:10:41.203', null);

-- 22. maximum_tap_payment_amount_config
-- Source: 20261014110558_seed_maximum_tap_payment_amount_config.sql
INSERT INTO public.maximum_tap_payment_amount_config (
    country_code, currency_code, max_amount, is_active,
    created_by, created_at, updated_at, updated_by
) VALUES
    ('zw', 'zig', 500.000000, true, 'admin', '2026-07-22 17:23:26.861+00', '2026-07-22 17:23:26.861', null),
    ('zw', 'bwp', 50.000000, true, 'admin', '2026-07-22 17:23:26.861+00', '2026-07-22 17:23:26.861', null),
    ('zw', 'zar', 50.000000, true, 'admin', '2026-07-22 17:23:26.861+00', '2026-07-22 17:23:26.861', null),
    ('zw', 'usd', 5.000000, true, 'admin', '2026-07-22 17:23:26.861+00', '2026-07-22 17:23:26.861', null);

-- 23. financial_badge
-- Source: 20261014095223_seed_financial_badge.sql
INSERT INTO public.financial_badge (
    code, behavior, metric, level, threshold_usd,
    name, description, is_active, created_at, updated_at
) VALUES
    ('SAVER_1', 'saver', 'saving', 1, 1.000000, 'Saver 1', 'Easy milestone (level 1 of 25): Saved at least USD 1 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_5', 'saver', 'saving', 2, 5.000000, 'Saver 5', 'Easy milestone (level 2 of 25): Saved at least USD 5 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_10', 'saver', 'saving', 3, 10.000000, 'Saver 10', 'Easy milestone (level 3 of 25): Saved at least USD 10 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_20', 'saver', 'saving', 4, 20.000000, 'Saver 20', 'Easy milestone (level 4 of 25): Saved at least USD 20 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_50', 'saver', 'saving', 5, 50.000000, 'Saver 50', 'Easy milestone (level 5 of 25): Saved at least USD 50 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_100', 'saver', 'saving', 6, 100.000000, 'Saver 100', 'Moderate milestone (level 6 of 25): Saved at least USD 100 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_200', 'saver', 'saving', 7, 200.000000, 'Saver 200', 'Moderate milestone (level 7 of 25): Saved at least USD 200 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_500', 'saver', 'saving', 8, 500.000000, 'Saver 500', 'Moderate milestone (level 8 of 25): Saved at least USD 500 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_1000', 'saver', 'saving', 9, 1000.000000, 'Saver 1,000', 'Moderate milestone (level 9 of 25): Saved at least USD 1,000 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_2000', 'saver', 'saving', 10, 2000.000000, 'Saver 2,000', 'Moderate milestone (level 10 of 25): Saved at least USD 2,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_5000', 'saver', 'saving', 11, 5000.000000, 'Saver 5,000', 'Hard milestone (level 11 of 25): Saved at least USD 5,000 equivalent.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SAVER_10000', 'saver', 'saving', 12, 10000.000000, 'Saver 10,000', 'Hard milestone (level 12 of 25): Saved at least USD 10,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_25000', 'saver', 'saving', 13, 25000.000000, 'Saver 25,000', 'Hard milestone (level 13 of 25): Saved at least USD 25,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_50000', 'saver', 'saving', 14, 50000.000000, 'Saver 50,000', 'Hard milestone (level 14 of 25): Saved at least USD 50,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_100000', 'saver', 'saving', 15, 100000.000000, 'Saver 100,000', 'Hard milestone (level 15 of 25): Saved at least USD 100,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_250000', 'saver', 'saving', 16, 250000.000000, 'Saver 250,000', 'Very hard milestone (level 16 of 25): Saved at least USD 250,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_500000', 'saver', 'saving', 17, 500000.000000, 'Saver 500,000', 'Very hard milestone (level 17 of 25): Saved at least USD 500,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_1000000', 'saver', 'saving', 18, 1000000.000000, 'Saver 1,000,000', 'Very hard milestone (level 18 of 25): Saved at least USD 1,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_2000000', 'saver', 'saving', 19, 2000000.000000, 'Saver 2,000,000', 'Very hard milestone (level 19 of 25): Saved at least USD 2,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_5000000', 'saver', 'saving', 20, 5000000.000000, 'Saver 5,000,000', 'Very hard milestone (level 20 of 25): Saved at least USD 5,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_10000000', 'saver', 'saving', 21, 10000000.000000, 'Saver 10,000,000', 'Extremely hard milestone (level 21 of 25): Saved at least USD 10,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_25000000', 'saver', 'saving', 22, 25000000.000000, 'Saver 25,000,000', 'Extremely hard milestone (level 22 of 25): Saved at least USD 25,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_50000000', 'saver', 'saving', 23, 50000000.000000, 'Saver 50,000,000', 'Extremely hard milestone (level 23 of 25): Saved at least USD 50,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_100000000', 'saver', 'saving', 24, 100000000.000000, 'Saver 100,000,000', 'Extremely hard milestone (level 24 of 25): Saved at least USD 100,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SAVER_1000000000', 'saver', 'saving', 25, 1000000000.000000, 'Saver 1,000,000,000', 'Extremely hard milestone (level 25 of 25): Saved at least USD 1,000,000,000 equivalent.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_1', 'shopper', 'spending', 1, 1.000000, 'Shopper 1', 'Easy milestone (level 1 of 25): Spent at least USD 1 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_5', 'shopper', 'spending', 2, 5.000000, 'Shopper 5', 'Easy milestone (level 2 of 25): Spent at least USD 5 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_10', 'shopper', 'spending', 3, 10.000000, 'Shopper 10', 'Easy milestone (level 3 of 25): Spent at least USD 10 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_20', 'shopper', 'spending', 4, 20.000000, 'Shopper 20', 'Easy milestone (level 4 of 25): Spent at least USD 20 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_50', 'shopper', 'spending', 5, 50.000000, 'Shopper 50', 'Easy milestone (level 5 of 25): Spent at least USD 50 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_100', 'shopper', 'spending', 6, 100.000000, 'Shopper 100', 'Moderate milestone (level 6 of 25): Spent at least USD 100 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_200', 'shopper', 'spending', 7, 200.000000, 'Shopper 200', 'Moderate milestone (level 7 of 25): Spent at least USD 200 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_500', 'shopper', 'spending', 8, 500.000000, 'Shopper 500', 'Moderate milestone (level 8 of 25): Spent at least USD 500 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_1000', 'shopper', 'spending', 9, 1000.000000, 'Shopper 1,000', 'Moderate milestone (level 9 of 25): Spent at least USD 1,000 equivalent through merchant payments.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('SHOPPER_2000', 'shopper', 'spending', 10, 2000.000000, 'Shopper 2,000', 'Moderate milestone (level 10 of 25): Spent at least USD 2,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_5000', 'shopper', 'spending', 11, 5000.000000, 'Shopper 5,000', 'Hard milestone (level 11 of 25): Spent at least USD 5,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_10000', 'shopper', 'spending', 12, 10000.000000, 'Shopper 10,000', 'Hard milestone (level 12 of 25): Spent at least USD 10,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_25000', 'shopper', 'spending', 13, 25000.000000, 'Shopper 25,000', 'Hard milestone (level 13 of 25): Spent at least USD 25,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_50000', 'shopper', 'spending', 14, 50000.000000, 'Shopper 50,000', 'Hard milestone (level 14 of 25): Spent at least USD 50,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_100000', 'shopper', 'spending', 15, 100000.000000, 'Shopper 100,000', 'Hard milestone (level 15 of 25): Spent at least USD 100,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_250000', 'shopper', 'spending', 16, 250000.000000, 'Shopper 250,000', 'Very hard milestone (level 16 of 25): Spent at least USD 250,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_500000', 'shopper', 'spending', 17, 500000.000000, 'Shopper 500,000', 'Very hard milestone (level 17 of 25): Spent at least USD 500,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_1000000', 'shopper', 'spending', 18, 1000000.000000, 'Shopper 1,000,000', 'Very hard milestone (level 18 of 25): Spent at least USD 1,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_2000000', 'shopper', 'spending', 19, 2000000.000000, 'Shopper 2,000,000', 'Very hard milestone (level 19 of 25): Spent at least USD 2,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_5000000', 'shopper', 'spending', 20, 5000000.000000, 'Shopper 5,000,000', 'Very hard milestone (level 20 of 25): Spent at least USD 5,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_10000000', 'shopper', 'spending', 21, 10000000.000000, 'Shopper 10,000,000', 'Extremely hard milestone (level 21 of 25): Spent at least USD 10,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_25000000', 'shopper', 'spending', 22, 25000000.000000, 'Shopper 25,000,000', 'Extremely hard milestone (level 22 of 25): Spent at least USD 25,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_50000000', 'shopper', 'spending', 23, 50000000.000000, 'Shopper 50,000,000', 'Extremely hard milestone (level 23 of 25): Spent at least USD 50,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_100000000', 'shopper', 'spending', 24, 100000000.000000, 'Shopper 100,000,000', 'Extremely hard milestone (level 24 of 25): Spent at least USD 100,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('SHOPPER_1000000000', 'shopper', 'spending', 25, 1000000000.000000, 'Shopper 1,000,000,000', 'Extremely hard milestone (level 25 of 25): Spent at least USD 1,000,000,000 equivalent through merchant payments.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_1', 'investor', 'investment', 1, 1.000000, 'Investor 1', 'Easy milestone (level 1 of 25): Invested at least USD 1 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_5', 'investor', 'investment', 2, 5.000000, 'Investor 5', 'Easy milestone (level 2 of 25): Invested at least USD 5 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_10', 'investor', 'investment', 3, 10.000000, 'Investor 10', 'Easy milestone (level 3 of 25): Invested at least USD 10 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_20', 'investor', 'investment', 4, 20.000000, 'Investor 20', 'Easy milestone (level 4 of 25): Invested at least USD 20 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_50', 'investor', 'investment', 5, 50.000000, 'Investor 50', 'Easy milestone (level 5 of 25): Invested at least USD 50 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_100', 'investor', 'investment', 6, 100.000000, 'Investor 100', 'Moderate milestone (level 6 of 25): Invested at least USD 100 equivalent in gold.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('INVESTOR_200', 'investor', 'investment', 7, 200.000000, 'Investor 200', 'Moderate milestone (level 7 of 25): Invested at least USD 200 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_500', 'investor', 'investment', 8, 500.000000, 'Investor 500', 'Moderate milestone (level 8 of 25): Invested at least USD 500 equivalent in gold.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('INVESTOR_1000', 'investor', 'investment', 9, 1000.000000, 'Investor 1,000', 'Moderate milestone (level 9 of 25): Invested at least USD 1,000 equivalent in gold.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('INVESTOR_2000', 'investor', 'investment', 10, 2000.000000, 'Investor 2,000', 'Moderate milestone (level 10 of 25): Invested at least USD 2,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_5000', 'investor', 'investment', 11, 5000.000000, 'Investor 5,000', 'Hard milestone (level 11 of 25): Invested at least USD 5,000 equivalent in gold.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('INVESTOR_10000', 'investor', 'investment', 12, 10000.000000, 'Investor 10,000', 'Hard milestone (level 12 of 25): Invested at least USD 10,000 equivalent in gold.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('INVESTOR_25000', 'investor', 'investment', 13, 25000.000000, 'Investor 25,000', 'Hard milestone (level 13 of 25): Invested at least USD 25,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_50000', 'investor', 'investment', 14, 50000.000000, 'Investor 50,000', 'Hard milestone (level 14 of 25): Invested at least USD 50,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_100000', 'investor', 'investment', 15, 100000.000000, 'Investor 100,000', 'Hard milestone (level 15 of 25): Invested at least USD 100,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_250000', 'investor', 'investment', 16, 250000.000000, 'Investor 250,000', 'Very hard milestone (level 16 of 25): Invested at least USD 250,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_500000', 'investor', 'investment', 17, 500000.000000, 'Investor 500,000', 'Very hard milestone (level 17 of 25): Invested at least USD 500,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_1000000', 'investor', 'investment', 18, 1000000.000000, 'Investor 1,000,000', 'Very hard milestone (level 18 of 25): Invested at least USD 1,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_2000000', 'investor', 'investment', 19, 2000000.000000, 'Investor 2,000,000', 'Very hard milestone (level 19 of 25): Invested at least USD 2,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_5000000', 'investor', 'investment', 20, 5000000.000000, 'Investor 5,000,000', 'Very hard milestone (level 20 of 25): Invested at least USD 5,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_10000000', 'investor', 'investment', 21, 10000000.000000, 'Investor 10,000,000', 'Extremely hard milestone (level 21 of 25): Invested at least USD 10,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_25000000', 'investor', 'investment', 22, 25000000.000000, 'Investor 25,000,000', 'Extremely hard milestone (level 22 of 25): Invested at least USD 25,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_50000000', 'investor', 'investment', 23, 50000000.000000, 'Investor 50,000,000', 'Extremely hard milestone (level 23 of 25): Invested at least USD 50,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_100000000', 'investor', 'investment', 24, 100000000.000000, 'Investor 100,000,000', 'Extremely hard milestone (level 24 of 25): Invested at least USD 100,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INVESTOR_1000000000', 'investor', 'investment', 25, 1000000000.000000, 'Investor 1,000,000,000', 'Extremely hard milestone (level 25 of 25): Invested at least USD 1,000,000,000 equivalent in gold.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_1', 'borrower', 'borrowing', 1, 1.000000, 'Borrower 1', 'Easy milestone (level 1 of 25): Borrowed at least USD 1 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_5', 'borrower', 'borrowing', 2, 5.000000, 'Borrower 5', 'Easy milestone (level 2 of 25): Borrowed at least USD 5 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_10', 'borrower', 'borrowing', 3, 10.000000, 'Borrower 10', 'Easy milestone (level 3 of 25): Borrowed at least USD 10 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_20', 'borrower', 'borrowing', 4, 20.000000, 'Borrower 20', 'Easy milestone (level 4 of 25): Borrowed at least USD 20 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_50', 'borrower', 'borrowing', 5, 50.000000, 'Borrower 50', 'Easy milestone (level 5 of 25): Borrowed at least USD 50 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_100', 'borrower', 'borrowing', 6, 100.000000, 'Borrower 100', 'Moderate milestone (level 6 of 25): Borrowed at least USD 100 equivalent while accessing liquidity.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('BORROWER_200', 'borrower', 'borrowing', 7, 200.000000, 'Borrower 200', 'Moderate milestone (level 7 of 25): Borrowed at least USD 200 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_500', 'borrower', 'borrowing', 8, 500.000000, 'Borrower 500', 'Moderate milestone (level 8 of 25): Borrowed at least USD 500 equivalent while accessing liquidity.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('BORROWER_1000', 'borrower', 'borrowing', 9, 1000.000000, 'Borrower 1,000', 'Moderate milestone (level 9 of 25): Borrowed at least USD 1,000 equivalent while accessing liquidity.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('BORROWER_2000', 'borrower', 'borrowing', 10, 2000.000000, 'Borrower 2,000', 'Moderate milestone (level 10 of 25): Borrowed at least USD 2,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_5000', 'borrower', 'borrowing', 11, 5000.000000, 'Borrower 5,000', 'Hard milestone (level 11 of 25): Borrowed at least USD 5,000 equivalent while accessing liquidity.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('BORROWER_10000', 'borrower', 'borrowing', 12, 10000.000000, 'Borrower 10,000', 'Hard milestone (level 12 of 25): Borrowed at least USD 10,000 equivalent while accessing liquidity.', true, '2026-08-29 09:57:07.895373+00', '2026-08-29 09:57:07.895373+00'),
    ('BORROWER_25000', 'borrower', 'borrowing', 13, 25000.000000, 'Borrower 25,000', 'Hard milestone (level 13 of 25): Borrowed at least USD 25,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_50000', 'borrower', 'borrowing', 14, 50000.000000, 'Borrower 50,000', 'Hard milestone (level 14 of 25): Borrowed at least USD 50,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_100000', 'borrower', 'borrowing', 15, 100000.000000, 'Borrower 100,000', 'Hard milestone (level 15 of 25): Borrowed at least USD 100,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_250000', 'borrower', 'borrowing', 16, 250000.000000, 'Borrower 250,000', 'Very hard milestone (level 16 of 25): Borrowed at least USD 250,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_500000', 'borrower', 'borrowing', 17, 500000.000000, 'Borrower 500,000', 'Very hard milestone (level 17 of 25): Borrowed at least USD 500,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_1000000', 'borrower', 'borrowing', 18, 1000000.000000, 'Borrower 1,000,000', 'Very hard milestone (level 18 of 25): Borrowed at least USD 1,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_2000000', 'borrower', 'borrowing', 19, 2000000.000000, 'Borrower 2,000,000', 'Very hard milestone (level 19 of 25): Borrowed at least USD 2,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_5000000', 'borrower', 'borrowing', 20, 5000000.000000, 'Borrower 5,000,000', 'Very hard milestone (level 20 of 25): Borrowed at least USD 5,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_10000000', 'borrower', 'borrowing', 21, 10000000.000000, 'Borrower 10,000,000', 'Extremely hard milestone (level 21 of 25): Borrowed at least USD 10,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_25000000', 'borrower', 'borrowing', 22, 25000000.000000, 'Borrower 25,000,000', 'Extremely hard milestone (level 22 of 25): Borrowed at least USD 25,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_50000000', 'borrower', 'borrowing', 23, 50000000.000000, 'Borrower 50,000,000', 'Extremely hard milestone (level 23 of 25): Borrowed at least USD 50,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_100000000', 'borrower', 'borrowing', 24, 100000000.000000, 'Borrower 100,000,000', 'Extremely hard milestone (level 24 of 25): Borrowed at least USD 100,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BORROWER_1000000000', 'borrower', 'borrowing', 25, 1000000000.000000, 'Borrower 1,000,000,000', 'Extremely hard milestone (level 25 of 25): Borrowed at least USD 1,000,000,000 equivalent while accessing liquidity.', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- 24. financial_behavior_rule
-- Source: 20261014095757_seed_financial_behavior_rule.sql
INSERT INTO public.financial_behavior_rule (
    code, behavior, name, description, priority, conditions,
    is_active, created_at, updated_at
) VALUES
    ('SAVER_V1', 'saver', 'Saver', 'Saving is the dominant qualifying financial behaviour.', 30, '{"metric":"saving","rule_type":"dominant","minimum_percentage":30}', true, '2026-08-29 10:11:55.117694+00', '2026-08-29 10:11:55.117694+00'),
    ('BORROWER_V1', 'borrower', 'Borrower', 'Loan repayment is the dominant qualifying financial behaviour.', 40, '{"metric":"repayment","rule_type":"dominant","minimum_percentage":30}', true, '2026-08-29 10:11:55.117694+00', '2026-08-31 08:50:50.169452+00'),
    ('NEUTRAL_V1', 'neutral', 'Neutral', 'There is not enough qualifying activity to classify a financial behaviour.', 1, '{"rule_type":"zero_activity"}', true, '2026-08-29 10:11:55.117694+00', '2026-08-29 10:11:55.117694+00'),
    ('SHOPPER_V1', 'shopper', 'Shopper', 'Merchant spending is the dominant qualifying financial behaviour.', 50, '{"metric":"spending","rule_type":"dominant","minimum_percentage":30}', true, '2026-08-29 10:11:55.117694+00', '2026-08-29 10:11:55.117694+00'),
    ('INVESTOR_V1', 'investor', 'Investor', 'Investment is the dominant qualifying financial behaviour.', 20, '{"metric":"investment","rule_type":"dominant","minimum_percentage":30}', true, '2026-08-29 10:11:55.117694+00', '2026-08-29 10:11:55.117694+00'),
    ('BALANCED_V1', 'balanced', 'Balanced', 'The two strongest financial behaviours are close enough that there is no clear dominant behaviour.', 10, '{"rule_type":"lead_gap","maximum_lead_percentage":10}', true, '2026-08-29 10:11:55.117694+00', '2026-08-29 10:11:55.117694+00');

UPDATE public.financial_badge
SET
    metric = 'repayment',
    description = replace(
        description,
        'Borrowed at least',
        'Repaid at least'
    ),
    updated_at = CURRENT_TIMESTAMP
WHERE behavior = 'borrower'
  AND metric = 'borrowing';

-- 25. loyalty_program_config
-- Source: 20261014105033_seed_loyalty_program_config.sql
INSERT INTO public.loyalty_program_config (
    country_code, daily_points_cap, monthly_points_cap,
    points_expiry_months, is_active, created_at, updated_at
) VALUES (
    null, 500, 5000, null, true,
    '2026-08-26 15:28:53.078261+00',
    '2026-08-26 15:28:53.078261+00'
);

-- 26. loyalty_level
-- Source: 20261014101307_seed_loyalty_level.sql
INSERT INTO public.loyalty_level (
    level_code, name, min_tier_points, max_tier_points, sort_order,
    benefits, is_active, created_at, updated_at
) VALUES
    ('bronze', 'Bronze', 0, 4999, 1, '{}', true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('silver', 'Silver', 5000, 9999, 2, '{}', true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('gold', 'Gold', 10000, 14999, 3, '{}', true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('platinum', 'Platinum', 15000, 19999, 4, '{}', true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('diamond', 'Diamond', 20000, null, 5, '{}', true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00');

-- 27. loyalty_rule
-- Source: 20261014105450_seed_loyalty_rule.sql
INSERT INTO public.loyalty_rule (
    event_type, rule_code, rule_name, calculation_type,
    fixed_points, points_per_usd, min_amount_usd, max_amount_usd,
    min_points_per_event, max_points_per_event, daily_cap_points,
    monthly_cap_points, country_code, currency_code, multiplier, priority,
    condition_config, valid_from, valid_until, is_active, created_at, updated_at
) VALUES
    ('merchant_payment', 'merchant_payment_standard', 'Successful merchant payment', 'fixed_plus_amount', 5.000000, 0.500000, null, null, 5, 100, 300, null, null, null, 1.0000, 100, '{"beneficiary":"customer","exclude_merchant_self_payment":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('referral_completed', 'referral_completed_standard', 'Qualified referral completed', 'fixed', 250.000000, null, null, null, 250, 250, null, 2000, null, null, 1.0000, 100, '{"requires_referred_kyc":true,"requires_first_successful_transaction":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('merchant_payment_fee_contribution', 'merchant_payment_fee_contribution_standard', 'Optional merchant-payment support contribution', 'fixed', 5.000000, null, null, null, 5, 5, 100, 500, null, null, 1.0000, 100, '{"beneficiary":"payer","requires_payment_fee_contribution":true}', null, null, true, '2026-08-28 13:54:45.856407+00', '2026-08-28 13:54:45.856407+00'),
    ('loan_repayment_on_time_bonus', 'loan_repayment_on_time_bonus_standard', 'On-time loan repayment bonus', 'fixed', 50.000000, null, null, null, 50, 50, null, null, null, null, 1.0000, 100, '{"requires_on_or_before_due_date":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('gold_token_sell', 'gold_token_sell_standard', 'Gold sale - points disabled', 'fixed_plus_amount', 2.000000, 0.250000, null, null, 2, 50, null, null, null, null, 1.0000, 100, '{"campaign_multiplier_allowed":false}', null, null, false, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:10:24.453194+00'),
    ('loan_repayment', 'loan_repayment_standard', 'Successful voluntary loan repayment', 'amount_based', null, 1.000000, null, null, null, 250, null, null, null, null, 0.7500, 100, '{"exclude_reversal":true,"exclude_liquidation":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 18:50:25.09051+00'),
    ('gold_token_buy', 'gold_token_buy_standard', 'Successful Gold purchase', 'fixed_plus_amount', 5.000000, 1.250000, null, null, 5, 300, 500, null, null, null, 1.0000, 100, '{"amount_basis":"gross_fiat_before_fee","requires_completed_mint":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:22:58.132503+00'),
    ('user_transfer', 'user_transfer_standard', 'Successful user transfer', 'fixed_plus_amount', 2.000000, 0.250000, null, null, 2, 50, 150, null, null, null, 1.0000, 100, '{"beneficiary":"sender","exclude_self_transfer":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('user_deposit', 'user_deposit_standard', 'Successful user deposit', 'amount_based', null, 1.000000, null, null, 1, 200, null, null, null, null, 1.0000, 100, '{"exclude_test_transactions":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00'),
    ('kyc_completed', 'kyc_completed_standard', 'KYC completed', 'fixed', 100.000000, null, null, null, 100, 100, 100, 100, null, null, 1.0000, 100, '{"once_per_user":true}', null, null, true, '2026-08-26 15:28:53.078261+00', '2026-08-28 17:09:19.589255+00');

-- 28. loyalty_badge
-- Source: 20261014101100_seed_loyalty_badge.sql
INSERT INTO public.loyalty_badge (
    badge_code, name, description, category, criteria_type, event_type,
    target_value, icon_key, sort_order, criteria_config, is_secret, is_active,
    valid_from, valid_until, created_at, updated_at
) VALUES
    ('first_deposit', 'First Deposit', 'Easy milestone (level 1 of 25): Complete 1 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 1, 'account_balance_wallet', 101, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('deposit_2', 'Deposit 2', 'Easy milestone (level 2 of 25): Complete 2 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 2, 'account_balance_wallet', 102, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_3', 'Deposit 3', 'Easy milestone (level 3 of 25): Complete 3 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 3, 'account_balance_wallet', 103, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_5', 'Deposit 5', 'Easy milestone (level 4 of 25): Complete 5 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 5, 'account_balance_wallet', 104, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_10', 'Deposit 10', 'Easy milestone (level 5 of 25): Complete 10 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 10, 'account_balance_wallet', 105, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_20', 'Deposit 20', 'Moderate milestone (level 6 of 25): Complete 20 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 20, 'account_balance_wallet', 106, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_30', 'Deposit 30', 'Moderate milestone (level 7 of 25): Complete 30 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 30, 'account_balance_wallet', 107, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_50', 'Deposit 50', 'Moderate milestone (level 8 of 25): Complete 50 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 50, 'account_balance_wallet', 108, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_75', 'Deposit 75', 'Moderate milestone (level 9 of 25): Complete 75 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 75, 'account_balance_wallet', 109, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_100', 'Deposit 100', 'Moderate milestone (level 10 of 25): Complete 100 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 100, 'account_balance_wallet', 110, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_200', 'Deposit 200', 'Hard milestone (level 11 of 25): Complete 200 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 200, 'account_balance_wallet', 111, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_300', 'Deposit 300', 'Hard milestone (level 12 of 25): Complete 300 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 300, 'account_balance_wallet', 112, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_500', 'Deposit 500', 'Hard milestone (level 13 of 25): Complete 500 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 500, 'account_balance_wallet', 113, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_750', 'Deposit 750', 'Hard milestone (level 14 of 25): Complete 750 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 750, 'account_balance_wallet', 114, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_1000', 'Deposit 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 1000, 'account_balance_wallet', 115, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_2000', 'Deposit 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 2000, 'account_balance_wallet', 116, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_5000', 'Deposit 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 5000, 'account_balance_wallet', 117, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_10000', 'Deposit 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 10000, 'account_balance_wallet', 118, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_25000', 'Deposit 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 25000, 'account_balance_wallet', 119, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_50000', 'Deposit 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 50000, 'account_balance_wallet', 120, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_100000', 'Deposit 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 100000, 'account_balance_wallet', 121, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_250000', 'Deposit 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 250000, 'account_balance_wallet', 122, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_500000', 'Deposit 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 500000, 'account_balance_wallet', 123, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_1000000', 'Deposit 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 1000000, 'account_balance_wallet', 124, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('deposit_5000000', 'Deposit 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful wallet deposits.', 'wallet', 'event_count', 'user_deposit', 5000000, 'account_balance_wallet', 125, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('first_transfer', 'First Transfer', 'Easy milestone (level 1 of 25): Complete 1 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 1, 'swap_horiz', 201, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('transfer_2', 'Transfer 2', 'Easy milestone (level 2 of 25): Complete 2 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 2, 'swap_horiz', 202, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_3', 'Transfer 3', 'Easy milestone (level 3 of 25): Complete 3 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 3, 'swap_horiz', 203, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_5', 'Transfer 5', 'Easy milestone (level 4 of 25): Complete 5 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 5, 'swap_horiz', 204, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_10', 'Transfer 10', 'Easy milestone (level 5 of 25): Complete 10 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 10, 'swap_horiz', 205, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_20', 'Transfer 20', 'Moderate milestone (level 6 of 25): Complete 20 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 20, 'swap_horiz', 206, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_30', 'Transfer 30', 'Moderate milestone (level 7 of 25): Complete 30 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 30, 'swap_horiz', 207, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_50', 'Transfer 50', 'Moderate milestone (level 8 of 25): Complete 50 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 50, 'swap_horiz', 208, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_75', 'Transfer 75', 'Moderate milestone (level 9 of 25): Complete 75 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 75, 'swap_horiz', 209, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_100', 'Transfer 100', 'Moderate milestone (level 10 of 25): Complete 100 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 100, 'swap_horiz', 210, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_200', 'Transfer 200', 'Hard milestone (level 11 of 25): Complete 200 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 200, 'swap_horiz', 211, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_300', 'Transfer 300', 'Hard milestone (level 12 of 25): Complete 300 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 300, 'swap_horiz', 212, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_500', 'Transfer 500', 'Hard milestone (level 13 of 25): Complete 500 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 500, 'swap_horiz', 213, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_750', 'Transfer 750', 'Hard milestone (level 14 of 25): Complete 750 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 750, 'swap_horiz', 214, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_1000', 'Transfer 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 1000, 'swap_horiz', 215, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_2000', 'Transfer 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 2000, 'swap_horiz', 216, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_5000', 'Transfer 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 5000, 'swap_horiz', 217, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_10000', 'Transfer 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 10000, 'swap_horiz', 218, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_25000', 'Transfer 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 25000, 'swap_horiz', 219, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_50000', 'Transfer 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 50000, 'swap_horiz', 220, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_100000', 'Transfer 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 100000, 'swap_horiz', 221, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_250000', 'Transfer 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 250000, 'swap_horiz', 222, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_500000', 'Transfer 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 500000, 'swap_horiz', 223, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_1000000', 'Transfer 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 1000000, 'swap_horiz', 224, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('transfer_5000000', 'Transfer 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful wallet transfers.', 'wallet', 'event_count', 'user_transfer', 5000000, 'swap_horiz', 225, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('first_gold_purchase', 'First Gold Purchase', 'Easy milestone (level 1 of 25): Complete 1 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 1, 'diamond', 301, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('gold_purchase_2', 'Gold Purchase 2', 'Easy milestone (level 2 of 25): Complete 2 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 2, 'diamond', 302, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_3', 'Gold Purchase 3', 'Easy milestone (level 3 of 25): Complete 3 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 3, 'diamond', 303, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_5', 'Gold Purchase 5', 'Easy milestone (level 4 of 25): Complete 5 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 5, 'diamond', 304, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_saver', 'Gold Saver', 'Easy milestone (level 5 of 25): Complete 10 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 10, 'savings', 305, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('gold_purchase_20', 'Gold Purchase 20', 'Moderate milestone (level 6 of 25): Complete 20 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 20, 'diamond', 306, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_30', 'Gold Purchase 30', 'Moderate milestone (level 7 of 25): Complete 30 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 30, 'diamond', 307, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_50', 'Gold Purchase 50', 'Moderate milestone (level 8 of 25): Complete 50 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 50, 'diamond', 308, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_75', 'Gold Purchase 75', 'Moderate milestone (level 9 of 25): Complete 75 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 75, 'diamond', 309, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_100', 'Gold Purchase 100', 'Moderate milestone (level 10 of 25): Complete 100 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 100, 'diamond', 310, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_200', 'Gold Purchase 200', 'Hard milestone (level 11 of 25): Complete 200 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 200, 'diamond', 311, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_300', 'Gold Purchase 300', 'Hard milestone (level 12 of 25): Complete 300 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 300, 'diamond', 312, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_500', 'Gold Purchase 500', 'Hard milestone (level 13 of 25): Complete 500 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 500, 'diamond', 313, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_750', 'Gold Purchase 750', 'Hard milestone (level 14 of 25): Complete 750 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 750, 'diamond', 314, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_1000', 'Gold Purchase 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 1000, 'diamond', 315, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_2000', 'Gold Purchase 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 2000, 'diamond', 316, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_5000', 'Gold Purchase 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 5000, 'diamond', 317, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_10000', 'Gold Purchase 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 10000, 'diamond', 318, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_25000', 'Gold Purchase 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 25000, 'diamond', 319, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_50000', 'Gold Purchase 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 50000, 'diamond', 320, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_100000', 'Gold Purchase 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 100000, 'diamond', 321, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_250000', 'Gold Purchase 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 250000, 'diamond', 322, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_500000', 'Gold Purchase 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 500000, 'diamond', 323, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_1000000', 'Gold Purchase 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 1000000, 'diamond', 324, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('gold_purchase_5000000', 'Gold Purchase 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful Gold purchases.', 'gold', 'event_count', 'gold_token_buy', 5000000, 'diamond', 325, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('first_merchant_payment', 'First Merchant Payment', 'Easy milestone (level 1 of 25): Complete 1 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 1, 'storefront', 401, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('merchant_payment_2', 'Merchant Payment 2', 'Easy milestone (level 2 of 25): Complete 2 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 2, 'storefront', 402, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_3', 'Merchant Payment 3', 'Easy milestone (level 3 of 25): Complete 3 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 3, 'storefront', 403, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_5', 'Merchant Payment 5', 'Easy milestone (level 4 of 25): Complete 5 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 5, 'storefront', 404, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_10', 'Merchant Payment 10', 'Easy milestone (level 5 of 25): Complete 10 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 10, 'storefront', 405, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_20', 'Merchant Payment 20', 'Moderate milestone (level 6 of 25): Complete 20 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 20, 'storefront', 406, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_30', 'Merchant Payment 30', 'Moderate milestone (level 7 of 25): Complete 30 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 30, 'storefront', 407, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_50', 'Merchant Payment 50', 'Moderate milestone (level 8 of 25): Complete 50 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 50, 'storefront', 408, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_75', 'Merchant Payment 75', 'Moderate milestone (level 9 of 25): Complete 75 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 75, 'storefront', 409, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_100', 'Merchant Payment 100', 'Moderate milestone (level 10 of 25): Complete 100 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 100, 'storefront', 410, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_200', 'Merchant Payment 200', 'Hard milestone (level 11 of 25): Complete 200 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 200, 'storefront', 411, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_300', 'Merchant Payment 300', 'Hard milestone (level 12 of 25): Complete 300 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 300, 'storefront', 412, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_500', 'Merchant Payment 500', 'Hard milestone (level 13 of 25): Complete 500 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 500, 'storefront', 413, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_750', 'Merchant Payment 750', 'Hard milestone (level 14 of 25): Complete 750 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 750, 'storefront', 414, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_1000', 'Merchant Payment 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 1000, 'storefront', 415, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_2000', 'Merchant Payment 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 2000, 'storefront', 416, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_5000', 'Merchant Payment 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 5000, 'storefront', 417, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_10000', 'Merchant Payment 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 10000, 'storefront', 418, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_25000', 'Merchant Payment 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 25000, 'storefront', 419, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_50000', 'Merchant Payment 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 50000, 'storefront', 420, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_100000', 'Merchant Payment 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 100000, 'storefront', 421, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_250000', 'Merchant Payment 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 250000, 'storefront', 422, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_500000', 'Merchant Payment 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 500000, 'storefront', 423, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_1000000', 'Merchant Payment 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 1000000, 'storefront', 424, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('merchant_payment_5000000', 'Merchant Payment 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful merchant payments.', 'merchant', 'event_count', 'merchant_payment', 5000000, 'storefront', 425, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('responsible_borrower', 'Responsible Borrower', 'Easy milestone (level 1 of 25): Complete 1 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 1, 'verified', 501, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('repayment_2', 'Repayment 2', 'Easy milestone (level 2 of 25): Complete 2 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 2, 'verified', 502, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_3', 'Repayment 3', 'Easy milestone (level 3 of 25): Complete 3 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 3, 'verified', 503, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_5', 'Repayment 5', 'Easy milestone (level 4 of 25): Complete 5 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 5, 'verified', 504, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_10', 'Repayment 10', 'Easy milestone (level 5 of 25): Complete 10 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 10, 'verified', 505, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_20', 'Repayment 20', 'Moderate milestone (level 6 of 25): Complete 20 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 20, 'verified', 506, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_30', 'Repayment 30', 'Moderate milestone (level 7 of 25): Complete 30 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 30, 'verified', 507, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_50', 'Repayment 50', 'Moderate milestone (level 8 of 25): Complete 50 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 50, 'verified', 508, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_75', 'Repayment 75', 'Moderate milestone (level 9 of 25): Complete 75 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 75, 'verified', 509, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_100', 'Repayment 100', 'Moderate milestone (level 10 of 25): Complete 100 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 100, 'verified', 510, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_200', 'Repayment 200', 'Hard milestone (level 11 of 25): Complete 200 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 200, 'verified', 511, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_300', 'Repayment 300', 'Hard milestone (level 12 of 25): Complete 300 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 300, 'verified', 512, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_500', 'Repayment 500', 'Hard milestone (level 13 of 25): Complete 500 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 500, 'verified', 513, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_750', 'Repayment 750', 'Hard milestone (level 14 of 25): Complete 750 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 750, 'verified', 514, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_1000', 'Repayment 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 1000, 'verified', 515, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_2000', 'Repayment 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 2000, 'verified', 516, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_5000', 'Repayment 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 5000, 'verified', 517, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_10000', 'Repayment 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 10000, 'verified', 518, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_25000', 'Repayment 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 25000, 'verified', 519, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_50000', 'Repayment 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 50000, 'verified', 520, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_100000', 'Repayment 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 100000, 'verified', 521, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_250000', 'Repayment 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 250000, 'verified', 522, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_500000', 'Repayment 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 500000, 'verified', 523, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_1000000', 'Repayment 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 1000000, 'verified', 524, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('repayment_5000000', 'Repayment 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful loan repayments.', 'lending', 'event_count', 'loan_repayment', 5000000, 'verified', 525, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_1', 'Referral 1', 'Easy milestone (level 1 of 25): Complete 1 successful customer referrals.', 'community', 'event_count', 'referral_completed', 1, 'groups', 601, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_2', 'Referral 2', 'Easy milestone (level 2 of 25): Complete 2 successful customer referrals.', 'community', 'event_count', 'referral_completed', 2, 'groups', 602, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_3', 'Referral 3', 'Easy milestone (level 3 of 25): Complete 3 successful customer referrals.', 'community', 'event_count', 'referral_completed', 3, 'groups', 603, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_champion', 'Referral Champion', 'Easy milestone (level 4 of 25): Complete 5 successful customer referrals.', 'community', 'event_count', 'referral_completed', 5, 'groups', 604, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('referral_10', 'Referral 10', 'Easy milestone (level 5 of 25): Complete 10 successful customer referrals.', 'community', 'event_count', 'referral_completed', 10, 'groups', 605, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_20', 'Referral 20', 'Moderate milestone (level 6 of 25): Complete 20 successful customer referrals.', 'community', 'event_count', 'referral_completed', 20, 'groups', 606, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_30', 'Referral 30', 'Moderate milestone (level 7 of 25): Complete 30 successful customer referrals.', 'community', 'event_count', 'referral_completed', 30, 'groups', 607, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_50', 'Referral 50', 'Moderate milestone (level 8 of 25): Complete 50 successful customer referrals.', 'community', 'event_count', 'referral_completed', 50, 'groups', 608, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_75', 'Referral 75', 'Moderate milestone (level 9 of 25): Complete 75 successful customer referrals.', 'community', 'event_count', 'referral_completed', 75, 'groups', 609, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_100', 'Referral 100', 'Moderate milestone (level 10 of 25): Complete 100 successful customer referrals.', 'community', 'event_count', 'referral_completed', 100, 'groups', 610, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_200', 'Referral 200', 'Hard milestone (level 11 of 25): Complete 200 successful customer referrals.', 'community', 'event_count', 'referral_completed', 200, 'groups', 611, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_300', 'Referral 300', 'Hard milestone (level 12 of 25): Complete 300 successful customer referrals.', 'community', 'event_count', 'referral_completed', 300, 'groups', 612, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_500', 'Referral 500', 'Hard milestone (level 13 of 25): Complete 500 successful customer referrals.', 'community', 'event_count', 'referral_completed', 500, 'groups', 613, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_750', 'Referral 750', 'Hard milestone (level 14 of 25): Complete 750 successful customer referrals.', 'community', 'event_count', 'referral_completed', 750, 'groups', 614, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_1000', 'Referral 1,000', 'Hard milestone (level 15 of 25): Complete 1,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 1000, 'groups', 615, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_2000', 'Referral 2,000', 'Very hard milestone (level 16 of 25): Complete 2,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 2000, 'groups', 616, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_5000', 'Referral 5,000', 'Very hard milestone (level 17 of 25): Complete 5,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 5000, 'groups', 617, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_10000', 'Referral 10,000', 'Very hard milestone (level 18 of 25): Complete 10,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 10000, 'groups', 618, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_25000', 'Referral 25,000', 'Very hard milestone (level 19 of 25): Complete 25,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 25000, 'groups', 619, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_50000', 'Referral 50,000', 'Very hard milestone (level 20 of 25): Complete 50,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 50000, 'groups', 620, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_100000', 'Referral 100,000', 'Extremely hard milestone (level 21 of 25): Complete 100,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 100000, 'groups', 621, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_250000', 'Referral 250,000', 'Extremely hard milestone (level 22 of 25): Complete 250,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 250000, 'groups', 622, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_500000', 'Referral 500,000', 'Extremely hard milestone (level 23 of 25): Complete 500,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 500000, 'groups', 623, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_1000000', 'Referral 1,000,000', 'Extremely hard milestone (level 24 of 25): Complete 1,000,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 1000000, 'groups', 624, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('referral_5000000', 'Referral 5,000,000', 'Extremely hard milestone (level 25 of 25): Complete 5,000,000 successful customer referrals.', 'community', 'event_count', 'referral_completed', 5000000, 'groups', 625, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_10', 'Points 10', 'Easy milestone (level 1 of 25): Earn 10 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 10, 'stars', 701, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_25', 'Points 25', 'Easy milestone (level 2 of 25): Earn 25 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 25, 'stars', 702, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_50', 'Points 50', 'Easy milestone (level 3 of 25): Earn 50 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 50, 'stars', 703, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_100', 'Points 100', 'Easy milestone (level 4 of 25): Earn 100 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 100, 'stars', 704, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_250', 'Points 250', 'Easy milestone (level 5 of 25): Earn 250 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 250, 'stars', 705, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_500', 'Points 500', 'Moderate milestone (level 6 of 25): Earn 500 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 500, 'stars', 706, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_1000', 'Points 1,000', 'Moderate milestone (level 7 of 25): Earn 1,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 1000, 'stars', 707, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_2500', 'Points 2,500', 'Moderate milestone (level 8 of 25): Earn 2,500 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 2500, 'stars', 708, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_collector', 'Points Collector', 'Moderate milestone (level 9 of 25): Earn 5,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 5000, 'stars', 709, '{}', false, true, null, null, '2026-08-26 18:45:42.925658+00', '2026-08-26 18:45:42.925658+00'),
    ('points_10000', 'Points 10,000', 'Moderate milestone (level 10 of 25): Earn 10,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 10000, 'stars', 710, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_25000', 'Points 25,000', 'Hard milestone (level 11 of 25): Earn 25,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 25000, 'stars', 711, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_50000', 'Points 50,000', 'Hard milestone (level 12 of 25): Earn 50,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 50000, 'stars', 712, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_100000', 'Points 100,000', 'Hard milestone (level 13 of 25): Earn 100,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 100000, 'stars', 713, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_250000', 'Points 250,000', 'Hard milestone (level 14 of 25): Earn 250,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 250000, 'stars', 714, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_500000', 'Points 500,000', 'Hard milestone (level 15 of 25): Earn 500,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 500000, 'stars', 715, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_1000000', 'Points 1,000,000', 'Very hard milestone (level 16 of 25): Earn 1,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 1000000, 'stars', 716, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_2500000', 'Points 2,500,000', 'Very hard milestone (level 17 of 25): Earn 2,500,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 2500000, 'stars', 717, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_5000000', 'Points 5,000,000', 'Very hard milestone (level 18 of 25): Earn 5,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 5000000, 'stars', 718, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_10000000', 'Points 10,000,000', 'Very hard milestone (level 19 of 25): Earn 10,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 10000000, 'stars', 719, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_25000000', 'Points 25,000,000', 'Very hard milestone (level 20 of 25): Earn 25,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 25000000, 'stars', 720, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_50000000', 'Points 50,000,000', 'Extremely hard milestone (level 21 of 25): Earn 50,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 50000000, 'stars', 721, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_100000000', 'Points 100,000,000', 'Extremely hard milestone (level 22 of 25): Earn 100,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 100000000, 'stars', 722, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_250000000', 'Points 250,000,000', 'Extremely hard milestone (level 23 of 25): Earn 250,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 250000000, 'stars', 723, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_500000000', 'Points 500,000,000', 'Extremely hard milestone (level 24 of 25): Earn 500,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 500000000, 'stars', 724, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('points_1000000000', 'Points 1,000,000,000', 'Extremely hard milestone (level 25 of 25): Earn 1,000,000,000 lifetime loyalty points.', 'wallet', 'lifetime_points', null, 1000000000, 'stars', 725, '{}', false, true, null, null, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- 29. loyalty_redemption_config
-- Source: 20261014105237_seed_loyalty_redemption_config.sql
INSERT INTO public.loyalty_redemption_config (
    redemption_code, transaction_type, country_code, currency_code,
    points_per_usd, priority, is_active, valid_from, valid_until,
    created_at, updated_at
) VALUES (
    'cash_transfer_fee_standard', 'cash_transfer', null, null,
    1000, 100, true, null, null,
    '2026-08-27 17:07:54.940088+00',
    '2026-08-28 10:17:58.726355+00'
);

-- 30. notification_template
-- Source: 20261014110821_seed_notification_template.sql
INSERT INTO public.notification_template (
    country_code, language_code, transaction_type, notification_type,
    audience, title_template, body_template, is_active, created_at, updated_at
) VALUES
    ('zw', 'en', 'gold_token_buy', 'buy', 'receiver', 'Gold Purchase Successful', 'You purchased {{quantity}} grams of gold worth {{amount}} {{currency}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'merchant_payment', 'payment', 'receiver', 'Payment Successful', 'You received payment of {{amount}} {{currency}} successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_deposit', 'deposit', 'sender', 'Deposit Successful', 'Your deposit of {{amount}} {{currency}} to {{receiver}} was successful. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'gold_token_sell', 'sell', 'receiver', 'Gold Sale Successful', 'You sold {{quantity}} grams of gold for {{amount}} {{currency}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'credit_agent_cash_settlement', 'settlement', 'receiver', 'Cash Settlement Successful', 'Your cash settlement of {{amount}} {{currency}} was completed successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_deposit', 'deposit', 'receiver', 'Deposit Successful', 'Your deposit of {{amount}} {{currency}} from {{sender}} was successful. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'loan_repayment', 'repayment', 'receiver', 'SVA Balance Settlement Successful', 'Your SVA balance settlement of {{amount}} {{currency}} was successfully received. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_withdrawal_reversal', 'deposit', 'receiver', 'Withdrawal Reversed', 'Your withdrawal transaction of {{amount}} {{currency}} was reversed and funds restored. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'merchant_withdrawal', 'withdrawal', 'receiver', 'Merchant Withdrawal Successful', 'Your merchant withdrawal of {{amount}} {{currency}} was completed successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'loan_disbursement', 'disbursement', 'receiver', 'SVA Unlocked', 'SVA of {{amount}} {{currency}} has been successfully unlocked. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'credit_agent_funding_reversal', 'reversal', 'receiver', 'Agent Funding Reversal Successful', 'Your deposit of {{amount}} {{currency}} was successfully reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'agent_settlement', 'payment', 'receiver', 'Agent Settlement Completed', 'Your settlement payment of {{amount}} {{currency}} has been completed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'loan_repayment_reversal', 'deposit', 'receiver', 'Loan Repayment Reversed', 'Your loan repayment of {{amount}} {{currency}} was reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'loan_disbursement_reversal', 'withdrawal', 'receiver', 'Loan Disbursement Reversed', 'Your loan disbursement of {{amount}} {{currency}} was reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'credit_agent_funding', 'deposit', 'receiver', 'Agent Funding Successful', 'Your deposit of {{amount}} {{currency}} was successfully processed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'gold_token_sell_reversal', 'buy', 'receiver', 'Gold Sale Reversed', 'Your gold sale transaction was reversed. Amount: {{amount}} {{currency}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_transfer', 'transfer', 'receiver', 'Transfer Successful', 'You received {{amount}} {{currency}} from {{sender}} successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'merchant_payment_reversal', 'payment', 'receiver', 'Payment Reversed', 'Your merchant payment of {{amount}} {{currency}} was reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'gold_token_buy_reversal', 'sell', 'receiver', 'Gold Purchase Reversed', 'Your gold purchase transaction was reversed. Amount: {{amount}} {{currency}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'customer_direct_deposit', 'deposit', 'receiver', 'Deposit Received', 'Your deposit of {{amount}} {{currency}} was successful. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'loan_liquidation', 'disbursement', 'receiver', 'SVA Rebalancing Executed', 'Collateral rebalancing was executed against your SVA balance. Total amount recovered: {{amount}} {{currency}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'credit_agent_cash_withdrawal', 'withdrawal', 'receiver', 'Withdrawal Successful', 'Your withdrawal of {{amount}} {{currency}} was completed successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_transfer', 'transfer', 'sender', 'Transfer Successful', 'You sent {{amount}} {{currency}} to {{receiver}}. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_transfer_reversal', 'transfer', 'receiver', 'Transfer Reversed', 'Your transfer transaction of {{amount}} {{currency}} was reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'gold_token_transfer', 'transfer', 'sender', 'Gold Transfer Successful', 'You transferred {{quantity}} grams of gold to {{receiver}} successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'merchant_payment', 'payment', 'sender', 'Payment Successful', 'Your payment of {{amount}} {{currency}} to {{receiver}} was completed successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_withdrawal', 'withdrawal', 'receiver', 'Withdrawal Successful', 'Your withdrawal of {{amount}} {{currency}} was completed successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'agent_commission_settlement', 'payment', 'receiver', 'Commission Settlement Successful', 'Your commission settlement of {{amount}} {{currency}} was successfully processed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'cash_deposit_reversal', 'withdrawal', 'receiver', 'Deposit Reversed', 'Your deposit transaction of {{amount}} {{currency}} was reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'agent_funding_reversal', 'reversal', 'receiver', 'Agent Funding Reversal Successful', 'Your deposit of {{amount}} {{currency}} was successfully reversed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'gold_token_transfer', 'transfer', 'receiver', 'Gold Transfer Successful', 'You received {{quantity}} grams of gold from {{sender}} successfully. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'agent_funding', 'deposit', 'receiver', 'Agent Funding Successful', 'Your deposit of {{amount}} {{currency}} was successfully processed. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198'),
    ('zw', 'en', 'credit_agent_cash_deposit', 'deposit', 'receiver', 'Deposit Successful', 'Your deposit of {{amount}} {{currency}} from {{sender}} was successful. Reference: {{reference}}.', true, '2026-07-20 15:10:45.198', '2026-07-20 15:10:45.198');

-- 31. Pending and verified transaction limits
-- Pending master data: exact supplied caps; minimum stays 1.
-- KYC verification code uses pending, not completed. No approved/completed aliases.
-- Run AFTER fiscal-audit, active-history and KYC-specific limit-index corrections.
LOCK TABLE public.transaction_limit IN SHARE ROW EXCLUSIVE MODE;
DO $seed$
DECLARE
  cfg record;
  previous public.transaction_limit%rowtype;
  audit_year integer := extract(year FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  audit_period integer := extract(month FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  inserted_count integer := 0;
  archived_count integer := 0;
  unchanged_count integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index x WHERE x.indrelid='public.transaction_limit'::regclass
      AND x.indisunique AND x.indisvalid AND x.indexprs IS NULL AND x.indnkeyatts=4
      AND pg_get_expr(x.indpred,x.indrelid)='(is_active = true)'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
        FROM unnest(x.indkey::smallint[]) WITH ORDINALITY keys(attnum,n)
        JOIN pg_attribute a ON a.attrelid=x.indrelid AND a.attnum=keys.attnum
        WHERE keys.n<=x.indnkeyatts)
        = ARRAY['country_code','currency_code','kyc_status','transaction_type']::text[]
  ) THEN RAISE EXCEPTION 'KYC_SPECIFIC_ACTIVE_LIMIT_INDEX_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_limit'::regclass
    AND contype='f' AND confrelid=to_regclass('public.fiscal_period_config'))
  THEN RAISE EXCEPTION 'APPLY_CONFIGURATION_FISCAL_AUDIT_CORRECTION_FIRST'; END IF;

  FOR cfg IN SELECT * FROM (VALUES
      ('bw','cash_deposit','bwp',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('bw','cash_transfer','bwp',1::numeric,5000::numeric,10000::numeric,20000::numeric),
      ('bw','cash_withdrawal','bwp',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('zw','cash_deposit','bwp',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('zw','cash_deposit','usd',1::numeric,100::numeric,500::numeric,1000::numeric),
      ('zw','cash_deposit','zar',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('zw','cash_deposit','zig',1::numeric,100::numeric,500::numeric,1000::numeric),
      ('zw','cash_transfer','bwp',1::numeric,5000::numeric,10000::numeric,20000::numeric),
      ('zw','cash_transfer','usd',1::numeric,500::numeric,1000::numeric,5000::numeric),
      ('zw','cash_transfer','zar',1::numeric,5000::numeric,10000::numeric,20000::numeric),
      ('zw','cash_transfer','zig',1::numeric,5000::numeric,10000::numeric,50000::numeric),
      ('zw','cash_withdrawal','bwp',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('zw','cash_withdrawal','usd',1::numeric,500::numeric,1000::numeric,5000::numeric),
      ('zw','cash_withdrawal','zar',1::numeric,2000::numeric,5000::numeric,20000::numeric),
      ('zw','cash_withdrawal','zig',1::numeric,5000::numeric,10000::numeric,50000::numeric)
  ) AS proposed(country_code,transaction_type,currency_code,min_amount,max_amount,daily_limit,monthly_limit)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.operational_country c WHERE c.country_code=cfg.country_code) THEN
      RAISE EXCEPTION 'SEED_COUNTRY_REQUIRED: %',cfg.country_code;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.supported_currency c WHERE c.currency_code=cfg.currency_code) THEN
      RAISE EXCEPTION 'SEED_CURRENCY_REQUIRED: %',cfg.currency_code;
    END IF;

    SELECT * INTO previous FROM public.transaction_limit t
    WHERE t.country_code=cfg.country_code
      AND t.transaction_type=cfg.transaction_type::public."TransactionType"
      AND t.currency_code=cfg.currency_code
      AND t.kyc_status='pending'::public."KycStatus"
      AND t.is_active=true
    FOR UPDATE;

    IF FOUND THEN
      IF previous.min_amount IS NOT DISTINCT FROM cfg.min_amount
         AND previous.max_amount IS NOT DISTINCT FROM cfg.max_amount
         AND previous.daily_limit IS NOT DISTINCT FROM cfg.daily_limit
         AND previous.monthly_limit IS NOT DISTINCT FROM cfg.monthly_limit
      THEN
        unchanged_count := unchanged_count+1;
        CONTINUE;
      END IF;
      UPDATE public.transaction_limit SET is_active=false,updated_at=now(),updated_by='admin'
      WHERE id=previous.id;
      archived_count := archived_count+1;
    END IF;

    INSERT INTO public.transaction_limit (
      fiscal_year,period,country_code,transaction_type,currency_code,kyc_status,
      min_amount,max_amount,daily_limit,monthly_limit,is_active,created_by
    ) VALUES (
      audit_year,audit_period,cfg.country_code,cfg.transaction_type::public."TransactionType",
      cfg.currency_code,'pending'::public."KycStatus",cfg.min_amount,cfg.max_amount,
      cfg.daily_limit,cfg.monthly_limit,true,'admin'
    );
    inserted_count := inserted_count+1;
  END LOOP;
  RAISE NOTICE 'PENDING_LIMIT_SEED inserted=%, archived=%, unchanged=%',inserted_count,archived_count,unchanged_count;
END;
$seed$;


SELECT country_code,transaction_type,currency_code,kyc_status,
       min_amount,max_amount,daily_limit,monthly_limit
FROM public.transaction_limit WHERE is_active=true AND kyc_status='pending'::public."KycStatus"
ORDER BY country_code,transaction_type,currency_code;

-- QA master data proposal: VERIFIED caps = 5x supplied pending caps; minimum stays 1.
-- KYC verification code uses verified, not completed. No approved/completed aliases.
-- Run AFTER fiscal-audit, active-history and KYC-specific limit-index corrections.
LOCK TABLE public.transaction_limit IN SHARE ROW EXCLUSIVE MODE;
DO $seed$
DECLARE
  cfg record;
  previous public.transaction_limit%rowtype;
  audit_year integer := extract(year FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  audit_period integer := extract(month FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  inserted_count integer := 0;
  archived_count integer := 0;
  unchanged_count integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index x WHERE x.indrelid='public.transaction_limit'::regclass
      AND x.indisunique AND x.indisvalid AND x.indexprs IS NULL AND x.indnkeyatts=4
      AND pg_get_expr(x.indpred,x.indrelid)='(is_active = true)'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
        FROM unnest(x.indkey::smallint[]) WITH ORDINALITY keys(attnum,n)
        JOIN pg_attribute a ON a.attrelid=x.indrelid AND a.attnum=keys.attnum
        WHERE keys.n<=x.indnkeyatts)
        = ARRAY['country_code','currency_code','kyc_status','transaction_type']::text[]
  ) THEN RAISE EXCEPTION 'KYC_SPECIFIC_ACTIVE_LIMIT_INDEX_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_limit'::regclass
    AND contype='f' AND confrelid=to_regclass('public.fiscal_period_config'))
  THEN RAISE EXCEPTION 'APPLY_CONFIGURATION_FISCAL_AUDIT_CORRECTION_FIRST'; END IF;

  FOR cfg IN SELECT * FROM (VALUES
      ('bw','cash_deposit','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('bw','cash_transfer','bwp',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('bw','cash_withdrawal','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','usd',1::numeric,500::numeric,2500::numeric,5000::numeric),
      ('zw','cash_deposit','zar',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','zig',1::numeric,500::numeric,2500::numeric,5000::numeric),
      ('zw','cash_transfer','bwp',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('zw','cash_transfer','usd',1::numeric,2500::numeric,5000::numeric,25000::numeric),
      ('zw','cash_transfer','zar',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('zw','cash_transfer','zig',1::numeric,25000::numeric,50000::numeric,250000::numeric),
      ('zw','cash_withdrawal','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_withdrawal','usd',1::numeric,2500::numeric,5000::numeric,25000::numeric),
      ('zw','cash_withdrawal','zar',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_withdrawal','zig',1::numeric,25000::numeric,50000::numeric,250000::numeric)
  ) AS proposed(country_code,transaction_type,currency_code,min_amount,max_amount,daily_limit,monthly_limit)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.operational_country c WHERE c.country_code=cfg.country_code) THEN
      RAISE EXCEPTION 'SEED_COUNTRY_REQUIRED: %',cfg.country_code;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.supported_currency c WHERE c.currency_code=cfg.currency_code) THEN
      RAISE EXCEPTION 'SEED_CURRENCY_REQUIRED: %',cfg.currency_code;
    END IF;

    SELECT * INTO previous FROM public.transaction_limit t
    WHERE t.country_code=cfg.country_code
      AND t.transaction_type=cfg.transaction_type::public."TransactionType"
      AND t.currency_code=cfg.currency_code
      AND t.kyc_status='verified'::public."KycStatus"
      AND t.is_active=true
    FOR UPDATE;

    IF FOUND THEN
      IF previous.min_amount IS NOT DISTINCT FROM cfg.min_amount
         AND previous.max_amount IS NOT DISTINCT FROM cfg.max_amount
         AND previous.daily_limit IS NOT DISTINCT FROM cfg.daily_limit
         AND previous.monthly_limit IS NOT DISTINCT FROM cfg.monthly_limit
      THEN
        unchanged_count := unchanged_count+1;
        CONTINUE;
      END IF;
      UPDATE public.transaction_limit SET is_active=false,updated_at=now(),updated_by='admin'
      WHERE id=previous.id;
      archived_count := archived_count+1;
    END IF;

    INSERT INTO public.transaction_limit (
      fiscal_year,period,country_code,transaction_type,currency_code,kyc_status,
      min_amount,max_amount,daily_limit,monthly_limit,is_active,created_by
    ) VALUES (
      audit_year,audit_period,cfg.country_code,cfg.transaction_type::public."TransactionType",
      cfg.currency_code,'verified'::public."KycStatus",cfg.min_amount,cfg.max_amount,
      cfg.daily_limit,cfg.monthly_limit,true,'admin'
    );
    inserted_count := inserted_count+1;
  END LOOP;
  RAISE NOTICE 'VERIFIED_LIMIT_SEED inserted=%, archived=%, unchanged=%',inserted_count,archived_count,unchanged_count;
END;
$seed$;


SELECT country_code,transaction_type,currency_code,kyc_status,
       min_amount,max_amount,daily_limit,monthly_limit
FROM public.transaction_limit WHERE is_active=true AND kyc_status='verified'::public."KycStatus"
ORDER BY country_code,transaction_type,currency_code;

COMMIT;

-- Next: deno run --allow-env --allow-net supabase/scripts/seed_super_admin.ts
