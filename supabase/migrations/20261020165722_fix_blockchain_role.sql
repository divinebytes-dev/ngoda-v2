CREATE OR REPLACE FUNCTION public.fetch_token_role_grant_config(
    p_blockchain_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_config jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if public.has_role(
        array['admin']::text[]
    ) is not true then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    select jsonb_build_object(
        'code', blockchain.code,
        'chain_id', network.chain_id,
        'rpc_url', network.rpc_url,
        'contract_address', blockchain.contract_address,
        'native_currency_code', blockchain.native_currency_code,
        'explorer_url', network.explorer_url,
        'treasury_wallet_address', network.treasury_wallet_address
    )
    into v_config
    from public.supported_blockchain blockchain
    join lateral (
        select network_record.*
        from public.supported_blockchain_network network_record
        where network_record.blockchain_id = blockchain.id
          and network_record.is_active = true
        order by
            network_record.is_default desc,
            network_record.created_at desc,
            network_record.id
        limit 1
    ) network on true
    where blockchain.code = v_blockchain_code
      and blockchain.is_active = true
      and blockchain.blockchain_type = 'evm';

    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    end if;

    if nullif(btrim(v_config ->> 'rpc_url'), '') is null then
        raise exception 'BLOCKCHAIN_RPC_URL_MISSING';
    end if;

    if coalesce(v_config ->> 'contract_address', '')
       !~ '^0x[0-9a-fA-F]{40}$'
    then
        raise exception 'INVALID_TOKEN_CONTRACT_ADDRESS';
    end if;

    if coalesce(v_config ->> 'treasury_wallet_address', '')
       !~ '^0x[0-9a-fA-F]{40}$'
    then
        raise exception 'INVALID_TREASURY_ADDRESS';
    end if;

    return v_config;
end;
$function$;

REVOKE ALL
ON FUNCTION public.fetch_token_role_grant_config(text)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE
ON FUNCTION public.fetch_token_role_grant_config(text)
TO authenticated;