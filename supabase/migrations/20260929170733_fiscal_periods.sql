CREATE OR REPLACE FUNCTION public.fetch_my_fiscal_periods()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_current_fiscal_year integer;
    v_next_fiscal_year integer;

    v_current_periods jsonb;
    v_next_periods jsonb;
BEGIN
    /*
     * Authentication
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHENTICATED';
    END IF;

    /*
     * Authorization
     *
     * Fiscal period maintenance is restricted
     * to Finance only.
     */
    IF NOT public.has_role(
        ARRAY[
            'finance'
        ]::text[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';
    END IF;

    /*
     * Fetch the authenticated application user.
     */
    SELECT user_record.*
    INTO v_user
    FROM public.fetch_user_by_id(
        auth.uid()::text
    ) AS user_record;

    IF v_user.id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'USER_NOT_FOUND';
    END IF;

    IF v_user.country_code IS NULL
       OR btrim(v_user.country_code) = '' THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'USER_COUNTRY_NOT_CONFIGURED';
    END IF;

    /*
     * Determine the current fiscal year.
     *
     * We use the configured fiscal-period dates rather
     * than assuming that fiscal year = calendar year.
     *
     * A fiscal year is current when today's date falls
     * within one of its configured periods.
     */
    SELECT fpc.fiscal_year
    INTO v_current_fiscal_year
    FROM public.fiscal_period_config AS fpc
    WHERE fpc.country_code = v_user.country_code
      AND CURRENT_TIMESTAMP >= fpc.opening_date
      AND CURRENT_TIMESTAMP <= fpc.closing_date
    ORDER BY
        fpc.fiscal_year DESC,
        fpc.period DESC
    LIMIT 1;

    /*
     * There must already be a fiscal year configured
     * for the user's country.
     */
    IF v_current_fiscal_year IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'CURRENT_FISCAL_YEAR_NOT_CONFIGURED';
    END IF;

    v_next_fiscal_year :=
        v_current_fiscal_year + 1;

    /*
     * Current fiscal-year periods.
     */
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id',
                fpc.id,

                'fiscal_year',
                fpc.fiscal_year,

                'period',
                fpc.period,

                'country_code',
                fpc.country_code,

                'period_name',
                fpc.period_name,

                'opening_date',
                fpc.opening_date,

                'closing_date',
                fpc.closing_date,

                'is_closed',
                fpc.is_closed,

                'created_at',
                fpc.created_at,

                'created_by',
                fpc.created_by,

                'updated_at',
                fpc.updated_at,

                'updated_by',
                fpc.updated_by
            )
            ORDER BY fpc.period
        ),
        '[]'::jsonb
    )
    INTO v_current_periods
    FROM public.fiscal_period_config AS fpc
    WHERE fpc.country_code = v_user.country_code
      AND fpc.fiscal_year = v_current_fiscal_year;

    /*
     * Next fiscal-year periods.
     *
     * This intentionally returns [] when the next fiscal
     * year has not yet been opened/configured.
     *
     * Flutter uses that condition to enable the
     * "Open Fiscal Year" button.
     */
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id',
                fpc.id,

                'fiscal_year',
                fpc.fiscal_year,

                'period',
                fpc.period,

                'country_code',
                fpc.country_code,

                'period_name',
                fpc.period_name,

                'opening_date',
                fpc.opening_date,

                'closing_date',
                fpc.closing_date,

                'is_closed',
                fpc.is_closed,

                'created_at',
                fpc.created_at,

                'created_by',
                fpc.created_by,

                'updated_at',
                fpc.updated_at,

                'updated_by',
                fpc.updated_by
            )
            ORDER BY fpc.period
        ),
        '[]'::jsonb
    )
    INTO v_next_periods
    FROM public.fiscal_period_config AS fpc
    WHERE fpc.country_code = v_user.country_code
      AND fpc.fiscal_year = v_next_fiscal_year;

    /*
     * Response expected by FiscalPeriodSummary.
     */
    RETURN jsonb_build_object(
        'country_code',
        v_user.country_code,

        'current_fiscal_year',
        v_current_fiscal_year,

        'next_fiscal_year',
        v_next_fiscal_year,

        'current_periods',
        v_current_periods,

        'next_periods',
        v_next_periods
    );
END;
$function$;