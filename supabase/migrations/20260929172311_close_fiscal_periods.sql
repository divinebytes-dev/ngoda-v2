CREATE OR REPLACE FUNCTION public.close_my_fiscal_year(
    p_fiscal_year integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_next_fiscal_year integer;

    v_period_count integer;
    v_open_period_count integer;
    v_closed_period_count integer;
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
     * Only Finance can close a fiscal year.
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
     * Validate input.
     */
    IF p_fiscal_year IS NULL
       OR p_fiscal_year <= 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_FISCAL_YEAR';
    END IF;

    /*
     * Fetch authenticated application user.
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
     * Confirm that the fiscal year being closed
     * actually exists for this user's country.
     */
    SELECT COUNT(*)
    INTO v_period_count
    FROM public.fiscal_period_config AS fpc
    WHERE fpc.country_code = v_user.country_code
      AND fpc.fiscal_year = p_fiscal_year;

    IF v_period_count = 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_YEAR_NOT_CONFIGURED';
    END IF;

    /*
     * The next fiscal year must already exist.
     *
     * Opening and closing remain separate operations:
     *
     * 1. Finance opens the next fiscal year.
     * 2. Finance separately closes the previous year.
     *
     * Opening the next year does NOT automatically
     * close this year.
     */
    v_next_fiscal_year :=
        p_fiscal_year + 1;

    IF NOT EXISTS (
        SELECT 1
        FROM public.fiscal_period_config AS fpc
        WHERE fpc.country_code = v_user.country_code
          AND fpc.fiscal_year = v_next_fiscal_year
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'NEXT_FISCAL_YEAR_NOT_OPEN';
    END IF;

    /*
     * Determine how many periods are still open.
     */
    SELECT COUNT(*)
    INTO v_open_period_count
    FROM public.fiscal_period_config AS fpc
    WHERE fpc.country_code = v_user.country_code
      AND fpc.fiscal_year = p_fiscal_year
      AND fpc.is_closed = false;

    /*
     * Prevent repeated closing.
     */
    IF v_open_period_count = 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_YEAR_ALREADY_CLOSED';
    END IF;

    /*
     * Close every open period belonging to the
     * selected fiscal year.
     */
    UPDATE public.fiscal_period_config AS fpc
    SET
        is_closed = true,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = auth.uid()::text
    WHERE fpc.country_code = v_user.country_code
      AND fpc.fiscal_year = p_fiscal_year
      AND fpc.is_closed = false;

    GET DIAGNOSTICS
        v_closed_period_count = ROW_COUNT;

    /*
     * Safety check.
     *
     * Every period that was open when this operation
     * started must have been updated.
     *
     * Raising here rolls back the transaction.
     */
    IF v_closed_period_count <> v_open_period_count THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_YEAR_CLOSE_INCOMPLETE';
    END IF;

    RETURN jsonb_build_object(
        'country_code',
        v_user.country_code,
        'fiscal_year',
        p_fiscal_year,
        'periods',
        v_period_count,
        'periods_closed',
        v_closed_period_count,
        'is_closed',
        true
    );
END;
$function$;