CREATE OR REPLACE FUNCTION public.create_weekly_agent_commission_batch(p_country_code text, p_currency_code text, p_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_country text := lower(nullif(btrim(p_country_code), ''));
  v_currency text := lower(nullif(btrim(p_currency_code), ''));
  v_zone text;
  v_start timestamptz;
  v_end timestamptz;
  v_ids text[];
  v_batch public.agent_settlement_batch%rowtype;
  v_fiscal record;
  v_total numeric;
  v_agents integer;
  v_count integer;
  v_assigned integer;
  v_items integer;
  v_document text;
BEGIN
  IF v_country IS NULL OR v_currency IS NULL OR p_week_start IS NULL
     OR NOT isfinite(p_week_start) OR extract(isodow FROM p_week_start) <> 1 THEN
    RAISE EXCEPTION 'INVALID_WEEKLY_COMMISSION_PARAMETERS';
  END IF;
  SELECT time_zone INTO v_zone FROM public.operational_country
  WHERE country_code = v_country AND is_active = true;
  IF v_zone IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_zone
  ) THEN RAISE EXCEPTION 'INVALID_ACTIVE_COUNTRY_TIME_ZONE_%', v_country; END IF;

  PERFORM 1 FROM public.country_currencies cc
  JOIN public.supported_currency sc ON sc.currency_code = cc.currency_code
  WHERE cc.country_code = v_country AND cc.currency_code = v_currency
    AND cc.is_active AND sc.is_active
    AND sc.currency_category = 'fiat'::public."CurrencyCategory";
  IF NOT FOUND THEN RAISE EXCEPTION 'COMMISSION_CURRENCY_NOT_ACTIVE'; END IF;

  v_start := p_week_start::timestamp AT TIME ZONE v_zone;
  v_end := (p_week_start + 7)::timestamp AT TIME ZONE v_zone;
  IF v_end > statement_timestamp() THEN RAISE EXCEPTION 'COMMISSION_WEEK_NOT_COMPLETE'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    format('weekly-agent-commission:%s:%s', v_country, v_currency), 0
  ));

  -- A batch for this exact week is reused regardless of its payment status.
  SELECT * INTO v_batch FROM public.agent_settlement_batch b
  WHERE b.country_code = v_country AND b.currency_code = v_currency
    AND b.start_date::date = p_week_start
    AND b.end_date::date = p_week_start + 6
  ORDER BY b.created_at, b.id LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success', true, 'already_created', true,
      'batch_id', v_batch.id, 'document_number', v_batch.document_number);
  END IF;

  -- Do not silently split an existing historical/manual assignment.
  PERFORM 1 FROM public.agent_commission c
  WHERE c.country_code = v_country AND c.currency_code = v_currency
    AND c.created_at >= v_start AND c.created_at < v_end
    AND c.is_settled = false AND c.settlement_batch_id IS NOT NULL;
  IF FOUND THEN RAISE EXCEPTION 'COMMISSION_WEEK_HAS_EXISTING_BATCH_ASSIGNMENTS_%_%_%',
    v_country, v_currency, p_week_start; END IF;

  SELECT array_agg(q.id ORDER BY q.id) INTO v_ids FROM (
    SELECT c.id FROM public.agent_commission c
    WHERE c.country_code = v_country AND c.currency_code = v_currency
      AND c.created_at >= v_start AND c.created_at < v_end
      AND c.is_settled = false AND c.settlement_batch_id IS NULL
    ORDER BY c.id FOR UPDATE
  ) q;
  IF coalesce(cardinality(v_ids), 0) = 0 THEN
    RETURN jsonb_build_object('success', true, 'no_commissions', true);
  END IF;
  SELECT count(*)::integer, count(DISTINCT c.agent_id)::integer,
         sum(c.commission_amount)
  INTO v_count, v_agents, v_total FROM public.agent_commission c WHERE c.id = ANY(v_ids);
  IF v_total = 0 THEN RETURN jsonb_build_object('success', true, 'no_commissions', true); END IF;
  IF v_agents < 1 OR v_total IS NULL OR v_total < 0
     OR v_total::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'INVALID_AGENT_COMMISSION_SETTLEMENT_TOTAL';
  END IF;

  -- The week can span multiple accounting periods. Preserve the existing
  -- convention: header/items use the fiscal period at batch creation time.
  -- No requirement to close that fiscal period for a weekly batch.
  SELECT * INTO STRICT v_fiscal FROM public.fetch_fiscal_period(
    v_country, statement_timestamp() AT TIME ZONE v_zone
  );
  v_document := public.generate_document_number(
    'AGENT-COMM', v_fiscal.fiscal_year, v_fiscal.period, v_country
  );
  INSERT INTO public.agent_settlement_batch (
    document_number, fiscal_year, period, currency_code, country_code,
    start_date, end_date, total_agents, total_amount, created_by, status
  ) VALUES (
    v_document, v_fiscal.fiscal_year, v_fiscal.period, v_currency, v_country,
    p_week_start::timestamp, (p_week_start + 7)::timestamp - interval '1 second',
    v_agents, v_total, 'system:weekly-agent-commission', 'draft'
  ) RETURNING * INTO v_batch;

  INSERT INTO public.agent_settlement_item (
    batch_id, agent_id, fiscal_year, period, currency_code, country_code,
    total_commission, total_withdrawal_volume, total_fees_generated, status
  ) SELECT v_batch.id, c.agent_id, v_fiscal.fiscal_year, v_fiscal.period,
    v_currency, v_country, sum(c.commission_amount), sum(c.amount),
    sum(c.fee_amount), 'draft'
  FROM public.agent_commission c WHERE c.id = ANY(v_ids) GROUP BY c.agent_id;
  GET DIAGNOSTICS v_items = ROW_COUNT;
  IF v_items <> v_agents THEN RAISE EXCEPTION 'AGENT_SETTLEMENT_ITEM_COUNT_MISMATCH'; END IF;

  UPDATE public.agent_commission SET settlement_batch_id = v_batch.id
  WHERE id = ANY(v_ids) AND is_settled = false AND settlement_batch_id IS NULL;
  GET DIAGNOSTICS v_assigned = ROW_COUNT;
  IF v_assigned <> v_count THEN RAISE EXCEPTION 'AGENT_COMMISSION_ASSIGNMENT_COUNT_MISMATCH'; END IF;
  RETURN jsonb_build_object('success', true, 'already_created', false,
    'batch_id', v_batch.id, 'document_number', v_document, 'currency_code', v_currency,
    'week_start', p_week_start, 'week_end', p_week_start + 6,
    'total_agents', v_agents, 'total_amount', v_total::text, 'commission_count', v_count);
END;
$function$
