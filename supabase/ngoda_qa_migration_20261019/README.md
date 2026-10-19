# Fresh Ngoda QA database package

Built 2026-10-19 from the supplied current development schema dump. Fresh QA only: the schema migration rejects existing application tables. It does not erase an existing database.

## Import order

Use the QA database owner connection. Confirm its project reference is QA before executing any file. Keep the development project unchanged.

1. Run numbered SQL files 01 through 10, in order, stopping on any error. Each migration has its own transaction. File 09 must commit before file 10 uses the badge enum value.
2. Run 11_verify_rpc_permissions.sql 12_verify_table_security.sql and 13_verify_registration_and_seed.sql; inspect the results. File 11 raises an error for an incorrect required RPC permission.
3. Configure and run seed_super_admin.ts against QA only using its environment variables. Use a new QA password; do not copy development Auth users. Its placeholder wallet is reserved for administration, not blockchain transfers.
4. Deploy the current working Edge Functions from your repository and configure QA secrets, Auth URLs, email delivery, and blockchain connections.
5. Recreate cron schedules using QA URLs and QA secrets, then test registration and each financial flow with fresh QA users.

Do not import historical development users, loans, collateral, transactions, queue jobs, or sequence values. Current rates intentionally start empty: run the fiat updater and the liquidation price refresh before financial testing.

## Contents

01 preserves current schema function bodies, enums, composite return types, sequences, constraints, policies and grants. It omits only the legacy _prisma_migrations and blockchains tables and their associated definitions (10 statements). No development data is copied.

02 restores the supplied enabled AFTER INSERT trigger on auth.users. Supabase schema-scoped dumps omit this trigger because its table belongs to auth. The private registration proof table and functions are already in 01.

03–04 apply the previously reviewed integrity checks and additional parent references; these are explicit overlays, including the wallet-entry identity trigger. Configuration fiscal year/period remain audit tags. No country column is added to spread_config or the central adjustment tables.

05–07 reapply the reviewed table security, ledger guards and complete RPC permissions after all functions exist. Retired user-trusting loan disbursement/top-up RPCs remain owner-only. 08 adds notifications and transaction_state to the existing Supabase Realtime publication.

10 includes 10 agent fee configurations, 15 pending and 15 verified transaction limits. Verified limits remain the previously proposed QA values and require business approval before production.

## Verification limits

TEST_RESULTS.txt records an embedded PostgreSQL restore, function-definition validation, seed checks, RPC permissions, RLS and registration proof tests. The test environment supplies minimal Supabase Auth objects. It does not test deployed Edge Functions, actual Auth signup, external price feeds, Firebase, blockchain signing/submission, or cron execution. Realtime publication membership must be verified in QA. A successful restore is not a completed end-to-end financial test.

The supplied seed retains the configured test blockchain addresses and URLs. Confirm they are the intended QA contracts and treasury before enabling blockchain workers. This bundle contains no cron schedules or secret values and does not deploy Edge Functions.
