BEGIN;

-- Replace the earlier summary-only signature; do not leave RPC overloads.
DROP FUNCTION IF EXISTS public.fetch_my_current_government_tax();

CREATE OR REPLACE FUNCTION public.fetch_my_current_government_tax(
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
  v_fiscal record;
  v_zone text;
  v_currency text;
  v_currencies jsonb;
  v_items jsonb;
  v_count bigint;
  v_pages bigint;
  v_as_of timestamptz := coalesce(p_as_of, statement_timestamp());
  v_local_as_of timestamp without time zone;
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
    RAISE EXCEPTION 'INVALID_PAGE_SIZE';
  END IF;
  IF NOT isfinite(v_as_of) OR v_as_of > statement_timestamp() THEN
    RAISE EXCEPTION 'INVALID_AS_OF';
  END IF;

  SELECT time_zone INTO v_zone FROM public.operational_country
  WHERE country_code = v_user.country_code AND is_active = true;
  IF v_zone IS NULL THEN RAISE EXCEPTION 'ACTIVE_COUNTRY_TIME_ZONE_REQUIRED'; END IF;
  SELECT * INTO STRICT v_fiscal FROM public.fetch_fiscal_period(
    v_user.country_code, statement_timestamp() AT TIME ZONE v_zone
  );

  -- A paging timestamp cannot be used to select an earlier fiscal period.
  v_local_as_of := v_as_of AT TIME ZONE v_zone;
  IF NOT EXISTS (
    SELECT 1 FROM public.fiscal_period_config f
    WHERE f.country_code = v_user.country_code
      AND f.fiscal_year = v_fiscal.fiscal_year AND f.period = v_fiscal.period
      AND f.opening_date <= v_local_as_of AND f.closing_date >= v_local_as_of
  ) THEN
    RAISE EXCEPTION 'CURRENT_TAX_PERIOD_CHANGED_REFRESH_REQUIRED';
  END IF;

  -- All tabs and their totals use the same cutoff. Amounts remain separated
  -- by currency; totals are for the entire result, never just one page.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'currency_code', cc.currency_code,
    'total_gross_amount', coalesce(t.gross, 0)::text,
    'total_tax_amount', coalesce(t.tax, 0)::text,
    'payable_count', coalesce(t.n, 0)
  ) ORDER BY cc.currency_code), '[]'::jsonb) INTO v_currencies
  FROM public.country_currencies cc
  JOIN public.supported_currency sc ON sc.currency_code = cc.currency_code
  LEFT JOIN LATERAL (
    SELECT sum(p.gross_amount) gross, sum(p.tax_amount) tax, count(*) n
    FROM public.government_tax_payable p
    WHERE p.country_code = v_user.country_code
      AND p.currency_code = cc.currency_code
      AND p.fiscal_year = v_fiscal.fiscal_year AND p.period = v_fiscal.period
      AND p.created_at <= v_as_of
  ) t ON true
  WHERE cc.country_code = v_user.country_code AND cc.is_active = true
    AND sc.is_active = true AND sc.currency_category = 'fiat'::public."CurrencyCategory";

  v_currency := lower(nullif(btrim(p_currency_code), ''));
  IF v_currency IS NULL THEN
    v_currency := v_currencies -> 0 ->> 'currency_code';
  ELSIF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_currencies) c
    WHERE c ->> 'currency_code' = v_currency
  ) THEN
    RAISE EXCEPTION 'TAX_CURRENCY_NOT_ACTIVE';
  END IF;

  SELECT count(*) INTO v_count FROM public.government_tax_payable p
  WHERE p.country_code = v_user.country_code AND p.currency_code = v_currency
    AND p.fiscal_year = v_fiscal.fiscal_year AND p.period = v_fiscal.period
    AND p.created_at <= v_as_of;
  v_pages := greatest(1::bigint, (v_count + p_page_size - 1) / p_page_size);
  IF p_page > v_pages THEN RAISE EXCEPTION 'PAGE_OUT_OF_RANGE'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'document_number', p.document_number, 'reference', p.reference,
    'transaction_type', p.transaction_type, 'currency_code', p.currency_code,
    'gross_amount', p.gross_amount::text, 'tax_rate', p.tax_rate::text,
    'tax_amount', p.tax_amount::text, 'created_at', p.created_at
  ) ORDER BY p.created_at DESC, p.id DESC), '[]'::jsonb) INTO v_items
  FROM (
    SELECT t.* FROM public.government_tax_payable t
    WHERE t.country_code = v_user.country_code AND t.currency_code = v_currency
      AND t.fiscal_year = v_fiscal.fiscal_year AND t.period = v_fiscal.period
      AND t.created_at <= v_as_of
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT p_page_size OFFSET ((p_page::bigint - 1) * p_page_size)
  ) p;

  RETURN jsonb_build_object(
    'country_code', v_user.country_code, 'fiscal_year', v_fiscal.fiscal_year,
    'period', v_fiscal.period, 'as_of', v_as_of, 'currency', v_currency,
    'currencies', v_currencies, 'items', v_items,
    'pagination', jsonb_build_object('page', p_page, 'pageSize', p_page_size,
      'totalEntries', v_count, 'totalPages', v_pages,
      'hasPrevious', p_page > 1, 'hasNext', p_page < v_pages)
  );
END;
$function$;

ALTER FUNCTION public.fetch_my_current_government_tax(text,integer,integer,timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_my_current_government_tax(text,integer,integer,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_current_government_tax(text,integer,integer,timestamptz)
TO authenticated;

CREATE INDEX IF NOT EXISTS ngoda_current_tax_paging_idx
ON public.government_tax_payable
  (country_code, fiscal_year, period, currency_code, created_at DESC, id DESC);

COMMIT;
