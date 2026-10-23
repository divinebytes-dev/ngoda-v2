BEGIN;

CREATE OR REPLACE FUNCTION public.fetch_my_current_week_agent_commissions(
  p_currency_code text DEFAULT NULL,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 50,
  p_as_of timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user public.users%rowtype;
  v_zone text;
  v_week timestamp;
  v_start timestamptz;
  v_end timestamptz;
  v_as_of timestamptz := coalesce(p_as_of, statement_timestamp());
  v_currency text := lower(nullif(btrim(p_currency_code), ''));
  v_currencies jsonb;
  v_items jsonb;
  v_count bigint;
  v_pages bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode='42501', message='UNAUTHORIZED';
  END IF;
  IF NOT public.has_role(ARRAY['accounts']::text[]) THEN
    RAISE EXCEPTION USING errcode='42501', message='FORBIDDEN';
  END IF;
  SELECT * INTO v_user FROM public.users
  WHERE id = auth.uid()::text AND status = 'active'::public."UserStatus";
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNTS_USER_NOT_ACTIVE_OR_NOT_FOUND'; END IF;
  IF p_page IS NULL OR p_page < 1 THEN RAISE EXCEPTION 'INVALID_PAGE'; END IF;
  IF p_page_size IS NULL OR p_page_size < 1 OR p_page_size > 100 THEN
    RAISE EXCEPTION 'INVALID_PAGE_SIZE'; END IF;
  IF NOT isfinite(v_as_of) OR v_as_of > statement_timestamp() THEN
    RAISE EXCEPTION 'INVALID_AS_OF'; END IF;
  SELECT time_zone INTO v_zone FROM public.operational_country
  WHERE country_code = v_user.country_code AND is_active;
  IF v_zone IS NULL THEN RAISE EXCEPTION 'ACTIVE_COUNTRY_TIME_ZONE_REQUIRED'; END IF;
  v_week := date_trunc('week', statement_timestamp() AT TIME ZONE v_zone);
  v_start := v_week AT TIME ZONE v_zone;
  v_end := (v_week + interval '7 days') AT TIME ZONE v_zone;
  IF v_as_of < v_start THEN RAISE EXCEPTION 'COMMISSION_WEEK_CHANGED_REFRESH_REQUIRED'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'currency_code', cc.currency_code,
    'total_transaction_amount', coalesce(a.volume, 0)::text,
    'total_fee_amount', coalesce(a.fees, 0)::text,
    'total_commission_amount', coalesce(a.commission, 0)::text,
    'paid_commission_amount', coalesce(a.paid, 0)::text,
    'pending_commission_amount', coalesce(a.pending, 0)::text,
    'commission_count', coalesce(a.n, 0),
    'paid_count', coalesce(a.paid_count, 0),
    'pending_count', coalesce(a.pending_count, 0)
  ) ORDER BY cc.currency_code), '[]'::jsonb) INTO v_currencies
  FROM public.country_currencies cc
  JOIN public.supported_currency sc ON sc.currency_code = cc.currency_code
  LEFT JOIN LATERAL (
    SELECT sum(c.amount) volume, sum(c.fee_amount) fees,
      sum(c.commission_amount) commission,
      sum(c.commission_amount) FILTER (WHERE c.is_settled) paid,
      sum(c.commission_amount) FILTER (WHERE NOT c.is_settled) pending,
      count(*) n, count(*) FILTER (WHERE c.is_settled) paid_count,
      count(*) FILTER (WHERE NOT c.is_settled) pending_count
    FROM public.agent_commission c
    WHERE c.country_code = v_user.country_code AND c.currency_code = cc.currency_code
      AND c.created_at >= v_start AND c.created_at < v_end AND c.created_at <= v_as_of
  ) a ON true
  WHERE cc.country_code = v_user.country_code AND cc.is_active AND sc.is_active
    AND sc.currency_category = 'fiat'::public."CurrencyCategory";

  IF v_currency IS NULL THEN v_currency := v_currencies -> 0 ->> 'currency_code';
  ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_currencies) c
    WHERE c ->> 'currency_code' = v_currency) THEN
    RAISE EXCEPTION 'COMMISSION_CURRENCY_NOT_ACTIVE';
  END IF;
  SELECT count(*) INTO v_count FROM public.agent_commission c
  WHERE c.country_code = v_user.country_code AND c.currency_code = v_currency
    AND c.created_at >= v_start AND c.created_at < v_end AND c.created_at <= v_as_of;
  v_pages := greatest(1::bigint, (v_count + p_page_size - 1) / p_page_size);
  IF p_page > v_pages THEN RAISE EXCEPTION 'PAGE_OUT_OF_RANGE'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'agent_id', c.agent_id, 'agent_email', u.email,
    'document_number', c.document_number, 'reference', c.reference,
    'transaction_type', c.transaction_type, 'currency_code', c.currency_code,
    'amount', c.amount::text, 'fee_amount', c.fee_amount::text,
    'commission_rate', c.commission_rate::text,
    'commission_amount', c.commission_amount::text,
    'is_settled', c.is_settled,
    'status', CASE WHEN c.is_settled THEN 'paid' ELSE 'pending' END,
    'settled_at', c.settled_at, 'created_at', c.created_at,
    'settlement_batch_id', c.settlement_batch_id
  ) ORDER BY c.created_at DESC, c.id DESC), '[]'::jsonb) INTO v_items
  FROM (
    SELECT a.* FROM public.agent_commission a
    WHERE a.country_code = v_user.country_code AND a.currency_code = v_currency
      AND a.created_at >= v_start AND a.created_at < v_end AND a.created_at <= v_as_of
    ORDER BY a.created_at DESC, a.id DESC
    LIMIT p_page_size OFFSET ((p_page::bigint - 1) * p_page_size)
  ) c LEFT JOIN public.users u ON u.id = c.agent_id;

  RETURN jsonb_build_object('country_code', v_user.country_code,
    'week_start', v_week::date, 'week_end', (v_week + interval '6 days')::date,
    'as_of', v_as_of, 'currency', v_currency, 'currencies', v_currencies,
    'items', v_items, 'pagination', jsonb_build_object('page', p_page,
      'pageSize', p_page_size, 'totalEntries', v_count, 'totalPages', v_pages,
      'hasPrevious', p_page > 1, 'hasNext', p_page < v_pages));
END;
$function$;
ALTER FUNCTION public.fetch_my_current_week_agent_commissions(text,integer,integer,timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_my_current_week_agent_commissions(text,integer,integer,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_current_week_agent_commissions(text,integer,integer,timestamptz)
TO authenticated;

CREATE INDEX IF NOT EXISTS ngoda_agent_commission_week_paging_idx
ON public.agent_commission(country_code, currency_code, created_at DESC, id DESC);

COMMIT;
