ALTER TABLE public.supported_blockchain
ADD COLUMN IF NOT EXISTS contract_address text;

UPDATE public.supported_blockchain
SET contract_address = '0x1824a96A6A17C15641F76a113A098945c0D75F43',
    updated_at = now()
WHERE code = 'gnosis';