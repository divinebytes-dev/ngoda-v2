CREATE OR REPLACE FUNCTION public.release_my_token_adjustment_execution(
    p_adjustment_request_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_request_id text;

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
     * Only a Zimbabwe treasury user may release a claim
     * associated with a minting or burning adjustment.
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
     * RELEASE EXECUTION CLAIM
     * ==========================================================
     *
     * Release only when:
     *
     * 1. The adjustment is still approved.
     * 2. The claim belongs to the authenticated user.
     * 3. No blockchain transaction hash has been attached.
     * 4. No blockchain transaction record exists.
     *
     * Do not restrict by the adjustment request's country.
     * Minting and burning are centrally managed by Zimbabwe.
     *
     * The Edge Function must only call this function before
     * blockchain execution begins.
     */
    update public.tokenised_asset_adjustment_request
    set
        executed_by = null
    where id::text =
          btrim(p_adjustment_request_id)

      and status =
          'approved'::public."AdjustmentStatus"

      and executed_by =
          v_user.id

      and tx_hash is null

      and not exists (
          select 1
          from public.blockchain_transaction
              blockchain_record
          where blockchain_record.reference =
                public.tokenised_asset_adjustment_request.id::text
      )

    returning id::text
    into v_request_id;

    /*
     * ==========================================================
     * VALIDATE RELEASE
     * ==========================================================
     */
    if v_request_id is null then
        raise exception
            'ADJUSTMENT_EXECUTION_CLAIM_NOT_RELEASED';
    end if;

    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     */
    return jsonb_build_object(
        'success',
        true,

        'adjustment_request_id',
        v_request_id,

        'released',
        true
    );
end;
$function$;


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

    v_tx_hash :=
        nullif(
            btrim(p_tx_hash),
            ''
        );

    if v_tx_hash is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_HASH_REQUIRED';
    end if;

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

    /*
     * ==========================================================
     * CENTRAL MINTING TREASURY AUTHORIZATION
     * ==========================================================
     *
     * Zimbabwe is the designated country responsible
     * for minting and burning GOLD tokens.
     *
     * Other country treasuries receive GOLD tokens
     * through transfers, not through minting.
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
     * LOCK CLAIMED ADJUSTMENT REQUEST
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
     * VALIDATE REQUEST STATUS AND CLAIM
     * ==========================================================
     */
    if v_request.status is distinct from
       'approved'::public."AdjustmentStatus"
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_APPROVED';
    end if;

    if v_request.executed_by is distinct from
       v_user.id
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_CLAIMED_BY_USER';
    end if;

    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    /*
     * ==========================================================
     * VALIDATE ADJUSTMENT QUANTITY AND CURRENCY
     * ==========================================================
     */
    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

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
     * Blockchain selection comes from the approved request.
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
     * FETCH ACTIVE BLOCKCHAIN NETWORK
     * ==========================================================
     *
     * Uses the same network selection rules as preparation.
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
     * VALIDATE TREASURY BLOCKCHAIN ADDRESS
     * ==========================================================
     */
    if lower(v_treasury_address) <>
       lower(btrim(v_network.treasury_wallet_address))
    then
        raise exception
            'TREASURY_BLOCKCHAIN_ADDRESS_MISMATCH';
    end if;

    /*
     * ==========================================================
     * BUILD EXPLORER URL
     * ==========================================================
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
     * RESOLVE TRANSACTION TYPE
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
     * PREVENT DUPLICATE ADJUSTMENT RECORD
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
     * FETCH ZIMBABWE FISCAL PERIOD
     * ==========================================================
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_minting_country_code
    ) as fiscal_period;

    if not found
       or v_fiscal_year is null
       or v_period is null
    then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * INSERT BLOCKCHAIN TRANSACTION
     * ==========================================================
     *
     * The on-chain transaction has already been confirmed.
     *
     * Pending indicates that internal accounting
     * has not yet been completed.
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
        v_minting_country_code,
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
     */
    update public.tokenised_asset_adjustment_request
    set tx_hash = v_tx_hash
    where id = v_request.id
      and status =
          'approved'::public."AdjustmentStatus"
      and executed_by = v_user.id
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

        'country_code',
        v_minting_country_code,

        'status',
        'pending',

        'explorer_url',
        v_explorer_url
    );
end;
$function$;


