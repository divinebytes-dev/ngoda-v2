BEGIN;

-- 1. Remove old fetch_opening_wallet_snapshot (5 parameters)
DROP FUNCTION IF EXISTS public.fetch_opening_wallet_snapshot(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer
) RESTRICT;

-- 2. Remove old fetch_wallet (3 parameters)
DROP FUNCTION IF EXISTS public.fetch_wallet(
    text,
    text,
    public."WalletOwnerType"
) RESTRICT;

-- 3. Remove old get_my_wallet_period_entries (6 parameters)
DROP FUNCTION IF EXISTS public.get_my_wallet_period_entries(
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
) RESTRICT;

-- 4. Remove old get_wallet_period_entries (7 parameters)
DROP FUNCTION IF EXISTS public.get_wallet_period_entries(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
) RESTRICT;

COMMIT;