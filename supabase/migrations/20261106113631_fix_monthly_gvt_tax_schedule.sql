CREATE OR REPLACE FUNCTION public.run_monthly_government_tax_batches()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_country record;
  v_currency record;
  v_source public.fiscal_period_config%rowtype;
  v_local_now timestamp without time zone;
  v_source_date date;
  v_ids text[];
  v_batch_id text;
  v_document text;
  v_prefix text;
  v_gross numeric;
  v_tax numeric;
  v_count integer;
  v_assigned integer;
  v_created integer := 0;
  v_existing integer := 0;
  v_empty integer := 0;
BEGIN
  -- Prevent concurrent scheduler/manual SQL runs from overlapping.
  IF NOT pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('ngoda:monthly-government-tax-job', 0)
  ) THEN
    RETURN jsonb_build_object('success', true, 'already_running', true);
  END IF;

  FOR v_country IN
    SELECT country_code, time_zone
    FROM public.operational_country
    WHERE is_active = true
    ORDER BY country_code
  LOOP
    IF nullif(btrim(v_country.time_zone), '') IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM pg_catalog.pg_timezone_names tz
         WHERE tz.name = v_country.time_zone
       ) THEN
      RAISE EXCEPTION 'INVALID_COUNTRY_TIME_ZONE_%', v_country.country_code;
    END IF;

    v_local_now := statement_timestamp() AT TIME ZONE v_country.time_zone;

    -- First attempt at 03:00; retries through the rest of the first local day.
    IF extract(day FROM v_local_now) <> 1
       OR v_local_now::time < time '03:00' THEN
      CONTINUE;
    END IF;

    v_source_date := date_trunc('month', v_local_now)::date - 1;

    -- Use the calendar's actual fiscal identity; do not assume fiscal year
    -- numbering equals the calendar year. Ambiguity must fail visibly.
    BEGIN
      SELECT f.* INTO STRICT v_source
      FROM public.fiscal_period_config f
      WHERE f.country_code = v_country.country_code
        AND f.opening_date <= v_source_date::timestamp
        AND f.closing_date >= v_source_date::timestamp
      FOR SHARE;
    EXCEPTION
      WHEN no_data_found THEN
        RAISE EXCEPTION 'PREVIOUS_FISCAL_PERIOD_NOT_FOUND_%_%',
          v_country.country_code, v_source_date;
      WHEN too_many_rows THEN
        RAISE EXCEPTION 'AMBIGUOUS_PREVIOUS_FISCAL_PERIOD_%_%',
          v_country.country_code, v_source_date;
    END;


    FOR v_currency IN
      SELECT cc.currency_code
      FROM public.country_currencies cc
      JOIN public.supported_currency sc
        ON sc.currency_code = cc.currency_code
      WHERE cc.country_code = v_country.country_code
        AND cc.is_active = true AND sc.is_active = true
        AND sc.currency_category = 'fiat'::public."CurrencyCategory"
      ORDER BY cc.currency_code
    LOOP
      -- Same lock namespace as the old manual creator during transition.
      PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          format('government-tax-settlement:%s:%s',
            v_country.country_code, v_currency.currency_code), 0
        )
      );

      -- Status deliberately irrelevant: a paid, failed or unpaid batch for
      -- THIS source period prevents a duplicate. Other periods never block it.
      PERFORM 1 FROM public.government_tax_settlement_batch b
      WHERE b.country_code = v_country.country_code
        AND b.currency_code = v_currency.currency_code
        AND b.fiscal_year = v_source.fiscal_year
        AND b.period = v_source.period;
      IF FOUND THEN
        v_existing := v_existing + 1;
        CONTINUE;
      END IF;

      SELECT array_agg(locked.id ORDER BY locked.id) INTO v_ids
      FROM (
        SELECT t.id
        FROM public.government_tax_payable t
        WHERE t.country_code = v_country.country_code
          AND t.currency_code = v_currency.currency_code
          AND t.fiscal_year = v_source.fiscal_year
          AND t.period = v_source.period
          AND t.is_settled = false AND t.settlement_batch_id IS NULL
        ORDER BY t.id FOR UPDATE
      ) locked;

      IF coalesce(cardinality(v_ids), 0) = 0 THEN
        v_empty := v_empty + 1;
        CONTINUE;
      END IF;

      SELECT count(*)::integer, sum(t.gross_amount), sum(t.tax_amount)
      INTO v_count, v_gross, v_tax
      FROM public.government_tax_payable t WHERE t.id = ANY(v_ids);

      -- No amount is payable when all selected tax amounts are zero.
      IF v_tax = 0 THEN
        v_empty := v_empty + 1;
        CONTINUE;
      END IF;
      IF v_tax IS NULL OR v_tax < 0 OR v_tax::text IN ('NaN','Infinity','-Infinity') THEN
        RAISE EXCEPTION 'INVALID_GOVERNMENT_TAX_SETTLEMENT_TOTAL';
      END IF;

      v_prefix := public.fetch_transaction_doc_num_prefix(
        'government_tax_clearing'::public."TransactionType"
      );
      IF nullif(btrim(v_prefix), '') IS NULL THEN
        RAISE EXCEPTION 'DOCUMENT_PREFIX_NOT_FOUND';
      END IF;
      v_document := public.generate_document_number(
        v_prefix, v_source.fiscal_year, v_source.period, v_country.country_code
      );

      INSERT INTO public.government_tax_settlement_batch (
        document_number, fiscal_year, period, currency_code, country_code,
        start_date, end_date, total_amount, status, created_by
      ) VALUES (
        v_document, v_source.fiscal_year, v_source.period,
        v_currency.currency_code, v_country.country_code,
        v_source.opening_date, v_source.closing_date, v_tax, 'draft',
        'system:monthly-government-tax'
      ) RETURNING id INTO v_batch_id;

      INSERT INTO public.government_tax_settlement_item (
        batch_id, transaction_type, fiscal_year, period, currency_code,
        country_code, gross_amount, tax_amount, status
      )
      SELECT v_batch_id, t.transaction_type, v_source.fiscal_year,
        v_source.period, v_currency.currency_code, v_country.country_code,
        sum(t.gross_amount), sum(t.tax_amount), 'draft'
      FROM public.government_tax_payable t
      WHERE t.id = ANY(v_ids)
      GROUP BY t.transaction_type;

      UPDATE public.government_tax_payable
      SET settlement_batch_id = v_batch_id
      WHERE id = ANY(v_ids) AND settlement_batch_id IS NULL AND is_settled = false;
      GET DIAGNOSTICS v_assigned = ROW_COUNT;
      IF v_assigned <> v_count THEN
        RAISE EXCEPTION 'GOVERNMENT_TAX_PAYABLE_ASSIGNMENT_COUNT_MISMATCH';
      END IF;

      v_created := v_created + 1;
      RAISE LOG 'MONTHLY_GOVERNMENT_TAX_BATCH_CREATED country=% currency=% fiscal_year=% period=% batch=% tax=%',
        v_country.country_code, v_currency.currency_code,
        v_source.fiscal_year, v_source.period, v_batch_id, v_tax;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'created', v_created,
    'already_created', v_existing, 'no_tax', v_empty);
END;
$function$