CREATE OR REPLACE FUNCTION public.complete_my_token_adjustment_execution(
    p_adjustment_request_id text,
    p_blockchain_transaction_id text,
    p_ip_address text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_request
        public.tokenised_asset_adjustment_request%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_treasury_wallet
        public.wallet%rowtype;

    v_transaction_type
        public."TransactionType";

    v_final_status
        public."AdjustmentStatus";

    v_audit_action
        public."AuditActionType";

    v_quantity numeric;

    v_wallet_debit numeric := 0;
    v_wallet_credit numeric := 0;

    v_wallet_balance_before numeric := 0;
    v_wallet_balance_after numeric := 0;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;
    v_description text;

    v_financial_transaction_id bigint;

    v_fiscal_year integer;
    v_period integer;

    v_blockchain_code text;

    v_minting_country_code constant text := 'zw';

    v_wallet_found boolean := false;
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

    if nullif(
        btrim(p_blockchain_transaction_id),
        ''
    ) is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ID_REQUIRED';
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
     * FETCH ZIMBABWE TREASURY ACCOUNT
     * ==========================================================
     */
    v_treasury :=
        public.fetch_country_treasury(
            v_minting_country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
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

    if v_request.status is distinct from
       'approved'::public."AdjustmentStatus"
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_APPROVED';
    end if;

    if v_request.executed_by is distinct from
       v_user.id
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_CLAIMED_BY_USER';
    end if;

    if nullif(
        btrim(v_request.tx_hash),
        ''
    ) is null then
        raise exception
            'ADJUSTMENT_REQUEST_BLOCKCHAIN_HASH_NOT_FOUND';
    end if;

    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

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
     * RESOLVE BLOCKCHAIN
     * ==========================================================
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

    v_quantity :=
        v_request.quantity;

    /*
     * ==========================================================
     * RESOLVE TRANSACTION TYPE
     * ==========================================================
     */
    if v_request.adjustment_type =
       'minting'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_mint'::public."TransactionType";

        v_final_status :=
            'minted'::public."AdjustmentStatus";

        v_audit_action :=
            'token_minted'::public."AuditActionType";

        v_description :=
            'Gold token minting - ' ||
            upper(v_blockchain_code);

        v_wallet_debit := 0;
        v_wallet_credit := v_quantity;

    elsif v_request.adjustment_type =
          'burning'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_burn'::public."TransactionType";

        v_final_status :=
            'burned'::public."AdjustmentStatus";

        v_audit_action :=
            'token_burned'::public."AuditActionType";

        v_description :=
            'Gold token burning - ' ||
            upper(v_blockchain_code);

        v_wallet_debit := v_quantity;
        v_wallet_credit := 0;

    else
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * ==========================================================
     * LOCK BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          btrim(p_blockchain_transaction_id)
    for update;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    if v_blockchain_transaction.reference
       is distinct from v_request.id::text
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_REQUEST_MISMATCH';
    end if;

    if lower(v_blockchain_transaction.tx_hash)
       is distinct from lower(v_request.tx_hash)
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_HASH_MISMATCH';
    end if;

    if v_blockchain_transaction.transaction_type
       is distinct from v_transaction_type
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_TYPE_MISMATCH';
    end if;

    /*
     * Mint/burn accounting belongs to Zimbabwe.
     */
    if lower(
        btrim(
            coalesce(
                v_blockchain_transaction.country_code,
                ''
            )
        )
    ) <> v_minting_country_code then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH';
    end if;

    /*
     * Validate the blockchain independently of country.
     */
    if lower(
        btrim(
            coalesce(
                v_blockchain_transaction.blockchain_code,
                ''
            )
        )
    ) <> v_blockchain_code then
        raise exception
            'BLOCKCHAIN_TRANSACTION_CHAIN_MISMATCH';
    end if;

    if lower(
        btrim(
            coalesce(
                v_blockchain_transaction.currency_code,
                ''
            )
        )
    ) <> 'gold' then
        raise exception
            'BLOCKCHAIN_TRANSACTION_CURRENCY_MISMATCH';
    end if;

    if v_blockchain_transaction.quantity
       is distinct from v_quantity
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_QUANTITY_MISMATCH';
    end if;

    if v_blockchain_transaction.status is distinct from
       'pending'::public."BlockchainTxStatus"
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_NOT_PENDING';
    end if;

    if v_blockchain_transaction.document_number is not null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ALREADY_POSTED';
    end if;

    v_fiscal_year :=
        v_blockchain_transaction.fiscal_year;

    v_period :=
        v_blockchain_transaction.period;

    if v_fiscal_year is null
       or v_period is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_FISCAL_PERIOD_MISSING';
    end if;

    /*
     * ==========================================================
     * FETCH GL MAPPINGS
     * ==========================================================
     */
    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        v_transaction_type
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * BUILD POSTING COMPONENTS
     * ==========================================================
     */
    v_components :=
        public.build_posting_components(
            v_transaction_type,
            v_quantity,
            v_mappings,
            v_minting_country_code,
            'gold',
            false
        );

    if v_components is null
       or cardinality(v_components) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * ==========================================================
     * GENERATE ACCOUNTING DOCUMENT NUMBER
     * ==========================================================
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );

    if nullif(
        btrim(v_document_prefix),
        ''
    ) is null then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_minting_country_code
        );

    /*
     * ==========================================================
     * CREATE FINANCIAL TRANSACTION
     * ==========================================================
     *
     * financial_transaction does not have blockchain_code.
     * The blockchain is included in the description.
     */
    insert into public.financial_transaction (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_request.tx_hash,
        v_fiscal_year,
        v_period,
        v_transaction_type,
        v_description,
        v_user.id,
        v_quantity,
        'gold',
        v_minting_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * ==========================================================
     * POST FINANCIAL ENTRIES
     * ==========================================================
     */
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_minting_country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            v_transaction_type,

        p_created_by =>
            v_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_request.id::text,

        p_deposit_type =>
            null
    );

    /*
     * ==========================================================
     * LOCK ZIMBABWE TREASURY GOLD WALLET
     * ==========================================================
     *
     * Wallet balances remain country-specific and
     * blockchain-specific.
     */
    select wallet_record.*
    into v_treasury_wallet
    from public.wallet
        wallet_record
    where wallet_record.country_code =
          v_minting_country_code

      and wallet_record.user_id =
          v_treasury.id

      and lower(wallet_record.currency_code) =
          'gold'

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"

      and wallet_record.blockchain_code =
          v_blockchain_code

    for update;

    v_wallet_found := found;

    /*
     * ==========================================================
     * MINT GOLD TOKENS
     * ==========================================================
     */
    if v_request.adjustment_type =
       'minting'::public."TokenAdjustmentType"
    then
        /*
         * Create Zimbabwe's GOLD wallet for this blockchain
         * if it does not already exist.
         */
        if not v_wallet_found then

            insert into public.wallet (
                country_code,
                user_id,
                currency_code,
                blockchain_code,
                owner_type,
                balance,
                is_active
            )
            values (
                v_minting_country_code,
                v_treasury.id,
                'gold',
                v_blockchain_code,
                'treasury'::public."WalletOwnerType",
                v_quantity,
                true
            )
            returning *
            into v_treasury_wallet;

            v_wallet_balance_before := 0;
            v_wallet_balance_after := v_quantity;

        else
            if not v_treasury_wallet.is_active then
                raise exception
                    'TREASURY_GOLD_WALLET_FROZEN';
            end if;

            v_wallet_balance_before :=
                coalesce(
                    v_treasury_wallet.balance,
                    0
                );

            update public.wallet
            set balance =
                coalesce(balance, 0) + v_quantity
            where id = v_treasury_wallet.id
              and is_active = true
            returning *
            into v_treasury_wallet;

            if not found then
                raise exception
                    'TREASURY_GOLD_WALLET_UPDATE_FAILED';
            end if;

            v_wallet_balance_after :=
                v_treasury_wallet.balance;
        end if;

    /*
     * ==========================================================
     * BURN GOLD TOKENS
     * ==========================================================
     */
    else
        if not v_wallet_found then
            raise exception
                'TREASURY_GOLD_WALLET_NOT_FOUND';
        end if;

        if not v_treasury_wallet.is_active then
            raise exception
                'TREASURY_GOLD_WALLET_FROZEN';
        end if;

        v_wallet_balance_before :=
            coalesce(
                v_treasury_wallet.balance,
                0
            );

        update public.wallet
        set balance =
            balance - v_quantity
        where id = v_treasury_wallet.id
          and is_active = true
          and balance >= v_quantity
        returning *
        into v_treasury_wallet;

        if not found then
            raise exception
                'INSUFFICIENT_TREASURY_GOLD_BALANCE';
        end if;

        v_wallet_balance_after :=
            v_treasury_wallet.balance;
    end if;

    /*
     * ==========================================================
     * CREATE TREASURY WALLET ENTRY
     * ==========================================================
     */
    insert into public.wallet_entry (
        fiscal_year,
        period,
        document_number,
        reference,
        transaction_type,
        wallet_id,
        currency_code,
        debit,
        credit,
        created_by,
        country_code
    )
    values (
        v_fiscal_year,
        v_period,
        v_document_number,
        v_request.id::text,
        v_transaction_type,
        v_treasury_wallet.id,
        'gold',
        v_wallet_debit,
        v_wallet_credit,
        v_user.id,
        v_minting_country_code
    );

    /*
     * ==========================================================
     * UPDATE BLOCKCHAIN-SPECIFIC WALLET SNAPSHOT
     * ==========================================================
     */
    perform public.update_wallet_balance_snapshot(
        v_transaction_type,
        v_treasury.id,
        v_treasury.id,
        null,
        'gold',
        'treasury'::public."WalletOwnerType",
        'treasury'::public."WalletOwnerType",
        v_wallet_debit,
        v_wallet_credit,
        v_fiscal_year,
        v_period,
        v_minting_country_code,
        0,
        v_blockchain_code
    );

    /*
     * ==========================================================
     * FINALIZE ADJUSTMENT REQUEST
     * ==========================================================
     */
    update public.tokenised_asset_adjustment_request
    set
        status = v_final_status,
        executed_by = v_user.id,
        executed_at = now(),
        tx_hash = v_request.tx_hash
    where id = v_request.id
      and status =
          'approved'::public."AdjustmentStatus"
      and executed_by = v_user.id
      and tx_hash = v_request.tx_hash;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_COMPLETION_FAILED';
    end if;

    /*
     * ==========================================================
     * COMPLETE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    update public.blockchain_transaction
    set
        document_number = v_document_number,
        status =
            'completed'::public."BlockchainTxStatus"
    where id = v_blockchain_transaction.id
      and blockchain_code = v_blockchain_code
      and status =
          'pending'::public."BlockchainTxStatus"
      and document_number is null;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COMPLETION_FAILED';
    end if;

    /*
     * ==========================================================
     * AUDIT COMPLETED TOKEN ADJUSTMENT
     * ==========================================================
     */
    insert into public.audit_log (
        fiscal_year,
        period,
        country_code,
        document_number,
        user_id,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata,
        ip_address
    )
    values (
        v_fiscal_year,
        v_period,
        v_minting_country_code,
        v_document_number,
        v_user.id,
        v_audit_action,
        'treasury',
        v_treasury.id,

        jsonb_build_object(
            'blockchain_code',
            v_blockchain_code,

            'treasury_gold_balance',
            v_wallet_balance_before::text
        ),

        jsonb_build_object(
            'blockchain_code',
            v_blockchain_code,

            'treasury_gold_balance',
            v_wallet_balance_after::text
        ),

        jsonb_build_object(
            'adjustment_request_id',
            v_request.id::text,

            'blockchain_transaction_id',
            v_blockchain_transaction.id::text,

            'blockchain_code',
            v_blockchain_code,

            'network_name',
            v_blockchain_transaction.chain,

            'tx_hash',
            v_request.tx_hash,

            'adjustment_type',
            v_request.adjustment_type,

            'quantity',
            v_quantity::text,

            'wallet_id',
            v_treasury_wallet.id
        ),

        p_ip_address
    );

    /*
     * ==========================================================
     * RETURN COMPLETED TRANSACTION
     * ==========================================================
     */
    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_document_number,

        'adjustment_request_id',
        v_request.id::text,

        'blockchain_transaction_id',
        v_blockchain_transaction.id::text,

        'blockchain_code',
        v_blockchain_code,

        'network_name',
        v_blockchain_transaction.chain,

        'transaction_type',
        v_transaction_type,

        'adjustment_type',
        v_request.adjustment_type,

        'adjusted_quantity',
        v_quantity::text,

        'status',
        v_final_status,

        'tx_hash',
        v_request.tx_hash,

        'explorer_url',
        v_blockchain_transaction.explorer_url,

        'treasury_wallet_id',
        v_treasury_wallet.id,

        'treasury_gold_balance',
        v_wallet_balance_after::text
    );
end;
$function$;