SELECT p.oid::regprocedure AS function_signature,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_allowed,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_allowed,
 has_function_privilege('service_role',p.oid,'EXECUTE') AS service_allowed
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('execute_my_loan_disbursement','execute_loan_disbursement','preview_loan_for_user')
ORDER BY p.proname;
