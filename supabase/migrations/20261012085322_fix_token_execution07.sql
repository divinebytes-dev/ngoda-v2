CREATE OR REPLACE FUNCTION public.prepare_my_token_adjustment_execution(
    p_adjustment_request_id text
)
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
     * VALIDATE REQUEST IDENTIFIER
     * ==========================================================
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
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
     * CENTRAL MINTING TREASURY AUTHORIZATION
     * ==========================================================
     *
     * Zimbabwe is the designated minting and burning country.
     *
     * Other countries receive GOLD tokens through treasury
     * transfers and cannot execute mint/burn operations.
     */
    if lower(
        btrim(
            coalesce(v_user.country_code, '')
        )
    ) <> v_minting_country_code then
        raise exception using
            errcode = '42501',
            message = 'CENTRAL_MINTING_TREASURY_ONLY';
    end if;

    /*
     * ==========================================================
     * LOCK ADJUSTMENT REQUEST
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
     * VALIDATE APPROVAL STATUS
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
     * PREVENT DUPLICATE EXECUTION
     * ==========================================================
     */
    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_EXECUTED';
    end if;

    if v_request.executed_by is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_CLAIMED';
    end if;

    /*
     * ==========================================================
     * PREVENT DUPLICATE BLOCKCHAIN RECORD
     * ==========================================================
     */
    perform 1
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.reference =
          v_request.id::text
    limit 1;

    if found then
        raise exception
            'ADJUSTMENT_BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    /*
     * ==========================================================
     * VALIDATE ADJUSTMENT QUANTITY
     * ==========================================================
     */
    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

    /*
     * ==========================================================
     * VALIDATE ADJUSTMENT TYPE
     * ==========================================================
     */
    if v_request.adjustment_type not in (
        'minting'::public."TokenAdjustmentType",
        'burning'::public."TokenAdjustmentType"
    ) then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * ==========================================================
     * VALIDATE GOLD CURRENCY
     * ==========================================================
     */
    if lower(
        btrim(
            coalesce(v_request.currency_code, '')
        )
    ) <> 'gold' then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_CURRENCY';
    end if;

    /*
     * ==========================================================
     * RESOLVE BLOCKCHAIN CODE
     * ==========================================================
     *
     * The approved request determines which blockchain
     * receives the mint/burn operation.
     */
    v_blockchain_code :=
        nullif(
            lower(
                btrim(v_request.blockchain_code)
            ),
            ''
        );

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    /*
     * ==========================================================
     * FETCH ACTIVE SUPPORTED BLOCKCHAIN
     * ==========================================================
     */
    select blockchain_record.*
    into v_blockchain
    from public.supported_blockchain
        blockchain_record
    where blockchain_record.code =
          v_blockchain_code
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
    from public.supported_blockchain_network
        network_record
    where network_record.blockchain_id =
          v_blockchain.id
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
     * CLAIM ADJUSTMENT REQUEST
     * ==========================================================
     *
     * executed_at remains NULL until the blockchain transaction
     * and accounting entries have completed successfully.
     */
    update public.tokenised_asset_adjustment_request
    set executed_by = v_user.id
    where id = v_request.id
      and status =
          'approved'::public."AdjustmentStatus"
      and executed_by is null
      and tx_hash is null;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_CLAIM_FAILED';
    end if;

    /*
     * ==========================================================
     * RETURN PREPARATION AND BLOCKCHAIN CONFIGURATION
     * ==========================================================
     */
    return jsonb_build_object(
        'success',
        true,

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
        v_blockchain.code,

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
$function$;