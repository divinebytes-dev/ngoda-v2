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
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    IF NOT public.has_role(
        ARRAY['treasury']::text[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';
    END IF;

    RETURN QUERY
    SELECT
        b.code,
        n.chain_id,
        n.rpc_url,
        b.contract_address,
        b.native_currency_code
    FROM public.supported_blockchain AS b
    JOIN LATERAL (
        SELECT
            network.chain_id,
            network.rpc_url
        FROM public.supported_blockchain_network AS network
        WHERE network.blockchain_id = b.id
          AND network.is_active = true
        ORDER BY
            network.is_default DESC,
            network.created_at DESC,
            network.id
        LIMIT 1
    ) AS n ON true
    WHERE b.is_active = true
    ORDER BY b.code;
END;
$function$;