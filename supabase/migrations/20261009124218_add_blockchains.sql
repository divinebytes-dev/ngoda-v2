BEGIN;

-- 1. Supported blockchains
CREATE TABLE IF NOT EXISTS public.supported_blockchain (
    id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    blockchain_type text NOT NULL DEFAULT 'evm',
    native_currency_code text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp NOT NULL DEFAULT now(),
    updated_at timestamp NOT NULL DEFAULT now()
);

-- 2. Blockchain networks
CREATE TABLE IF NOT EXISTS public.supported_blockchain_network (
    id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
    blockchain_id text NOT NULL
        REFERENCES public.supported_blockchain(id),
    network_name text NOT NULL,
    environment text NOT NULL
        CHECK (environment IN ('mainnet', 'testnet')),
    chain_id bigint NOT NULL UNIQUE,
    rpc_url text,
    explorer_url text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamp NOT NULL DEFAULT now(),
    updated_at timestamp NOT NULL DEFAULT now(),
    UNIQUE (blockchain_id, network_name)
);

-- 3. Register Gnosis
INSERT INTO public.supported_blockchain (
    code, name, blockchain_type, native_currency_code
)
VALUES (
    'gnosis', 'Gnosis', 'evm', 'XDAI'
)
ON CONFLICT (code) DO NOTHING;

-- 4. Register Gnosis networks
INSERT INTO public.supported_blockchain_network (
    blockchain_id,
    network_name,
    environment,
    chain_id,
    rpc_url,
    explorer_url,
    is_active,
    is_default
)
SELECT
    b.id,
    n.network_name,
    n.environment,
    n.chain_id,
    n.rpc_url,
    n.explorer_url,
    true,
    n.is_default
FROM public.supported_blockchain b
CROSS JOIN (
    VALUES
    (
        'Gnosis Mainnet',
        'mainnet',
        100::bigint,
        'https://rpc.gnosischain.com',
        'https://gnosisscan.io',
        true
    ),
    (
        'Gnosis Chiado',
        'testnet',
        10200::bigint,
        'https://rpc.chiadochain.net',
        'https://gnosis-chiado.blockscout.com',
        false
    )
) AS n (
    network_name,
    environment,
    chain_id,
    rpc_url,
    explorer_url,
    is_default
)
WHERE b.code = 'gnosis'
ON CONFLICT (chain_id) DO NOTHING;

-- 5. Extend wallet
ALTER TABLE public.wallet
ADD COLUMN IF NOT EXISTS blockchain_network_id text
REFERENCES public.supported_blockchain_network(id);

-- 6. Extend wallet snapshots
ALTER TABLE public.wallet_balance_snapshot
ADD COLUMN IF NOT EXISTS blockchain_network_id text
REFERENCES public.supported_blockchain_network(id);

-- 7. Replace wallet uniqueness
DROP INDEX IF EXISTS
public.wallet_country_code_user_id_currency_code_owner_type_key;

CREATE UNIQUE INDEX wallet_non_blockchain_unique_idx
ON public.wallet (
    country_code,
    user_id,
    currency_code,
    owner_type
)
WHERE blockchain_network_id IS NULL;

CREATE UNIQUE INDEX wallet_blockchain_unique_idx
ON public.wallet (
    country_code,
    user_id,
    currency_code,
    owner_type,
    blockchain_network_id
)
WHERE blockchain_network_id IS NOT NULL;

-- 8. Replace snapshot uniqueness
DROP INDEX IF EXISTS
public.wallet_balance_snapshot_user_id_currency_code_wallet_owner__key;

CREATE UNIQUE INDEX wallet_snapshot_non_blockchain_unique_idx
ON public.wallet_balance_snapshot (
    user_id,
    currency_code,
    wallet_owner,
    fiscal_year,
    period
)
WHERE blockchain_network_id IS NULL;

CREATE UNIQUE INDEX wallet_snapshot_blockchain_unique_idx
ON public.wallet_balance_snapshot (
    user_id,
    currency_code,
    wallet_owner,
    blockchain_network_id,
    fiscal_year,
    period
)
WHERE blockchain_network_id IS NOT NULL;

CREATE INDEX wallet_blockchain_network_idx
ON public.wallet (blockchain_network_id);

COMMIT;