-- EXISTING DEV OR PREPARED QA: authoritative direct-table security contract.
-- No data changes; RPC EXECUTE permissions remain unchanged.
BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role;
DO $security$
DECLARE t text; columns_sql text; seq_name text; policy_record record;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_commission','agent_fee_splitting_config','agent_settlement_batch','agent_settlement_item','aml_config','asset_entry','asset_reserve','audit_log','blockchain_transaction','collateral','collateral_balance_snapshot','collateral_entry','country_currencies','credit_agent_account','credit_agent_entry','current_rates','device_tokens','document_sequence','financial_badge','financial_behavior','financial_behavior_rule','financial_entry','financial_pot','financial_pot_event','financial_transaction','fiscal_period_config','gamification_event','gamification_notification','gl_account','gl_balance_snapshot','gl_update_request','government_tax_config','government_tax_payable','government_tax_settlement_batch','government_tax_settlement_item','idempotency_key','job_error_log','liquidation_blockchain_queue','liquidation_job','loan','loan_balance_snapshot','loan_config','loan_entry','loyalty_account','loyalty_badge','loyalty_badge_progress','loyalty_cap_usage','loyalty_ledger','loyalty_level','loyalty_level_history','loyalty_program_config','loyalty_redemption_config','loyalty_rule','loyalty_rule_band','maximum_tap_payment_amount_config','merchant_commission','merchant_fee_splitting_config','merchant_settlement_batch','merchant_settlement_item','message_translation','notification_template','notifications','operational_country','reconciliation_adjustment_request','reconciliation_item','reconciliation_run','referral_earnings','referral_earnings_config','referral_earnings_settlement_batch','referral_earnings_settlement_item','reserve_asset_adjustment_request','spread_config','supported_blockchain','supported_blockchain_network','supported_currency','supported_language','system_flag','tokenised_asset_adjustment_request','transaction_gl_mapping','transaction_limit','transaction_state','transaction_type_document_number_prefix','transaction_type_fee_config','transaction_type_wallet_owner','transaction_types','transaction_v','user_badge','user_financial_badge','user_kyc','user_presence','user_role','user_verification_document','users','voucher_lock','voucher_usage','wallet','wallet_balance_snapshot','wallet_entry']::text[] LOOP
    IF to_regclass(format('public.%I',t)) IS NULL THEN RAISE EXCEPTION 'APPLICATION_TABLE_MISSING: %',t; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    -- Owners retain bypass for existing SECURITY DEFINER posting functions.
    -- Do not FORCE RLS or grant new direct client access to backend tables.
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC,anon,authenticated',t);
    SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO columns_sql
    FROM pg_attribute WHERE attrelid=to_regclass(format('public.%I',t)) AND attnum>0 AND NOT attisdropped;
    EXECUTE format('REVOKE SELECT (%s), INSERT (%s), UPDATE (%s), REFERENCES (%s) ON TABLE public.%I FROM PUBLIC,anon,authenticated',columns_sql,columns_sql,columns_sql,columns_sql,t);
    -- Backend grants do not bypass ledger mutation triggers below.
    EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE public.%I TO service_role',t);
    FOR policy_record IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t LOOP
      EXECUTE format('DROP POLICY %I ON public.%I',policy_record.policyname,t);
    END LOOP;
    -- Direct client access below uses UUID/text IDs, not serial sequences.
    FOR seq_name IN SELECT pg_get_serial_sequence(format('public.%I',t),a.attname)
      FROM pg_attribute a WHERE a.attrelid=to_regclass(format('public.%I',t)) AND a.attnum>0 AND NOT a.attisdropped
    LOOP
      IF seq_name IS NOT NULL THEN
        EXECUTE format('REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM PUBLIC,anon,authenticated',seq_name);
        EXECUTE format('GRANT USAGE,SELECT ON SEQUENCE %s TO service_role',seq_name);
      END IF;
    END LOOP;
  END LOOP;
END;
$security$;

-- Notification receipt: content/delivery are server-controlled; read state is user-controlled.
GRANT SELECT ON TABLE public.notifications TO authenticated;
GRANT UPDATE(is_read,read_at) ON TABLE public.notifications TO authenticated;
CREATE POLICY notifications_select_own ON public.notifications FOR SELECT TO authenticated
USING(user_id=(SELECT auth.uid())::text);
CREATE POLICY notifications_update_own ON public.notifications FOR UPDATE TO authenticated
USING(user_id=(SELECT auth.uid())::text) WITH CHECK(user_id=(SELECT auth.uid())::text);

-- Participants can subscribe/read transaction progress, not mutate approvals/status.
GRANT SELECT ON TABLE public.transaction_state TO authenticated;
CREATE POLICY transaction_state_select_participant ON public.transaction_state FOR SELECT TO authenticated
USING(created_by=(SELECT auth.uid())::text OR user_id=(SELECT auth.uid())::text);

