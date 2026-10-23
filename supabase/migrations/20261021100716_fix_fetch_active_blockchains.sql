CREATE OR REPLACE FUNCTION public.fetch_active_supported_blockchains()
 RETURNS TABLE(code text, chain_id bigint, rpc_url text, contract_address text, native_currency_code text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain record;
begin
    /*
     * AUTHENTICATION
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * AUTHORIZATION
     */
    if public.has_role(
        array[
            'treasury',
            'customer',
            'agent',
            'vendor',
            'finance',
            'accounts'
        ]::text[]
    ) is not true then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Select one active network per active EVM blockchain.
     *
     * LEFT JOIN ensures a missing network is detected
     * rather than silently excluded from the supply total.
     */
    for v_blockchain in
        select
            blockchain.code,
            blockchain.contract_address,
            blockchain.native_currency_code,
            network.id as network_id,
            network.chain_id,
            network.rpc_url
        from public.supported_blockchain blockchain
        left join lateral (
            select
                network_record.id,
                network_record.chain_id,
                network_record.rpc_url
            from public.supported_blockchain_network
                network_record
            where network_record.blockchain_id = blockchain.id
              and network_record.is_active = true
            order by
                network_record.is_default desc,
                network_record.created_at desc,
                network_record.id
            limit 1
        ) network on true
        where blockchain.is_active = true
          and blockchain.blockchain_type = 'evm'
        order by blockchain.code
    loop
        if v_blockchain.network_id is null then
            raise exception
                'ACTIVE_BLOCKCHAIN_NETWORK_REQUIRED: %',
                v_blockchain.code;
        end if;

        if v_blockchain.chain_id is null
           or v_blockchain.chain_id <= 0
        then
            raise exception
                'INVALID_BLOCKCHAIN_CHAIN_ID: %',
                v_blockchain.code;
        end if;

        if nullif(btrim(v_blockchain.rpc_url), '') is null then
            raise exception
                'BLOCKCHAIN_RPC_URL_MISSING: %',
                v_blockchain.code;
        end if;

        if coalesce(v_blockchain.contract_address, '')
           !~ '^0x[0-9a-fA-F]{40}$'
           or lower(v_blockchain.contract_address) =
              '0x0000000000000000000000000000000000000000'
        then
            raise exception
                'INVALID_TOKEN_CONTRACT_ADDRESS: %',
                v_blockchain.code;
        end if;

        code := v_blockchain.code;
        chain_id := v_blockchain.chain_id;
        rpc_url := btrim(v_blockchain.rpc_url);
        contract_address := v_blockchain.contract_address;
        native_currency_code := v_blockchain.native_currency_code;

        return next;
    end loop;
end;
$function$
