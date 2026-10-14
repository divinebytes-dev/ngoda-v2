BEGIN;

DROP FUNCTION IF EXISTS
    public.fetch_my_treasury_dashboard_context();

CREATE FUNCTION public.fetch_my_treasury_dashboard_context()
RETURNS TABLE (
    user_id text,
    country_code text,
    wallet_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
    /*
     * Authentication.
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    /*
     * Fetch authenticated Treasury user
     * and blockchain wallet address.
     */
    RETURN QUERY
    SELECT
        u.id::text,
        u.country_code::text,
        u.wallet_address::text
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status =
          'active'::public."UserStatus"
      AND lower(r.name::text) = 'treasury'
    LIMIT 1;

    /*
     * Reject unauthorized Treasury access.
     */
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'TREASURY_NOT_AUTHORIZED';
    END IF;
END;
$function$;

COMMIT;