-- Authenticated users may discover recipient presence, as explicitly confirmed.
GRANT SELECT,INSERT,UPDATE ON TABLE public.user_presence TO authenticated;
CREATE POLICY user_presence_select_authenticated ON public.user_presence FOR SELECT TO authenticated USING(true);
CREATE POLICY user_presence_insert_own ON public.user_presence FOR INSERT TO authenticated
WITH CHECK(user_id=(SELECT auth.uid())::text);
CREATE POLICY user_presence_update_own ON public.user_presence FOR UPDATE TO authenticated
USING(user_id=(SELECT auth.uid())::text) WITH CHECK(user_id=(SELECT auth.uid())::text);

-- Preserve existing device-registration S/I/U access and own-row checks.
GRANT SELECT,INSERT,UPDATE ON TABLE public.device_tokens TO authenticated;
CREATE POLICY device_tokens_select_own ON public.device_tokens FOR SELECT TO authenticated
USING(user_id=(SELECT auth.uid())::text);
CREATE POLICY device_tokens_insert_own ON public.device_tokens FOR INSERT TO authenticated
WITH CHECK(user_id=(SELECT auth.uid())::text);
CREATE POLICY device_tokens_update_own ON public.device_tokens FOR UPDATE TO authenticated
USING(user_id=(SELECT auth.uid())::text) WITH CHECK(user_id=(SELECT auth.uid())::text);

GRANT SELECT ON TABLE public.financial_badge,public.financial_behavior,public.financial_pot,public.user_financial_badge TO authenticated;
CREATE POLICY financial_badge_select_authenticated ON public.financial_badge FOR SELECT TO authenticated USING(is_active=true);
CREATE POLICY financial_behavior_select_own ON public.financial_behavior FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid())::text);
CREATE POLICY financial_pot_select_own ON public.financial_pot FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid())::text);
CREATE POLICY user_financial_badge_select_own ON public.user_financial_badge FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid())::text);

-- Remove automatic future client table/sequence grants for the observed app owners.
-- Each future table migration must still explicitly ENABLE RLS.
DO $defaults$
DECLARE owner_name text;
BEGIN
  FOR owner_name IN SELECT DISTINCT pg_get_userbyid(c.relowner) FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname=ANY(ARRAY['agent_commission','agent_fee_splitting_config','agent_settlement_batch','agent_settlement_item','aml_config','asset_entry','asset_reserve','audit_log','blockchain_transaction','collateral','collateral_balance_snapshot','collateral_entry','country_currencies','credit_agent_account','credit_agent_entry','current_rates','device_tokens','document_sequence','financial_badge','financial_behavior','financial_behavior_rule','financial_entry','financial_pot','financial_pot_event','financial_transaction','fiscal_period_config','gamification_event','gamification_notification','gl_account','gl_balance_snapshot','gl_update_request','government_tax_config','government_tax_payable','government_tax_settlement_batch','government_tax_settlement_item','idempotency_key','job_error_log','liquidation_blockchain_queue','liquidation_job','loan','loan_balance_snapshot','loan_config','loan_entry','loyalty_account','loyalty_badge','loyalty_badge_progress','loyalty_cap_usage','loyalty_ledger','loyalty_level','loyalty_level_history','loyalty_program_config','loyalty_redemption_config','loyalty_rule','loyalty_rule_band','maximum_tap_payment_amount_config','merchant_commission','merchant_fee_splitting_config','merchant_settlement_batch','merchant_settlement_item','message_translation','notification_template','notifications','operational_country','reconciliation_adjustment_request','reconciliation_item','reconciliation_run','referral_earnings','referral_earnings_config','referral_earnings_settlement_batch','referral_earnings_settlement_item','reserve_asset_adjustment_request','spread_config','supported_blockchain','supported_blockchain_network','supported_currency','supported_language','system_flag','tokenised_asset_adjustment_request','transaction_gl_mapping','transaction_limit','transaction_state','transaction_type_document_number_prefix','transaction_type_fee_config','transaction_type_wallet_owner','transaction_types','transaction_v','user_badge','user_financial_badge','user_kyc','user_presence','user_role','user_verification_document','users','voucher_lock','voucher_usage','wallet','wallet_balance_snapshot','wallet_entry']::text[])
    UNION SELECT current_user::text
  LOOP
    -- Global and schema-local defaults combine; revoke both.
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL ON TABLES FROM PUBLIC,anon,authenticated',owner_name);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC,anon,authenticated',owner_name);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL ON SEQUENCES FROM PUBLIC,anon,authenticated',owner_name);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC,anon,authenticated',owner_name);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO service_role',owner_name);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO service_role',owner_name);
  END LOOP;
END;
$defaults$;
COMMIT;
