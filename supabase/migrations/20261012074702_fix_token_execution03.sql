CREATE OR REPLACE FUNCTION public.record_my_token_adjustment_blockchain_transaction(
    p_adjustment_request_id text,
    p_tx_hash text,
    p_treasury_address text,
    p_explorer_url text DEFAULT NULL::text
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

    v_transaction_type
        public."TransactionType";

    v_fiscal_year integer;
    v_period integer;

    v_blockchain_code text;

    v_sender text;
    v_receiver text;
    v_description text;

    v_tx_hash text;
    v_treasury_address text;
    v_explorer_url text;
    v_expected_explorer_url text;

    v_blockchain_transaction_id
        public.blockchain_transaction.id%type;

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
        array[
            'treasury'
        ]::text[]
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
     * VALIDATE BLOCKCHAIN TRANSACTION HASH
     * ==========================================================
     */
    v_tx_hash :=
        nullif(
            btrim(p_tx_hash),
            ''
        );

    if v_tx_hash is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_HASH_REQUIRED';
    end if;

    /*
     * ==========================================================
     * VALIDATE SUPPLIED TREASURY ADDRESS
     * ==========================================================
     */
    v_treasury_address :=
        nullif(
            btrim(p_treasury_address),
            ''
        );

    if v_treasury_address is null then
        raise exception
            'TREASURY_BLOCKCHAIN_ADDRESS_REQUIRED';
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

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * ==========================================================
     * LOCK CLAIMED ADJUSTMENT REQUEST
     * ==========================================================
     */
    select
        adjustment_record.*
    into
        v_request
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
     * VALIDATE REQUEST STATUS
     * ==========================================================
     */
    if v_request.status <>
       'approved'::public."AdjustmentStatus"
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_APPROVED';
    end if;

    /*
     * ==========================================================
     * VALIDATE EXECUTION CLAIM
     * ==========================================================
     */
    if v_request.executed_by is distinct from
       v_user.id
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_CLAIMED_BY_USER';
    end if;

    /*
     * ==========================================================
     * PREVENT DUPLICATE RECORDING
     * ==========================================================
     */
    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
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
     * RESOLVE BLOCKCHAIN CODE
     * ==========================================================
     *
     * Blockchain selection comes exclusively from the
     * approved adjustment request.
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
    select
        blockchain_record.*
    into
        v_blockchain
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
     * FETCH ACTIVE BLOCKCHAIN NETWORK
     * ==========================================================
     *
     * Uses the same network selection rules as
     * prepare_my_token_adjustment_execution.
     */
    select
        network_record.*
    into
        v_network
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
        btrim(v_network.treasury_wallet_address),
        ''
    ) is null then
        raise exception
            'TREASURY_WALLET_ADDRESS_NOT_CONFIGURED';
    end if;

    if nullif(
        btrim(v_network.explorer_url),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISSING';
    end if;

    /*
     * ==========================================================
     * VALIDATE TREASURY WALLET ADDRESS
     * ==========================================================
     *
     * The address passed by the Edge Function must match
     * the configured treasury address for this network.
     */
    if lower(v_treasury_address) <>
       lower(btrim(v_network.treasury_wallet_address))
    then
        raise exception
            'TREASURY_BLOCKCHAIN_ADDRESS_MISMATCH';
    end if;

    /*
     * ==========================================================
     * RESOLVE EXPLORER URL
     * ==========================================================
     *
     * explorer_url in supported_blockchain_network is the
     * explorer base URL.
     */
    v_expected_explorer_url :=
        rtrim(
            btrim(v_network.explorer_url),
            '/'
        ) ||
        '/tx/' ||
        v_tx_hash;

    v_explorer_url :=
        nullif(
            btrim(p_explorer_url),
            ''
        );

    /*
     * If an explorer URL was supplied, it must match
     * the URL derived from the configured network.
     */
    if v_explorer_url is not null
       and v_explorer_url <>
           v_expected_explorer_url
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISMATCH';
    end if;

    v_explorer_url :=
        v_expected_explorer_url;

    /*
     * ==========================================================
     * RESOLVE TRANSACTION TYPE AND ADDRESSES
     * ==========================================================
     */
    if v_request.adjustment_type =
       'minting'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_mint'::public."TransactionType";

        v_sender :=
            'contract';

        v_receiver :=
            v_network.treasury_wallet_address;

        v_description :=
            'Gold token minting - ' ||
            upper(v_blockchain_code);

    elsif v_request.adjustment_type =
          'burning'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_burn'::public."TransactionType";

        v_sender :=
            v_network.treasury_wallet_address;

        v_receiver :=
            'contract';

        v_description :=
            'Gold token burning - ' ||
            upper(v_blockchain_code);

    else
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * ==========================================================
     * PREVENT DUPLICATE BLOCKCHAIN HASH
     * ==========================================================
     *
     * Transaction hashes are checked within the selected
     * blockchain rather than across unrelated blockchains.
     */
    perform 1
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.blockchain_code =
          v_blockchain_code
      and lower(blockchain_record.tx_hash) =
          lower(v_tx_hash)
    limit 1;

    if found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    /*
     * ==========================================================
     * PREVENT DUPLICATE ADJUSTMENT TRANSACTION
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
     * FETCH FISCAL PERIOD
     * ==========================================================
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * INSERT CONFIRMED BLOCKCHAIN TRANSACTION
     * ==========================================================
     *
     * Blockchain execution has already succeeded.
     *
     * Pending means the blockchain transaction has been
     * recorded, but financial accounting is not yet complete.
     */
    insert into public.blockchain_transaction (
        fiscal_year,
        period,
        country_code,
        tx_hash,
        reference,
        transaction_type,
        blockchain_code,
        chain,
        sender,
        receiver,
        quantity,
        gross_amount,
        net_amount,
        fee_amount,
        currency_code,
        explorer_url,
        status,
        description,
        created_by
    )
    values (
        v_fiscal_year,
        v_period,
        v_user.country_code,
        v_tx_hash,
        v_request.id::text,
        v_transaction_type,
        v_blockchain_code,
        v_network.network_name,
        v_sender,
        v_receiver,
        v_request.quantity,
        0,
        0,
        0,
        'gold',
        v_explorer_url,
        'pending'::public."BlockchainTxStatus",
        v_description,
        v_user.id
    )
    returning id
    into v_blockchain_transaction_id;

    /*
     * ==========================================================
     * ATTACH BLOCKCHAIN HASH TO ADJUSTMENT REQUEST
     * ==========================================================
     *
     * Keep status approved until accounting completes.
     */
    update public.tokenised_asset_adjustment_request
    set
        tx_hash =
            v_tx_hash
    where id =
          v_request.id

      and status =
          'approved'::public."AdjustmentStatus"

      and executed_by =
          v_user.id

      and tx_hash is null;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_HASH_UPDATE_FAILED';
    end if;

    /*
     * ==========================================================
     * RETURN BLOCKCHAIN TRANSACTION RESULT
     * ==========================================================
     */
    return jsonb_build_object(
        'success',
        true,

        'adjustment_request_id',
        v_request.id::text,

        'blockchain_transaction_id',
        v_blockchain_transaction_id::text,

        'tx_hash',
        v_tx_hash,

        'transaction_type',
        v_transaction_type,

        'adjustment_type',
        v_request.adjustment_type,

        'quantity',
        v_request.quantity::text,

        'blockchain_code',
        v_blockchain_code,

        'network_name',
        v_network.network_name,

        'chain_id',
        v_network.chain_id,

        'treasury_wallet_address',
        v_network.treasury_wallet_address,

        'status',
        'pending',

        'explorer_url',
        v_explorer_url
    );
end;
$function$;