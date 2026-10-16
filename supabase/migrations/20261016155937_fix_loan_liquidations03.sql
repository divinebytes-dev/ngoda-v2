CREATE OR REPLACE FUNCTION public.fetch_liquidation_blockchain_config(
    p_queue_id text
)
RETURNS TABLE (
    code text,
    chain_id bigint,
    rpc_url text,
    contract_address text,
    native_currency_code text,
    explorer_url text,
    treasury_wallet_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_blockchain public.supported_blockchain%rowtype;
    v_network public.supported_blockchain_network%rowtype;

    v_saved_chain_id bigint;
    v_contract_address text;
    v_treasury_wallet_address text;
    v_resume boolean;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = p_queue_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_NOT_FOUND';
    END IF;

    IF nullif(btrim(v_queue.blockchain_code), '') IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    SELECT b.*
    INTO v_blockchain
    FROM public.supported_blockchain AS b
    WHERE b.code = v_queue.blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_NOT_FOUND';
    END IF;

    IF v_blockchain.blockchain_type IS DISTINCT FROM 'evm' THEN
        RAISE EXCEPTION 'UNSUPPORTED_BLOCKCHAIN_TYPE';
    END IF;

    v_resume :=
        v_queue.signed_payload IS NOT NULL
        OR v_queue.tx_hash IS NOT NULL;

    IF v_resume THEN
        /*
         * Recover the exact network and contract used
         * when the signature was created.
         */
        IF v_queue.signed_payload IS NULL
           OR (v_queue.signed_payload ->> 'blockchain_code')
              IS DISTINCT FROM v_queue.blockchain_code
           OR coalesce(
               v_queue.signed_payload ->> 'chain_id',
               ''
           ) !~ '^[0-9]+$'
        THEN
            RAISE EXCEPTION
                'LIQUIDATION_SAVED_BLOCKCHAIN_METADATA_REQUIRED';
        END IF;

        BEGIN
            v_saved_chain_id :=
                (v_queue.signed_payload ->> 'chain_id')::bigint;
        EXCEPTION
            WHEN invalid_text_representation
              OR numeric_value_out_of_range
            THEN
                RAISE EXCEPTION
                    'INVALID_LIQUIDATION_SAVED_CHAIN_ID';
        END;

        IF v_saved_chain_id <= 0 THEN
            RAISE EXCEPTION
                'INVALID_LIQUIDATION_SAVED_CHAIN_ID';
        END IF;

        v_contract_address :=
            nullif(
                btrim(
                    v_queue.signed_payload ->> 'contract_address'
                ),
                ''
            );

        /*
         * chain_id is unique in supported_blockchain_network.
         *
         * Do not filter is_active here: a disabled network
         * may still contain a transaction requiring recovery.
         */
        SELECT n.*
        INTO v_network
        FROM public.supported_blockchain_network AS n
        WHERE n.blockchain_id = v_blockchain.id
          AND n.chain_id = v_saved_chain_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'LIQUIDATION_SAVED_NETWORK_NOT_FOUND';
        END IF;

        /*
         * Use the signed recipient for existing jobs.
         * Configuration changes must not change that recipient.
         */
        v_treasury_wallet_address :=
            nullif(
                btrim(v_queue.signed_payload ->> 'to'),
                ''
            );
    ELSE
        /*
         * A new signature requires an active blockchain
         * and an active configured network.
         */
        IF v_blockchain.is_active IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
        END IF;

        SELECT n.*
        INTO v_network
        FROM public.supported_blockchain_network AS n
        WHERE n.blockchain_id = v_blockchain.id
          AND n.is_active = true
        ORDER BY
            n.is_default DESC,
            n.created_at DESC,
            n.id
        LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_NETWORK_NOT_FOUND_OR_INACTIVE';
        END IF;

        v_contract_address :=
            nullif(btrim(v_blockchain.contract_address), '');

        v_treasury_wallet_address :=
            nullif(btrim(v_network.treasury_wallet_address), '');
    END IF;

    /*
     * Validate the resolved configuration.
     */
    IF v_network.chain_id <= 0 THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_CHAIN_ID';
    END IF;

    IF nullif(btrim(v_network.rpc_url), '') IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_RPC_URL_MISSING';
    END IF;

    IF nullif(btrim(v_network.explorer_url), '') IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_EXPLORER_URL_MISSING';
    END IF;

    IF v_contract_address IS NULL
       OR v_contract_address !~ '^0x[0-9a-fA-F]{40}$'
       OR lower(v_contract_address) =
          '0x0000000000000000000000000000000000000000'
    THEN
        RAISE EXCEPTION 'INVALID_TOKEN_CONTRACT_ADDRESS';
    END IF;

    IF v_treasury_wallet_address IS NULL
       OR v_treasury_wallet_address !~ '^0x[0-9a-fA-F]{40}$'
       OR lower(v_treasury_wallet_address) =
          '0x0000000000000000000000000000000000000000'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_TREASURY_WALLET_ADDRESS';
    END IF;

    RETURN QUERY
    SELECT
        v_blockchain.code,
        v_network.chain_id,
        btrim(v_network.rpc_url),
        v_contract_address,
        v_blockchain.native_currency_code,
        btrim(v_network.explorer_url),
        v_treasury_wallet_address;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.fetch_liquidation_blockchain_config(text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.fetch_liquidation_blockchain_config(text)
TO service_role;