BEGIN;

DROP FUNCTION IF EXISTS
    public.fetch_my_current_week_agent_commissions(
        text,
        integer,
        integer,
        timestamptz
    );

CREATE OR REPLACE FUNCTION public.fetch_my_current_period_agent_commissions(
    p_currency_code text DEFAULT NULL,
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50,
    p_as_of timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;
    v_fiscal record;

    v_zone text;
    v_period_start timestamp;
    v_period_end timestamp;
    v_local_as_of timestamp;

    v_as_of timestamptz :=
        coalesce(p_as_of, statement_timestamp());

    v_currency text :=
        lower(nullif(btrim(p_currency_code), ''));

    v_currencies jsonb;
    v_items jsonb;

    v_count bigint;
    v_pages bigint;
BEGIN
    /*
     * Authorize the authenticated Accounts user.
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            errcode = '42501',
            message = 'UNAUTHORIZED';
    END IF;

    IF NOT public.has_role(
        ARRAY['accounts']::text[]
    ) THEN
        RAISE EXCEPTION USING
            errcode = '42501',
            message = 'FORBIDDEN';
    END IF;

    SELECT user_record.*
    INTO v_user
    FROM public.users user_record
    WHERE user_record.id = auth.uid()::text
      AND user_record.status =
          'active'::public."UserStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'ACCOUNTS_USER_NOT_ACTIVE_OR_NOT_FOUND';
    END IF;

    /*
     * Validate pagination and cutoff.
     */
    IF p_page IS NULL OR p_page < 1 THEN
        RAISE EXCEPTION 'INVALID_PAGE';
    END IF;

    IF p_page_size IS NULL
       OR p_page_size < 1
       OR p_page_size > 100
    THEN
        RAISE EXCEPTION 'INVALID_PAGE_SIZE';
    END IF;

    IF NOT isfinite(v_as_of)
       OR v_as_of > statement_timestamp()
    THEN
        RAISE EXCEPTION 'INVALID_AS_OF';
    END IF;

    /*
     * Determine the current fiscal period using
     * the user's country-local time.
     */
    SELECT country_record.time_zone
    INTO v_zone
    FROM public.operational_country country_record
    WHERE country_record.country_code =
          v_user.country_code
      AND country_record.is_active = true;

    IF v_zone IS NULL THEN
        RAISE EXCEPTION
            'ACTIVE_COUNTRY_TIME_ZONE_REQUIRED';
    END IF;

    SELECT fiscal_record.*
    INTO STRICT v_fiscal
    FROM public.fetch_fiscal_period(
        v_user.country_code,
        statement_timestamp() AT TIME ZONE v_zone
    ) fiscal_record;

    SELECT
        period_record.opening_date,
        period_record.closing_date
    INTO STRICT
        v_period_start,
        v_period_end
    FROM public.fiscal_period_config period_record
    WHERE period_record.country_code =
          v_user.country_code
      AND period_record.fiscal_year =
          v_fiscal.fiscal_year
      AND period_record.period =
          v_fiscal.period;

    v_local_as_of :=
        v_as_of AT TIME ZONE v_zone;

    IF v_local_as_of < v_period_start
       OR v_local_as_of > v_period_end
    THEN
        RAISE EXCEPTION
            'COMMISSION_PERIOD_CHANGED_REFRESH_REQUIRED';
    END IF;

    /*
     * Current-period totals per currency.
     *
     * Totals include both paid and pending records.
     * Agent counts are distinct commission earners.
     */
    SELECT coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                country_currency.currency_code,

                'total_transaction_amount',
                coalesce(totals.volume, 0)::text,

                'total_fee_amount',
                coalesce(totals.fees, 0)::text,

                'total_commission_amount',
                coalesce(totals.commission, 0)::text,

                'paid_commission_amount',
                coalesce(totals.paid, 0)::text,

                'pending_commission_amount',
                coalesce(totals.pending, 0)::text,

                'total_agents',
                coalesce(totals.total_agents, 0),

                'pending_agents',
                coalesce(totals.pending_agents, 0),

                'commission_count',
                coalesce(totals.commission_count, 0),

                'paid_count',
                coalesce(totals.paid_count, 0),

                'pending_count',
                coalesce(totals.pending_count, 0)
            )
            ORDER BY country_currency.currency_code
        ),
        '[]'::jsonb
    )
    INTO v_currencies
    FROM public.country_currencies country_currency
    JOIN public.supported_currency supported_currency
      ON supported_currency.currency_code =
         country_currency.currency_code
    LEFT JOIN LATERAL (
        SELECT
            sum(commission_record.amount) AS volume,

            sum(commission_record.fee_amount) AS fees,

            sum(
                commission_record.commission_amount
            ) AS commission,

            sum(
                commission_record.commission_amount
            ) FILTER (
                WHERE commission_record.is_settled = true
            ) AS paid,

            sum(
                commission_record.commission_amount
            ) FILTER (
                WHERE commission_record.is_settled = false
            ) AS pending,

            count(
                DISTINCT commission_record.agent_id
            ) AS total_agents,

            count(
                DISTINCT commission_record.agent_id
            ) FILTER (
                WHERE commission_record.is_settled = false
            ) AS pending_agents,

            count(*) AS commission_count,

            count(*) FILTER (
                WHERE commission_record.is_settled = true
            ) AS paid_count,

            count(*) FILTER (
                WHERE commission_record.is_settled = false
            ) AS pending_count

        FROM public.agent_commission commission_record
        WHERE commission_record.country_code =
              v_user.country_code
          AND commission_record.currency_code =
              country_currency.currency_code
          AND commission_record.fiscal_year =
              v_fiscal.fiscal_year
          AND commission_record.period =
              v_fiscal.period
          AND commission_record.created_at <= v_as_of
    ) totals ON true
    WHERE country_currency.country_code =
          v_user.country_code
      AND country_currency.is_active = true
      AND supported_currency.is_active = true
      AND supported_currency.currency_category =
          'fiat'::public."CurrencyCategory";

    /*
     * Select and validate the currency tab.
     */
    IF v_currency IS NULL THEN
        v_currency :=
            v_currencies -> 0 ->> 'currency_code';

    ELSIF NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_currencies)
            currency_record
        WHERE currency_record ->> 'currency_code' =
              v_currency
    ) THEN
        RAISE EXCEPTION
            'COMMISSION_CURRENCY_NOT_ACTIVE';
    END IF;

    /*
     * Pagination counts pending records only.
     */
    SELECT count(*)
    INTO v_count
    FROM public.agent_commission commission_record
    WHERE commission_record.country_code =
          v_user.country_code
      AND commission_record.currency_code =
          v_currency
      AND commission_record.fiscal_year =
          v_fiscal.fiscal_year
      AND commission_record.period =
          v_fiscal.period
      AND commission_record.created_at <= v_as_of
      AND commission_record.is_settled = false;

    v_pages :=
        greatest(
            1::bigint,
            (v_count + p_page_size - 1) / p_page_size
        );

    IF p_page > v_pages THEN
        RAISE EXCEPTION 'PAGE_OUT_OF_RANGE';
    END IF;

    /*
     * Pending transaction-level commission items.
     *
     * Assigned but unpaid records remain included.
     */
    SELECT coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', commission_record.id,
                'agent_id', commission_record.agent_id,
                'agent_email', user_record.email,
                'document_number',
                    commission_record.document_number,
                'reference', commission_record.reference,
                'transaction_type',
                    commission_record.transaction_type,
                'currency_code',
                    commission_record.currency_code,
                'amount',
                    commission_record.amount::text,
                'fee_amount',
                    commission_record.fee_amount::text,
                'commission_rate',
                    commission_record.commission_rate::text,
                'commission_amount',
                    commission_record.commission_amount::text,
                'is_settled', false,
                'status', 'pending',
                'created_at', commission_record.created_at,
                'settlement_batch_id',
                    commission_record.settlement_batch_id
            )
            ORDER BY
                commission_record.created_at DESC,
                commission_record.id DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM (
        SELECT commission_source.*
        FROM public.agent_commission commission_source
        WHERE commission_source.country_code =
              v_user.country_code
          AND commission_source.currency_code =
              v_currency
          AND commission_source.fiscal_year =
              v_fiscal.fiscal_year
          AND commission_source.period =
              v_fiscal.period
          AND commission_source.created_at <= v_as_of
          AND commission_source.is_settled = false
        ORDER BY
            commission_source.created_at DESC,
            commission_source.id DESC
        LIMIT p_page_size
        OFFSET ((p_page::bigint - 1) * p_page_size)
    ) commission_record
    LEFT JOIN public.users user_record
      ON user_record.id =
         commission_record.agent_id;

    RETURN jsonb_build_object(
        'country_code', v_user.country_code,
        'fiscal_year', v_fiscal.fiscal_year,
        'period', v_fiscal.period,
        'period_start', v_period_start,
        'period_end', v_period_end,
        'as_of', v_as_of,
        'currency', v_currency,
        'currencies', v_currencies,
        'items', v_items,
        'pagination', jsonb_build_object(
            'page', p_page,
            'pageSize', p_page_size,
            'totalEntries', v_count,
            'totalPages', v_pages,
            'hasPrevious', p_page > 1,
            'hasNext', p_page < v_pages
        )
    );
END;
$function$;

ALTER FUNCTION
    public.fetch_my_current_period_agent_commissions(
        text,
        integer,
        integer,
        timestamptz
    )
OWNER TO postgres;

REVOKE ALL ON FUNCTION
    public.fetch_my_current_period_agent_commissions(
        text,
        integer,
        integer,
        timestamptz
    )
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_current_period_agent_commissions(
        text,
        integer,
        integer,
        timestamptz
    )
TO authenticated;

CREATE INDEX IF NOT EXISTS
    ngoda_agent_commission_period_paging_idx
ON public.agent_commission (
    country_code,
    fiscal_year,
    period,
    currency_code,
    created_at DESC,
    id DESC
);

COMMIT;