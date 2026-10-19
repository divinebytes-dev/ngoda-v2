-- QA master data proposal: VERIFIED caps = 5x supplied pending caps; minimum stays 1.
-- KYC verification code uses verified, not completed. No approved/completed aliases.
-- Run AFTER fiscal-audit, active-history and KYC-specific limit-index corrections.
BEGIN;
LOCK TABLE public.transaction_limit IN SHARE ROW EXCLUSIVE MODE;
DO $seed$
DECLARE
  cfg record;
  previous public.transaction_limit%rowtype;
  audit_year integer := extract(year FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  audit_period integer := extract(month FROM current_timestamp AT TIME ZONE 'UTC')::integer;
  inserted_count integer := 0;
  archived_count integer := 0;
  unchanged_count integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index x WHERE x.indrelid='public.transaction_limit'::regclass
      AND x.indisunique AND x.indisvalid AND x.indexprs IS NULL AND x.indnkeyatts=4
      AND pg_get_expr(x.indpred,x.indrelid)='(is_active = true)'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
        FROM unnest(x.indkey::smallint[]) WITH ORDINALITY keys(attnum,n)
        JOIN pg_attribute a ON a.attrelid=x.indrelid AND a.attnum=keys.attnum
        WHERE keys.n<=x.indnkeyatts)
        = ARRAY['country_code','currency_code','kyc_status','transaction_type']::text[]
  ) THEN RAISE EXCEPTION 'KYC_SPECIFIC_ACTIVE_LIMIT_INDEX_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transaction_limit'::regclass
    AND contype='f' AND confrelid=to_regclass('public.fiscal_period_config'))
  THEN RAISE EXCEPTION 'APPLY_CONFIGURATION_FISCAL_AUDIT_CORRECTION_FIRST'; END IF;

  FOR cfg IN SELECT * FROM (VALUES
      ('bw','cash_deposit','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('bw','cash_transfer','bwp',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('bw','cash_withdrawal','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','usd',1::numeric,500::numeric,2500::numeric,5000::numeric),
      ('zw','cash_deposit','zar',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_deposit','zig',1::numeric,500::numeric,2500::numeric,5000::numeric),
      ('zw','cash_transfer','bwp',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('zw','cash_transfer','usd',1::numeric,2500::numeric,5000::numeric,25000::numeric),
      ('zw','cash_transfer','zar',1::numeric,25000::numeric,50000::numeric,100000::numeric),
      ('zw','cash_transfer','zig',1::numeric,25000::numeric,50000::numeric,250000::numeric),
      ('zw','cash_withdrawal','bwp',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_withdrawal','usd',1::numeric,2500::numeric,5000::numeric,25000::numeric),
      ('zw','cash_withdrawal','zar',1::numeric,10000::numeric,25000::numeric,100000::numeric),
      ('zw','cash_withdrawal','zig',1::numeric,25000::numeric,50000::numeric,250000::numeric)
  ) AS proposed(country_code,transaction_type,currency_code,min_amount,max_amount,daily_limit,monthly_limit)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.operational_country c WHERE c.country_code=cfg.country_code) THEN
      RAISE EXCEPTION 'SEED_COUNTRY_REQUIRED: %',cfg.country_code;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.supported_currency c WHERE c.currency_code=cfg.currency_code) THEN
      RAISE EXCEPTION 'SEED_CURRENCY_REQUIRED: %',cfg.currency_code;
    END IF;

    SELECT * INTO previous FROM public.transaction_limit t
    WHERE t.country_code=cfg.country_code
      AND t.transaction_type=cfg.transaction_type::public."TransactionType"
      AND t.currency_code=cfg.currency_code
      AND t.kyc_status='verified'::public."KycStatus"
      AND t.is_active=true
    FOR UPDATE;

    IF FOUND THEN
      IF previous.min_amount IS NOT DISTINCT FROM cfg.min_amount
         AND previous.max_amount IS NOT DISTINCT FROM cfg.max_amount
         AND previous.daily_limit IS NOT DISTINCT FROM cfg.daily_limit
         AND previous.monthly_limit IS NOT DISTINCT FROM cfg.monthly_limit
      THEN
        unchanged_count := unchanged_count+1;
        CONTINUE;
      END IF;
      UPDATE public.transaction_limit SET is_active=false,updated_at=now(),updated_by='admin'
      WHERE id=previous.id;
      archived_count := archived_count+1;
    END IF;

    INSERT INTO public.transaction_limit (
      fiscal_year,period,country_code,transaction_type,currency_code,kyc_status,
      min_amount,max_amount,daily_limit,monthly_limit,is_active,created_by
    ) VALUES (
      audit_year,audit_period,cfg.country_code,cfg.transaction_type::public."TransactionType",
      cfg.currency_code,'verified'::public."KycStatus",cfg.min_amount,cfg.max_amount,
      cfg.daily_limit,cfg.monthly_limit,true,'admin'
    );
    inserted_count := inserted_count+1;
  END LOOP;
  RAISE NOTICE 'VERIFIED_LIMIT_SEED inserted=%, archived=%, unchanged=%',inserted_count,archived_count,unchanged_count;
END;
$seed$;
COMMIT;

SELECT country_code,transaction_type,currency_code,kyc_status,
       min_amount,max_amount,daily_limit,monthly_limit
FROM public.transaction_limit WHERE is_active=true AND kyc_status='verified'::public."KycStatus"
ORDER BY country_code,transaction_type,currency_code;
