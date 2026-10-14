ALTER TABLE public.wallet
ADD COLUMN blockchain_id text
REFERENCES public.supported_blockchain(id);

ALTER TABLE public.wallet_balance_snapshot
ADD COLUMN blockchain_id text
REFERENCES public.supported_blockchain(id);