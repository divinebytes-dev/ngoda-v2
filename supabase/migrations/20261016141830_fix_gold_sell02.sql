ALTER TABLE public.liquidation_job
ADD COLUMN IF NOT EXISTS blockchain_code text;