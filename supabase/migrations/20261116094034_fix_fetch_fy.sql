CREATE OR REPLACE FUNCTION public.fetch_my_fiscal_periods()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;
    v_now_utc timestamp without time zone := statement_timestamp() AT TIME ZONE 'UTC';
    v_current_fiscal_year integer;
    v_previous_fiscal_year integer;
    v_current_periods jsonb;
    v_previous_periods jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501', MESSAGE = 'UNAUTHENTICATED';
    END IF;

    IF NOT public.has_role(ARRAY['finance']::text[]) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501', MESSAGE = 'FORBIDDEN';
    END IF;

    SELECT user_record.* INTO v_user
    FROM public.fetch_user_by_id(auth.uid()::text) AS user_record;

    IF v_user.id IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND';
    END IF;

    IF nullif(btrim(v_user.country_code), '') IS NULL THEN
        RAISE EXCEPTION 'USER_COUNTRY_NOT_CONFIGURED';
    END IF;

    -- Calendar dates are stored as UTC timestamps without a time zone.
    -- Use the configured fiscal identity rather than the calendar year number.
    BEGIN
        SELECT f.fiscal_year INTO STRICT v_current_fiscal_year
        FROM public.fiscal_period_config f
        WHERE f.country_code = v_user.country_code
          AND f.opening_date <= v_now_utc
          AND f.closing_date >= v_now_utc;
    EXCEPTION
        WHEN no_data_found THEN
            RAISE EXCEPTION 'CURRENT_FISCAL_YEAR_NOT_CONFIGURED';
        WHEN too_many_rows THEN
            RAISE EXCEPTION 'AMBIGUOUS_CURRENT_FISCAL_PERIOD';
    END;

    v_previous_fiscal_year := v_current_fiscal_year - 1;

    WITH period_rows AS (
        SELECT
            f.fiscal_year,
            f.period,
            jsonb_build_object(
                'id', f.id,
                'fiscal_year', f.fiscal_year,
                'period', f.period,
                'country_code', f.country_code,
                'period_name', f.period_name,
                'opening_date', f.opening_date,
                'closing_date', f.closing_date,
                'is_closed', f.is_closed,
                'created_at', f.created_at,
                'created_by', f.created_by,
                'updated_at', f.updated_at,
                'updated_by', f.updated_by
            ) AS period_data
        FROM public.fiscal_period_config f
        WHERE f.country_code = v_user.country_code
          AND f.fiscal_year IN (
              v_previous_fiscal_year,
              v_current_fiscal_year
          )
    )
    SELECT
        coalesce(
            jsonb_agg(period_data ORDER BY period)
                FILTER (WHERE fiscal_year = v_previous_fiscal_year),
            '[]'::jsonb
        ),
        coalesce(
            jsonb_agg(period_data ORDER BY period)
                FILTER (WHERE fiscal_year = v_current_fiscal_year),
            '[]'::jsonb
        )
    INTO v_previous_periods, v_current_periods
    FROM period_rows;

    RETURN jsonb_build_object(
        'country_code', v_user.country_code,
        'previous_fiscal_year', v_previous_fiscal_year,
        'current_fiscal_year', v_current_fiscal_year,
        'previous_periods', v_previous_periods,
        'current_periods', v_current_periods
    );
END;
$function$;
