-- Configuration history: one ACTIVE row per existing logical scope.
-- Fiscal year/month remain audit tags and are not part of active selection.
-- No configuration rows/values/statuses are rewritten or deleted.
BEGIN;
DO $migration$
DECLARE
  cfg record;
  idx record;
  duplicate_groups bigint;
  column_sql text;
  expected_old_columns text[];
  scope_columns text[];
BEGIN
  -- Stable lock order, covering the same eleven explicitly reviewed tables.
  FOR cfg IN SELECT * FROM (VALUES
    ('agent_fee_splitting_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('aml_config',ARRAY['transaction_type','country_code','currency_code']::text[]),
    ('government_tax_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('loan_config',ARRAY['country_code','config_type']::text[]),
    ('maximum_tap_payment_amount_config',ARRAY['country_code','currency_code']::text[]),
    ('merchant_fee_splitting_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('referral_earnings_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('spread_config',ARRAY['asset','direction']::text[]),
    ('system_flag',ARRAY['country_code','flag_name']::text[]),
    ('transaction_limit',ARRAY['transaction_type','country_code','currency_code']::text[]),
    ('transaction_type_fee_config',ARRAY['country_code','transaction_type','currency_code']::text[])
  ) AS configurations(table_name,key_columns) ORDER BY table_name
  LOOP
    IF to_regclass(format('public.%I',cfg.table_name)) IS NULL THEN
      RAISE EXCEPTION 'CONFIGURATION_TABLE_MISSING: %',cfg.table_name;
    END IF;
    EXECUTE format('LOCK TABLE public.%I IN ACCESS EXCLUSIVE MODE',cfg.table_name);
  END LOOP;

  FOR cfg IN SELECT * FROM (VALUES
    ('agent_fee_splitting_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('aml_config',ARRAY['transaction_type','country_code','currency_code']::text[]),
    ('government_tax_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('loan_config',ARRAY['country_code','config_type']::text[]),
    ('maximum_tap_payment_amount_config',ARRAY['country_code','currency_code']::text[]),
    ('merchant_fee_splitting_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('referral_earnings_config',ARRAY['country_code','transaction_type','currency_code']::text[]),
    ('spread_config',ARRAY['asset','direction']::text[]),
    ('system_flag',ARRAY['country_code','flag_name']::text[]),
    ('transaction_limit',ARRAY['transaction_type','country_code','currency_code']::text[]),
    ('transaction_type_fee_config',ARRAY['country_code','transaction_type','currency_code']::text[])
  ) AS configurations(table_name,key_columns) ORDER BY table_name
  LOOP
    SELECT string_agg(quote_ident(c),',' ORDER BY n) INTO column_sql
    FROM unnest(cfg.key_columns) WITH ORDINALITY AS key(c,n);
    EXECUTE format(
      'SELECT count(*) FROM (SELECT %s FROM public.%I WHERE is_active=true GROUP BY %s HAVING count(*)>1) duplicates',
      column_sql,cfg.table_name,column_sql
    ) INTO duplicate_groups;
    IF duplicate_groups>0 THEN
      RAISE EXCEPTION 'DUPLICATE_ACTIVE_CONFIGURATIONS: table %, scopes %',cfg.table_name,duplicate_groups
        USING HINT='Review which configuration is current; this migration does not choose or deactivate rows automatically.';
    END IF;

    -- Add the replacement first so uniqueness is continuously enforced.
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON public.%I (%s) WHERE is_active=true',
      cfg.table_name || '_active_scope_unique',cfg.table_name,column_sql);

    SELECT array_agg(c ORDER BY c) INTO scope_columns FROM unnest(cfg.key_columns) AS key(c);
    -- Fail rather than trust an unrelated preexisting index with our name.
    IF NOT EXISTS (
      SELECT 1 FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
      WHERE x.indrelid=to_regclass(format('public.%I',cfg.table_name))
        AND i.relname=cfg.table_name || '_active_scope_unique'
        AND x.indisunique AND x.indisvalid AND x.indexprs IS NULL
        AND pg_get_expr(x.indpred,x.indrelid)='(is_active = true)'
        AND x.indnkeyatts=cardinality(cfg.key_columns)
        AND (SELECT array_agg(att.attname::text ORDER BY att.attname::text)
          FROM unnest(x.indkey::smallint[]) WITH ORDINALITY AS keys(attnum,n)
          JOIN pg_attribute att ON att.attrelid=x.indrelid AND att.attnum=keys.attnum
          WHERE keys.n<=x.indnkeyatts)=scope_columns
    ) THEN
      RAISE EXCEPTION 'ACTIVE_CONFIGURATION_INDEX_MISMATCH: %',cfg.table_name;
    END IF;

    SELECT array_agg(c ORDER BY c) INTO expected_old_columns
    FROM unnest(cfg.key_columns || ARRAY['is_active']::text[]) AS key(c);
    -- Remove only the old unconditional scope+is_active uniqueness.
    -- Leave primary keys, identifiers, other scopes and new partial indexes intact.
    FOR idx IN
      SELECT x.indexrelid,i.relname,n.nspname,k.conname
      FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
      JOIN pg_namespace n ON n.oid=i.relnamespace
      LEFT JOIN pg_constraint k ON k.conindid=x.indexrelid AND k.contype='u'
      WHERE x.indrelid=to_regclass(format('public.%I',cfg.table_name))
        AND x.indisunique AND NOT x.indisprimary
        AND x.indpred IS NULL AND x.indexprs IS NULL
        AND x.indnkeyatts=cardinality(expected_old_columns)
        AND (SELECT array_agg(att.attname::text ORDER BY att.attname::text)
          FROM unnest(x.indkey::smallint[]) WITH ORDINALITY AS keys(attnum,n)
          JOIN pg_attribute att ON att.attrelid=x.indrelid AND att.attnum=keys.attnum
          WHERE keys.n<=x.indnkeyatts)=expected_old_columns
    LOOP
      IF idx.conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',cfg.table_name,idx.conname);
      ELSE
        EXECUTE format('DROP INDEX %I.%I',idx.nspname,idx.relname);
      END IF;
    END LOOP;
  END LOOP;
END;
$migration$;
COMMIT;
