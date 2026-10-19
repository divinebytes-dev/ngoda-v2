-- Run on the prepared QA tables as the migration owner. No data is copied.
BEGIN;
DO $preflight$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_commission', 'agent_fee_splitting_config', 'agent_settlement_batch', 'agent_settlement_item', 'aml_config', 'asset_entry', 'asset_reserve', 'audit_log', 'blockchain_transaction', 'collateral', 'collateral_balance_snapshot', 'collateral_entry', 'country_currencies', 'credit_agent_account', 'credit_agent_entry', 'current_rates', 'device_tokens', 'document_sequence', 'financial_badge', 'financial_behavior', 'financial_behavior_rule', 'financial_entry', 'financial_pot', 'financial_pot_event', 'financial_transaction', 'fiscal_period_config', 'gamification_event', 'gamification_notification', 'gl_account', 'gl_balance_snapshot', 'gl_update_request', 'government_tax_config', 'government_tax_payable', 'government_tax_settlement_batch', 'government_tax_settlement_item', 'idempotency_key', 'job_error_log', 'liquidation_blockchain_queue', 'liquidation_job', 'loan', 'loan_balance_snapshot', 'loan_config', 'loan_entry', 'loyalty_account', 'loyalty_badge', 'loyalty_badge_progress', 'loyalty_cap_usage', 'loyalty_ledger', 'loyalty_level', 'loyalty_level_history', 'loyalty_program_config', 'loyalty_redemption_config', 'loyalty_rule', 'loyalty_rule_band', 'maximum_tap_payment_amount_config', 'merchant_commission', 'merchant_fee_splitting_config', 'merchant_settlement_batch', 'merchant_settlement_item', 'message_translation', 'notification_template', 'notifications', 'operational_country', 'reconciliation_adjustment_request', 'reconciliation_item', 'reconciliation_run', 'referral_earnings', 'referral_earnings_config', 'referral_earnings_settlement_batch', 'referral_earnings_settlement_item', 'reserve_asset_adjustment_request', 'spread_config', 'supported_blockchain', 'supported_blockchain_network', 'supported_currency', 'supported_language', 'system_flag', 'tokenised_asset_adjustment_request', 'transaction_gl_mapping', 'transaction_limit', 'transaction_state', 'transaction_type_document_number_prefix', 'transaction_type_fee_config', 'transaction_type_wallet_owner', 'transaction_types', 'transaction_v', 'user_badge', 'user_financial_badge', 'user_kyc', 'user_presence', 'user_role', 'user_verification_document', 'users', 'voucher_lock', 'voucher_usage', 'wallet', 'wallet_balance_snapshot', 'wallet_entry']::text[] LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE EXCEPTION 'QA_TABLE_MISSING: %', t;
    END IF;
  END LOOP;
