CREATE OR REPLACE FUNCTION public.fetch_active_supported_blockchains()
RETURNS TABLE (
    code text,
    chain_id bigint,
    rpc_url text,
    contract_address text,
    native_currency_code text
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
     * Validate Treasury role.
     */
    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.user_role r
            ON r.id = u.role_id
        WHERE u.id = auth.uid()::text
          AND u.status = 'active'::public."UserStatus"
          AND lower(r.name::text) = 'treasury'
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'TREASURY_NOT_AUTHORIZED';
    END IF;

    /*
     * Return all active supported blockchains.
     */
    RETURN QUERY
    SELECT
        b.code::text,
        b.chain_id::bigint,
        b.rpc_url::text,
        b.contract_address::text,
        b.native_currency_code::text
    FROM public.supported_blockchain b
    WHERE b.is_active = true
    ORDER BY b.code;
END;
$function$;