UPDATE public.wallet
SET blockchain_id = (
    SELECT id
    FROM public.supported_blockchain
    WHERE code = 'gnosis'
)
WHERE currency_code = 'gold';

UPDATE public.wallet_balance_snapshot
SET blockchain_id = (
    SELECT id
    FROM public.supported_blockchain
    WHERE code = 'gnosis'
)
WHERE currency_code = 'gold';