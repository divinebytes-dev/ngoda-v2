-- Expected: enabled O, AFTER INSERT ON auth.users, private proof function.
SELECT t.tgname,t.tgenabled,pg_get_triggerdef(t.oid)
FROM pg_trigger t WHERE t.tgrelid='auth.users'::regclass
AND t.tgname='ngoda_record_registration_auth_creation';
-- Expected seed counts: 10, 15, 15.
SELECT (SELECT count(*) FROM public.agent_fee_splitting_config) AS agent_splits,
(SELECT count(*) FROM public.transaction_limit WHERE kyc_status::text='pending') AS pending_limits,
(SELECT count(*) FROM public.transaction_limit WHERE kyc_status::text='verified') AS verified_limits;
-- Rates start empty; inspect again after running the price refreshes.
SELECT code,rate_to_usd,updated_at FROM public.current_rates ORDER BY code;
