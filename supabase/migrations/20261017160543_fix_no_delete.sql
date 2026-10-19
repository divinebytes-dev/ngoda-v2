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

CREATE OR REPLACE FUNCTION public.ngoda_prevent_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  RAISE EXCEPTION 'Deletes/truncates are not allowed on table %.', TG_TABLE_NAME;
END;
$function$;
CREATE OR REPLACE FUNCTION public.ngoda_prevent_update_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
  RAISE EXCEPTION 'Updates and deletes are not allowed on append-only table %.', TG_TABLE_NAME;
END;
$function$;
REVOKE ALL ON FUNCTION public.ngoda_prevent_delete(), public.ngoda_prevent_update_delete()
  FROM PUBLIC, anon, authenticated;
DO $migration$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_commission', 'agent_fee_splitting_config', 'agent_settlement_batch', 'agent_settlement_item', 'aml_config', 'asset_entry', 'asset_reserve', 'audit_log', 'blockchain_transaction', 'collateral', 'collateral_balance_snapshot', 'collateral_entry', 'country_currencies', 'credit_agent_account', 'credit_agent_entry', 'current_rates', 'device_tokens', 'document_sequence', 'financial_badge', 'financial_behavior', 'financial_behavior_rule', 'financial_entry', 'financial_pot', 'financial_pot_event', 'financial_transaction', 'fiscal_period_config', 'gamification_event', 'gamification_notification', 'gl_account', 'gl_balance_snapshot', 'gl_update_request', 'government_tax_config', 'government_tax_payable', 'government_tax_settlement_batch', 'government_tax_settlement_item', 'idempotency_key', 'job_error_log', 'liquidation_blockchain_queue', 'liquidation_job', 'loan', 'loan_balance_snapshot', 'loan_config', 'loan_entry', 'loyalty_account', 'loyalty_badge', 'loyalty_badge_progress', 'loyalty_cap_usage', 'loyalty_ledger', 'loyalty_level', 'loyalty_level_history', 'loyalty_program_config', 'loyalty_redemption_config', 'loyalty_rule', 'loyalty_rule_band', 'maximum_tap_payment_amount_config', 'merchant_commission', 'merchant_fee_splitting_config', 'merchant_settlement_batch', 'merchant_settlement_item', 'message_translation', 'notification_template', 'notifications', 'operational_country', 'reconciliation_adjustment_request', 'reconciliation_item', 'reconciliation_run', 'referral_earnings', 'referral_earnings_config', 'referral_earnings_settlement_batch', 'referral_earnings_settlement_item', 'reserve_asset_adjustment_request', 'spread_config', 'supported_blockchain', 'supported_blockchain_network', 'supported_currency', 'supported_language', 'system_flag', 'tokenised_asset_adjustment_request', 'transaction_gl_mapping', 'transaction_limit', 'transaction_state', 'transaction_type_document_number_prefix', 'transaction_type_fee_config', 'transaction_type_wallet_owner', 'transaction_types', 'transaction_v', 'user_badge', 'user_financial_badge', 'user_kyc', 'user_presence', 'user_role', 'user_verification_document', 'users', 'voucher_lock', 'voucher_usage', 'wallet', 'wallet_balance_snapshot', 'wallet_entry']::text[] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I',t || '_no_delete',t);
    EXECUTE format('CREATE TRIGGER %I BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.ngoda_prevent_delete()',t || '_no_delete',t);
    -- Row DELETE triggers do not protect TRUNCATE. Protect it explicitly too.
    EXECUTE format('DROP TRIGGER IF EXISTS ngoda_no_truncate ON public.%I',t);
    EXECUTE format('CREATE TRIGGER ngoda_no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.ngoda_prevent_delete()',t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['financial_transaction', 'financial_entry', 'wallet_entry', 'loan_entry', 'asset_entry', 'collateral_entry', 'audit_log', 'credit_agent_entry', 'loyalty_ledger', 'loyalty_level_history', 'user_badge']::text[] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I',t || '_no_update',t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.ngoda_prevent_update_delete()',t || '_no_update',t);
  END LOOP;
END;
$migration$;
-- Existing business triggers are retained; these generic guards do not replace them.
-- Status tables, current balances and snapshots remain updateable through backend code.
COMMIT;
