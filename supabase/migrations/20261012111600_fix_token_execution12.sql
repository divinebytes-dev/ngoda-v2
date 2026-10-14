CREATE OR REPLACE FUNCTION public.complete_my_token_adjustment_execution(p_adjustment_request_id text, p_blockchain_transaction_id text, p_ip_address text DEFAULT NULL::text)
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

/*
 * ==========================================================
 * VALIDATE ORIGINAL INVENTORY PURCHASE CURRENCY
 * ==========================================================
 *
 * The adjustment request's currency_code represents the
 * original currency used to purchase physical gold.
 *
 * It can be USD, ZIG, ZAR, etc.
 *
 * GOLD remains the currency used for the blockchain
 * transaction, GL entries and treasury wallet.
 */
if nullif(
    lower(
        btrim(
            v_request.currency_code::text
        )
    ),
    ''
) is null then
    raise exception
        'ADJUSTMENT_PURCHASE_CURRENCY_REQUIRED';
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
 *
 * GOLD wallet entries must identify the blockchain.
 */
insert into public.wallet_entry (
    fiscal_year,
    period,
    document_number,
    reference,
    transaction_type,
    wallet_id,
    currency_code,
    blockchain_code,
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
    v_blockchain_code,
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
$function$


