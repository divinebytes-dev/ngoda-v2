-- Apply as migration owner after the application tables exist.
-- Scope: configuration audit tags stay independent; accounting fiscal identity is country-aware.
BEGIN;

-- Serialize schema changes and prevent writes from entering between preflight and FK replacement.
-- The migration is intended for QA provisioning or a maintenance window.
DO $locks$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT n.nspname,c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE (c.oid='public.fiscal_period_config'::regclass OR c.oid IN (
      SELECT conrelid FROM pg_constraint
      WHERE contype='f' AND confrelid='public.fiscal_period_config'::regclass
    )) ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE',r.nspname,r.relname);
  END LOOP;
END;
$locks$;

-- Configuration fiscal fields are audit tags: when the row was configured,
-- not the accounting calendar in which it is effective. Keep the stored
-- tags and valid-value checks; do not demand a matching calendar row.
-- The two central adjustment tables also retain the agreed countryless design.
-- No country columns are added, and no existing audit values are rewritten.
DO $global_checks$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_fee_splitting_config', 'aml_config', 'government_tax_config', 'loan_config', 'merchant_fee_splitting_config', 'referral_earnings_config', 'spread_config', 'transaction_limit', 'transaction_type_fee_config', 'reserve_asset_adjustment_request', 'tokenised_asset_adjustment_request', 'system_flag'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid=to_regclass(format('public.%I',t)) AND conname='ngoda_audit_fiscal_values_check') THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT ngoda_audit_fiscal_values_check CHECK (fiscal_year > 0 AND period BETWEEN 1 AND 12)',t);
    END IF;
  END LOOP;
END;
$global_checks$;

-- Retain the existing country-aware unique index. It is the new referenced identity.
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_period_config_country_code_fiscal_year_period_key
  ON public.fiscal_period_config(country_code,fiscal_year,period);

-- Remove calendar membership constraints from audit-only configurations even
-- if a prior review step already made one of those FKs country-aware.
DO $remove_audit_links$
DECLARE r record;
BEGIN
  FOR r IN SELECT k.conname,n.nspname,c.relname FROM pg_constraint k
    JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE k.contype='f' AND k.confrelid='public.fiscal_period_config'::regclass
      AND n.nspname='public'
      AND c.relname = ANY (ARRAY['agent_fee_splitting_config','aml_config','government_tax_config','loan_config','merchant_fee_splitting_config','referral_earnings_config','spread_config','transaction_limit','transaction_type_fee_config','reserve_asset_adjustment_request','tokenised_asset_adjustment_request'])
  LOOP
    EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I',r.nspname,r.relname,r.conname);
  END LOOP;
END;
$remove_audit_links$;

DO $replace_fks$
DECLARE
  r record;
  year_att smallint;
  period_att smallint;
  country_column text;
  invalid_count bigint;
  update_action text;
  delete_action text;
  deferrability text;
