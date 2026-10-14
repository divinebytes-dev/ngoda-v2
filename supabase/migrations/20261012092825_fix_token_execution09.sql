CREATE OR REPLACE FUNCTION public.prepare_my_token_adjustment_execution(p_adjustment_request_id text, p_blockchain_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_request
        public.tokenised_asset_adjustment_request%rowtype;

    v_blockchain
        public.supported_blockchain%rowtype;

    v_network
        public.supported_blockchain_network%rowtype;

    v_blockchain_code text;

    v_minting_country_code constant text := 'zw';
begin
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * ==========================================================
     * ROLE AUTHORIZATION
     * ==========================================================
     */
    if not public.has_role(
        array['treasury']::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * ==========================================================
     * VALIDATE INPUT
     * ==========================================================
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    v_blockchain_code :=
        nullif(
            lower(btrim(p_blockchain_code)),
            ''
        );

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    /*
     * ==========================================================
     * FETCH AUTHENTICATED TREASURY USER
     * ==========================================================
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * ZIMBABWE MINTING TREASURY
     * ==========================================================
     *
     * Only Zimbabwe treasury users can execute minting
     * and burning adjustments.
     */
    if lower(
        btrim(coalesce(v_user.country_code, ''))
    ) <> v_minting_country_code then
        raise exception using
            errcode = '42501',
            message = 'CENTRAL_MINTING_TREASURY_ONLY';
    end if;

    /*
     * ==========================================================
     * LOCK APPROVED ADJUSTMENT REQUEST
     * ==========================================================
     */
    select adjustment_record.*
    into v_request
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.id::text =
          btrim(p_adjustment_request_id)
    for update;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * VALIDATE APPROVAL
     * ==========================================================
     */
    if v_request.status is distinct from
       'approved'::public."AdjustmentStatus"
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_APPROVED';
    end if;

    /*
     * ==========================================================
     * VALIDATE EXECUTION STATE
     * ==========================================================
     */
    if v_request.executed_by is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_CLAIMED';
    end if;

    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_EXECUTED';
    end if;

    perform 1
    from public.blockchain_transaction blockchain_record
    where blockchain_record.reference = v_request.id::text
    limit 1;

    if found then
        raise exception
            'ADJUSTMENT_BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    /*
     * ==========================================================
     * VALIDATE ADJUSTMENT DETAILS
     * ==========================================================
     *
     * currency_code is the original purchase currency.
     * For example, USD.
     *
     * quantity is the GOLD quantity in grams.
     */
    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

    if v_request.adjustment_type not in (
        'minting'::public."TokenAdjustmentType",
        'burning'::public."TokenAdjustmentType"
    ) then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

/*
 * ==========================================================
 * VALIDATE UNIT OF MEASUREMENT
 * ==========================================================
 *
 * Uom is a PostgreSQL enum.
 * Cast to text before applying text operations.
 */
if lower(
    btrim(
        coalesce(v_request.uom::text, '')
    )
) <> 'gram' then
    raise exception
        'INVALID_TOKEN_ADJUSTMENT_UOM';
end if;

    /*
     * ==========================================================
     * FETCH TREASURY-SELECTED BLOCKCHAIN
     * ==========================================================
     *
     * Finance and Accounts do not select the blockchain.
     *
     * Treasury supplies p_blockchain_code when executing
     * the approved request.
     */
    select blockchain_record.*
    into v_blockchain
    from public.supported_blockchain blockchain_record
    where blockchain_record.code = v_blockchain_code
      and blockchain_record.is_active = true
    limit 1;

    if not found then
        raise exception
            'SUPPORTED_BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    end if;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN CONFIGURATION
     * ==========================================================
     */
    if nullif(
        btrim(v_blockchain.contract_address),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_CONTRACT_ADDRESS_MISSING';
    end if;

    if nullif(
        btrim(v_blockchain.native_currency_code),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_NATIVE_CURRENCY_MISSING';
    end if;

    /*
     * ==========================================================
     * FETCH ACTIVE BLOCKCHAIN NETWORK
     * ==========================================================
     */
    select network_record.*
    into v_network
    from public.supported_blockchain_network network_record
    where network_record.blockchain_id = v_blockchain.id
      and network_record.is_active = true
    order by
        network_record.is_default desc,
        network_record.created_at desc,
        network_record.id
    limit 1;

    if not found then
        raise exception
            'ACTIVE_BLOCKCHAIN_NETWORK_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * VALIDATE NETWORK CONFIGURATION
     * ==========================================================
     */
    if v_network.chain_id is null
       or v_network.chain_id <= 0
    then
        raise exception
            'BLOCKCHAIN_CHAIN_ID_MISSING';
    end if;

    if nullif(
        btrim(v_network.network_name),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_NETWORK_NAME_MISSING';
    end if;

    if nullif(
        btrim(v_network.rpc_url),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_RPC_URL_MISSING';
    end if;

    if nullif(
        btrim(v_network.explorer_url),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISSING';
    end if;

    if nullif(
        btrim(v_network.treasury_wallet_address),
        ''
    ) is null then
        raise exception
            'TREASURY_WALLET_ADDRESS_NOT_CONFIGURED';
    end if;

    /*
     * ==========================================================
     * CLAIM REQUEST AND SAVE SELECTED BLOCKCHAIN
     * ==========================================================
     *
     * The blockchain selected by Treasury is stored
     * in tokenised_asset_adjustment_request.
     *
     * Both values are updated atomically.
     */
    update public.tokenised_asset_adjustment_request
    set
        executed_by = v_user.id,
        blockchain_code = v_blockchain_code
    where id = v_request.id
      and status =
          'approved'::public."AdjustmentStatus"
      and executed_by is null
      and tx_hash is null
    returning *
    into v_request;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_CLAIM_FAILED';
    end if;

    /*
     * ==========================================================
     * RETURN EXECUTION CONFIGURATION
     * ==========================================================
     */
    return jsonb_build_object(
        'success', true,

        'adjustment_request_id',
        v_request.id::text,

        'document_number',
        v_request.document_number,

        'adjustment_type',
        v_request.adjustment_type,

        'quantity',
        v_request.quantity::text,

        'uom',
        v_request.uom,

        'currency_code',
        v_request.currency_code,

        'country_code',
        v_minting_country_code,

        'executed_by',
        v_user.id,

        'blockchain_code',
        v_request.blockchain_code,

        'blockchain_name',
        v_blockchain.name,

        'blockchain_type',
        v_blockchain.blockchain_type,

        'native_currency_code',
        v_blockchain.native_currency_code,

        'contract_address',
        v_blockchain.contract_address,

        'network_name',
        v_network.network_name,

        'environment',
        v_network.environment,

        'chain_id',
        v_network.chain_id,

        'rpc_url',
        v_network.rpc_url,

        'explorer_url',
        v_network.explorer_url,

        'treasury_wallet_address',
        v_network.treasury_wallet_address
    );
end;
$function$
