BEGIN;

-- 1. Add the final blockchain_code columns

ALTER TABLE public.wallet
ADD COLUMN IF NOT EXISTS blockchain_code text;

ALTER TABLE public.wallet_balance_snapshot
ADD COLUMN IF NOT EXISTS blockchain_code text;


-- 2. Migrate existing blockchain references

UPDATE public.wallet w
SET blockchain_code = b.code
FROM public.supported_blockchain b
WHERE w.blockchain_id = b.id
  AND w.blockchain_id IS NOT NULL;

UPDATE public.wallet_balance_snapshot s
SET blockchain_code = b.code
FROM public.supported_blockchain b
WHERE s.blockchain_id = b.id
  AND s.blockchain_id IS NOT NULL;


-- 3. Assign Gnosis to existing gold wallets
-- Only where no blockchain has been assigned.

UPDATE public.wallet
SET blockchain_code = 'gnosis'
WHERE currency_code = 'gold'
  AND blockchain_code IS NULL;

UPDATE public.wallet_balance_snapshot
SET blockchain_code = 'gnosis'
WHERE currency_code = 'gold'
  AND blockchain_code IS NULL;


-- 4. Remove old unique indexes

DROP INDEX IF EXISTS
    public.wallet_non_blockchain_unique_idx;

DROP INDEX IF EXISTS
    public.wallet_blockchain_unique_idx;

DROP INDEX IF EXISTS
    public.wallet_blockchain_network_idx;

DROP INDEX IF EXISTS
    public.wallet_snapshot_non_blockchain_unique_idx;

DROP INDEX IF EXISTS
    public.wallet_snapshot_blockchain_unique_idx;


-- 5. Remove old foreign keys

ALTER TABLE public.wallet
DROP CONSTRAINT IF EXISTS wallet_blockchain_id_fkey,
DROP CONSTRAINT IF EXISTS wallet_blockchain_network_id_fkey;

ALTER TABLE public.wallet_balance_snapshot
DROP CONSTRAINT IF EXISTS wallet_balance_snapshot_blockchain_id_fkey,
DROP CONSTRAINT IF EXISTS wallet_balance_snapshot_blockchain_network_id_fkey;


-- 6. Remove unnecessary columns

ALTER TABLE public.wallet
DROP COLUMN IF EXISTS blockchain_id,
DROP COLUMN IF EXISTS blockchain_network_id;

ALTER TABLE public.wallet_balance_snapshot
DROP COLUMN IF EXISTS blockchain_id,
DROP COLUMN IF EXISTS blockchain_network_id;


-- 7. Create foreign keys using blockchain_code
-- References supported_blockchain.code

ALTER TABLE public.wallet
ADD CONSTRAINT wallet_blockchain_code_fkey
FOREIGN KEY (blockchain_code)
REFERENCES public.supported_blockchain(code)
ON UPDATE CASCADE
ON DELETE RESTRICT;

ALTER TABLE public.wallet_balance_snapshot
ADD CONSTRAINT wallet_balance_snapshot_blockchain_code_fkey
FOREIGN KEY (blockchain_code)
REFERENCES public.supported_blockchain(code)
ON UPDATE CASCADE
ON DELETE RESTRICT;


-- 8. Recreate wallet unique indexes

CREATE UNIQUE INDEX wallet_non_blockchain_unique_idx
ON public.wallet (
    country_code,
    user_id,
    currency_code,
    owner_type
)
WHERE blockchain_code IS NULL;

CREATE UNIQUE INDEX wallet_blockchain_unique_idx
ON public.wallet (
    country_code,
    user_id,
    currency_code,
    owner_type,
    blockchain_code
)
WHERE blockchain_code IS NOT NULL;


-- 9. Recreate snapshot unique indexes

CREATE UNIQUE INDEX wallet_snapshot_non_blockchain_unique_idx
ON public.wallet_balance_snapshot (
    user_id,
    currency_code,
    wallet_owner,
    fiscal_year,
    period
)
WHERE blockchain_code IS NULL;

CREATE UNIQUE INDEX wallet_snapshot_blockchain_unique_idx
ON public.wallet_balance_snapshot (
    user_id,
    currency_code,
    wallet_owner,
    blockchain_code,
    fiscal_year,
    period
)
WHERE blockchain_code IS NOT NULL;


-- 10. Add blockchain lookup index

CREATE INDEX wallet_blockchain_code_idx
ON public.wallet (blockchain_code);

COMMIT;