BEGIN
  SELECT attnum INTO STRICT year_att FROM pg_attribute
    WHERE attrelid='public.fiscal_period_config'::regclass AND attname='fiscal_year' AND NOT attisdropped;
  SELECT attnum INTO STRICT period_att FROM pg_attribute
    WHERE attrelid='public.fiscal_period_config'::regclass AND attname='period' AND NOT attisdropped;

  -- Only replace references to the old two-column fiscal identity.
  -- FK names, ON UPDATE/DELETE behavior and deferrability are retained.
  FOR r IN
    SELECT k.*, n.nspname,c.relname
    FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE k.contype='f' AND k.confrelid='public.fiscal_period_config'::regclass
      AND cardinality(k.confkey)=2
      AND k.confkey @> ARRAY[year_att,period_att]::smallint[]
    ORDER BY n.nspname,c.relname,k.conname
  LOOP
    IF r.nspname <> 'public' THEN
      RAISE EXCEPTION 'UNREVIEWED_FISCAL_REFERENCE_SCHEMA: %.%',r.nspname,r.relname;
    END IF;
    -- Do not reinterpret an unexpected FK that maps other columns to year/period.
    IF NOT EXISTS (
      SELECT 1 FROM unnest(r.conkey,r.confkey) AS keys(child_att,parent_att)
      JOIN pg_attribute a ON a.attrelid=r.conrelid AND a.attnum=keys.child_att
      GROUP BY r.conrelid
      HAVING bool_and((keys.parent_att=year_att AND a.attname='fiscal_year')
                    OR (keys.parent_att=period_att AND a.attname='period'))
    ) THEN
      RAISE EXCEPTION 'UNEXPECTED_FISCAL_REFERENCE_COLUMNS: %.%',r.relname,r.conname;
    END IF;

    IF r.relname = ANY (ARRAY['agent_fee_splitting_config', 'aml_config', 'government_tax_config', 'loan_config', 'merchant_fee_splitting_config', 'referral_earnings_config', 'spread_config', 'transaction_limit', 'transaction_type_fee_config', 'reserve_asset_adjustment_request', 'tokenised_asset_adjustment_request']) THEN
      -- Audit tags on configurations are independent of accounting calendars.
      -- Central adjustment requests also keep their existing countryless design.
      EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I',r.nspname,r.relname,r.conname);
      CONTINUE;
    ELSIF EXISTS (SELECT 1 FROM pg_attribute
      WHERE attrelid=r.conrelid AND attname='country_code' AND NOT attisdropped)
    THEN
      country_column := 'country_code';
    ELSE
      RAISE EXCEPTION 'FISCAL_REFERENCE_COUNTRY_NOT_CONFIGURED: %',r.relname;
    END IF;

    EXECUTE format(
      'SELECT count(*) FROM %I.%I child WHERE child.fiscal_year IS NOT NULL AND child.period IS NOT NULL AND (child.%I IS NULL OR NOT EXISTS (SELECT 1 FROM public.fiscal_period_config parent WHERE parent.country_code=child.%I AND parent.fiscal_year=child.fiscal_year AND parent.period=child.period))',
      r.nspname,r.relname,country_column,country_column
    ) INTO invalid_count;
    IF invalid_count > 0 THEN
      RAISE EXCEPTION 'COUNTRY_FISCAL_PERIOD_MISSING: table %, unmatched rows %',r.relname,invalid_count
        USING HINT='Provision the correct country periods or reconcile the affected rows. This migration does not reassign historical country values.';
    END IF;

    update_action := CASE r.confupdtype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
      WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END;
    delete_action := CASE r.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
      WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END;
    deferrability := CASE WHEN r.condeferrable THEN
      CASE WHEN r.condeferred THEN 'DEFERRABLE INITIALLY DEFERRED' ELSE 'DEFERRABLE INITIALLY IMMEDIATE' END
      ELSE 'NOT DEFERRABLE' END;
    -- The supplied fiscal FKs all use MATCH SIMPLE.
    IF r.confmatchtype <> 's' THEN RAISE EXCEPTION 'UNREVIEWED_FISCAL_MATCH_TYPE: %',r.conname; END IF;
    EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I',r.nspname,r.relname,r.conname);
    EXECUTE format(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I,fiscal_year,period) REFERENCES public.fiscal_period_config(country_code,fiscal_year,period) ON UPDATE %s ON DELETE %s %s',
      r.nspname,r.relname,r.conname,country_column,update_action,delete_action,deferrability);
  END LOOP;
END;
$replace_fks$;

-- Drop only unconditional two-key uniqueness for the old GLOBAL identity.
-- No CASCADE. Unexpected dependencies abort the transaction rather than removing protections.
DO $remove_global_key$
DECLARE r record; year_att smallint; period_att smallint;
BEGIN
  SELECT attnum INTO STRICT year_att FROM pg_attribute
    WHERE attrelid='public.fiscal_period_config'::regclass AND attname='fiscal_year' AND NOT attisdropped;
  SELECT attnum INTO STRICT period_att FROM pg_attribute
    WHERE attrelid='public.fiscal_period_config'::regclass AND attname='period' AND NOT attisdropped;
  FOR r IN SELECT conname FROM pg_constraint
    WHERE conrelid='public.fiscal_period_config'::regclass AND contype='u'
      AND cardinality(conkey)=2 AND conkey @> ARRAY[year_att,period_att]::smallint[]
  LOOP
    EXECUTE format('ALTER TABLE public.fiscal_period_config DROP CONSTRAINT %I',r.conname);
  END LOOP;
  FOR r IN SELECT ni.nspname,i.relname
    FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
    JOIN pg_namespace ni ON ni.oid=i.relnamespace
    WHERE x.indrelid='public.fiscal_period_config'::regclass
      AND x.indisunique AND NOT x.indisprimary AND x.indpred IS NULL
      AND x.indexprs IS NULL AND x.indnkeyatts=2
      AND ((x.indkey[0]=year_att AND x.indkey[1]=period_att)
        OR (x.indkey[0]=period_att AND x.indkey[1]=year_att))
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid=x.indexrelid)
  LOOP
    EXECUTE format('DROP INDEX %I.%I',r.nspname,r.relname);
  END LOOP;
END;
$remove_global_key$;

COMMIT;
