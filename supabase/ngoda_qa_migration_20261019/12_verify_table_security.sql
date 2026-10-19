-- Run as database owner after the two security migrations.
-- First query: expect 98,98,0.
SELECT count(*) AS application_tables,
       count(*) FILTER (WHERE relrowsecurity) AS rls_enabled,
       count(*) FILTER (WHERE relforcerowsecurity) AS force_rls_enabled
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
  AND c.relname NOT IN ('_prisma_migrations','blockchains');

-- Review the deliberately small direct-access contract.
SELECT tablename,policyname,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname='public' ORDER BY tablename,policyname;

-- Expect no rows: the five internal tables have no client grants.
SELECT table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='public' AND grantee IN ('anon','authenticated','PUBLIC')
AND table_name IN ('gl_account','supported_blockchain','supported_blockchain_network',
 'transaction_type_document_number_prefix','transaction_type_wallet_owner');

-- Expect only is_read/read_at UPDATE privileges for authenticated.
SELECT column_name,privilege_type FROM information_schema.column_privileges
WHERE table_schema='public' AND table_name='notifications'
AND grantee='authenticated' AND privilege_type='UPDATE' ORDER BY column_name;

-- Inspect enabled DELETE/TRUNCATE guards and append-only triggers.
SELECT c.relname AS table_name,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal
AND (t.tgname LIKE '%no_delete%' OR t.tgname LIKE '%no_truncate%'
 OR t.tgname LIKE '%no_update%') ORDER BY c.relname,t.tgname;

-- Supabase publication membership: notifications and transaction_state expected.
SELECT pubname,schemaname,tablename FROM pg_publication_tables
WHERE pubname='supabase_realtime' AND schemaname='public'
AND tablename IN ('notifications','transaction_state') ORDER BY tablename;
