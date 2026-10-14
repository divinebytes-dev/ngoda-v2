CREATE OR REPLACE FUNCTION public.fetch_active_supported_blockchain(
    p_blockchain_code text
)
RETURNS TABLE(
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
DECLARE
    v_blockchain_code text;
BEGIN
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    /*
     * ==========================================================
     * ROLE AUTHORIZATION
     * ==========================================================
     */
    IF NOT public.has_role(
        ARRAY[
            'treasury',
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';
    END IF;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * FETCH ACTIVE SUPPORTED BLOCKCHAIN
     * ==========================================================
     *
     * Return one active network for the requested blockchain.
     *
     * Network selection:
     * 1. Prefer the active default network.
     * 2. Otherwise select the most recently created
     *    active network.
     */
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
      AND lower(b.code) = v_blockchain_code

    LIMIT 1;

    /*
     * ==========================================================
     * VALIDATE RESULT
     * ==========================================================
     */
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

END;
$function$;