ALTER TABLE public.tokenised_asset_adjustment_request
ADD COLUMN IF NOT EXISTS blockchain_code text;

ALTER TABLE public.blockchain_transaction
ADD COLUMN IF NOT EXISTS blockchain_code text;


ALTER TABLE public.tokenised_asset_adjustment_request
ADD CONSTRAINT token_adjustment_blockchain_code_fk
FOREIGN KEY (blockchain_code)
REFERENCES public.supported_blockchain(code);