END;
$preflight$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.agent_commission'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.agent_commission ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.agent_fee_splitting_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.agent_fee_splitting_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.agent_settlement_batch'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.agent_settlement_batch ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.agent_settlement_item'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.agent_settlement_item ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.aml_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.aml_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asset_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.asset_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asset_reserve'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.asset_reserve ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.audit_log'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.audit_log ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.blockchain_transaction'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.blockchain_transaction ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.collateral'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.collateral ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.collateral_balance_snapshot'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.collateral_balance_snapshot ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.collateral_balance_snapshot'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.collateral_balance_snapshot ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.collateral_balance_snapshot'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.collateral_balance_snapshot ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.collateral_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.collateral_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_agent_account'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.credit_agent_account ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_agent_account'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.credit_agent_account ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_agent_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.credit_agent_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_agent_entry'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.credit_agent_entry ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_agent_entry'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.credit_agent_entry ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.device_tokens'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.device_tokens ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.device_tokens'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.device_tokens ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.document_sequence'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.document_sequence ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_behavior'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.financial_behavior ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_behavior'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.financial_behavior ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_behavior'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.financial_behavior ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_behavior'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.financial_behavior ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.financial_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.financial_pot ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.financial_pot ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.financial_pot ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.financial_pot ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot_event'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.financial_pot_event ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot_event'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.financial_pot_event ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot_event'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.financial_pot_event ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_pot_event'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.financial_pot_event ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.financial_transaction'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.financial_transaction ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.fiscal_period_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.fiscal_period_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gamification_event'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.gamification_event ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gamification_event'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.gamification_event ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gl_balance_snapshot'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.gl_balance_snapshot ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gl_balance_snapshot'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.gl_balance_snapshot ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gl_update_request'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.gl_update_request ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.government_tax_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.government_tax_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.government_tax_payable'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.government_tax_payable ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.government_tax_settlement_batch'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.government_tax_settlement_batch ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.government_tax_settlement_item'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.government_tax_settlement_item ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.idempotency_key'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.idempotency_key ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.idempotency_key'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.idempotency_key ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.job_error_log'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.job_error_log ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_blockchain_queue'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.liquidation_blockchain_queue ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_blockchain_queue'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.liquidation_blockchain_queue ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_job'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.liquidation_job ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_job'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.liquidation_job ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loan ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_balance_snapshot'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.loan_balance_snapshot ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_balance_snapshot'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loan_balance_snapshot ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_balance_snapshot'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.loan_balance_snapshot ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loan_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loan_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loyalty_program_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loyalty_program_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loyalty_redemption_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loyalty_redemption_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loyalty_redemption_config'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.loyalty_redemption_config ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loyalty_rule'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.loyalty_rule ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loyalty_rule'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.loyalty_rule ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.maximum_tap_payment_amount_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.maximum_tap_payment_amount_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.merchant_commission'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.merchant_commission ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.merchant_fee_splitting_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.merchant_fee_splitting_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.merchant_settlement_batch'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.merchant_settlement_batch ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.merchant_settlement_item'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.merchant_settlement_item ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notification_template'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.notification_template ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notifications'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.notifications ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notifications'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.notifications ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_adjustment_request'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.reconciliation_adjustment_request ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_adjustment_request'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.reconciliation_adjustment_request ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_item'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.reconciliation_item ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_item'::regclass AND conname='ngoda_currency_code_fk') THEN
    ALTER TABLE public.reconciliation_item ADD CONSTRAINT ngoda_currency_code_fk
      FOREIGN KEY (currency_code) REFERENCES public.supported_currency (currency_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_item'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.reconciliation_item ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reconciliation_run'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.reconciliation_run ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.referral_earnings'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.referral_earnings ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.referral_earnings_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.referral_earnings_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.referral_earnings_settlement_batch'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.referral_earnings_settlement_batch ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.referral_earnings_settlement_item'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.referral_earnings_settlement_item ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.system_flag'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.system_flag ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_limit'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.transaction_limit ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_state'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.transaction_state ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_state'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.transaction_state ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_type_fee_config'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.transaction_type_fee_config ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.user_financial_badge'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.user_financial_badge ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.user_presence'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.user_presence ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallet'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.wallet ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallet_balance_snapshot'::regclass AND conname='ngoda_user_id_fk') THEN
    ALTER TABLE public.wallet_balance_snapshot ADD CONSTRAINT ngoda_user_id_fk
      FOREIGN KEY (user_id) REFERENCES public.users (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallet_balance_snapshot'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.wallet_balance_snapshot ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallet_balance_snapshot'::regclass AND conname='ngoda_country_fiscal_period_fk') THEN
    ALTER TABLE public.wallet_balance_snapshot ADD CONSTRAINT ngoda_country_fiscal_period_fk
      FOREIGN KEY (country_code, fiscal_year, period) REFERENCES public.fiscal_period_config (country_code, fiscal_year, period)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallet_entry'::regclass AND conname='ngoda_country_code_fk') THEN
    ALTER TABLE public.wallet_entry ADD CONSTRAINT ngoda_country_code_fk
      FOREIGN KEY (country_code) REFERENCES public.operational_country (country_code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.agent_commission'::regclass AND conname='ngoda_settlement_batch_fk') THEN
    ALTER TABLE public.agent_commission ADD CONSTRAINT ngoda_settlement_batch_fk
      FOREIGN KEY (settlement_batch_id) REFERENCES public.agent_settlement_batch (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.merchant_commission'::regclass AND conname='ngoda_settlement_batch_fk') THEN
    ALTER TABLE public.merchant_commission ADD CONSTRAINT ngoda_settlement_batch_fk
      FOREIGN KEY (settlement_batch_id) REFERENCES public.merchant_settlement_batch (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.referral_earnings'::regclass AND conname='ngoda_settlement_batch_fk') THEN
    ALTER TABLE public.referral_earnings ADD CONSTRAINT ngoda_settlement_batch_fk
      FOREIGN KEY (settlement_batch_id) REFERENCES public.referral_earnings_settlement_batch (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.government_tax_payable'::regclass AND conname='ngoda_settlement_batch_fk') THEN
    ALTER TABLE public.government_tax_payable ADD CONSTRAINT ngoda_settlement_batch_fk
      FOREIGN KEY (settlement_batch_id) REFERENCES public.government_tax_settlement_batch (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_state'::regclass AND conname='ngoda_blockchain_code_fk') THEN
    ALTER TABLE public.transaction_state ADD CONSTRAINT ngoda_blockchain_code_fk
      FOREIGN KEY (blockchain_code) REFERENCES public.supported_blockchain (code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.blockchain_transaction'::regclass AND conname='ngoda_blockchain_code_fk') THEN
    ALTER TABLE public.blockchain_transaction ADD CONSTRAINT ngoda_blockchain_code_fk
      FOREIGN KEY (blockchain_code) REFERENCES public.supported_blockchain (code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_job'::regclass AND conname='ngoda_blockchain_code_fk') THEN
    ALTER TABLE public.liquidation_job ADD CONSTRAINT ngoda_blockchain_code_fk
      FOREIGN KEY (blockchain_code) REFERENCES public.supported_blockchain (code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_blockchain_queue'::regclass AND conname='ngoda_blockchain_code_fk') THEN
    ALTER TABLE public.liquidation_blockchain_queue ADD CONSTRAINT ngoda_blockchain_code_fk
      FOREIGN KEY (blockchain_code) REFERENCES public.supported_blockchain (code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_blockchain_queue'::regclass AND conname='ngoda_liquidation_job_fk') THEN
    ALTER TABLE public.liquidation_blockchain_queue ADD CONSTRAINT ngoda_liquidation_job_fk
      FOREIGN KEY (liquidation_job_id) REFERENCES public.liquidation_job (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.liquidation_job'::regclass AND conname='ngoda_blockchain_queue_fk') THEN
    ALTER TABLE public.liquidation_job ADD CONSTRAINT ngoda_blockchain_queue_fk
      FOREIGN KEY (blockchain_queue_id) REFERENCES public.liquidation_blockchain_queue (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.loan_balance_snapshot'::regclass AND conname='ngoda_loan_fk') THEN
    ALTER TABLE public.loan_balance_snapshot ADD CONSTRAINT ngoda_loan_fk
      FOREIGN KEY (loan_id) REFERENCES public.loan (id)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;
DO $fk$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.gl_balance_snapshot'::regclass AND conname='ngoda_gl_account_fk') THEN
    ALTER TABLE public.gl_balance_snapshot ADD CONSTRAINT ngoda_gl_account_fk
      FOREIGN KEY (gl_account_code) REFERENCES public.gl_account (code)
      ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
END; $fk$;

-- Keep existing unique/conflict keys intact until their calling RPCs are reviewed.
-- These lookup indexes support missing FK/ownership access paths.
CREATE INDEX IF NOT EXISTS ngoda_notifications_user_history_idx ON public.notifications(user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ngoda_transaction_state_user_idx ON public.transaction_state(user_id);
CREATE INDEX IF NOT EXISTS ngoda_transaction_state_created_by_idx ON public.transaction_state(created_by);
CREATE INDEX IF NOT EXISTS ngoda_network_blockchain_lookup_idx ON public.supported_blockchain_network(blockchain_id,is_active,is_default);
CREATE INDEX IF NOT EXISTS ngoda_wallet_snapshot_user_idx ON public.wallet_balance_snapshot(user_id);
CREATE INDEX IF NOT EXISTS ngoda_loan_snapshot_user_idx ON public.loan_balance_snapshot(user_id);
COMMIT;
