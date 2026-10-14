create or replace function public.complete_my_token_adjustment_execution(
    p_adjustment_request_id text,
    p_blockchain_transaction_id text,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
begin
    /*
     * Authenticate.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Preserve the existing treasury-role requirement.
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
     * Validate required identifiers.
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null
    then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    if nullif(
        btrim(p_blockchain_transaction_id),
        ''
    ) is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ID_REQUIRED';
    end if;

    /*
     * Fetch authenticated treasury employee.
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
     * Fetch the country treasury account.
     *
     * This account owns the treasury Gold wallet. The employee
     * executing the request does not own the wallet.
     */
    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Lock the adjustment request.
     */
    select adjustment_record.*
    into v_request
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.id::text =
          btrim(
              p_adjustment_request_id
          )
    for update;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_FOUND';
    end if;

    if v_request.status <>
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
    ) is null
    then
        raise exception
            'ADJUSTMENT_REQUEST_BLOCKCHAIN_HASH_NOT_FOUND';
    end if;

    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

    v_quantity :=
        v_request.quantity;

    /*
     * Resolve transaction context.
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
            'Gold token minting';

        v_wallet_debit :=
            0;

        v_wallet_credit :=
            v_quantity;
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
            'Gold token burning';

        v_wallet_debit :=
            v_quantity;

        v_wallet_credit :=
            0;
    else
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * Lock the pending blockchain transaction.
     */
    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          btrim(
              p_blockchain_transaction_id
          )
    for update;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_NOT_FOUND';
    end if;

    if v_blockchain_transaction.reference is distinct from
       v_request.id::text
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_REQUEST_MISMATCH';
    end if;

    if lower(
        v_blockchain_transaction.tx_hash
    ) is distinct from
       lower(
           v_request.tx_hash
       )
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_HASH_MISMATCH';
    end if;

    if v_blockchain_transaction.transaction_type <>
       v_transaction_type
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_TYPE_MISMATCH';
    end if;

    if v_blockchain_transaction.country_code is distinct from
       v_user.country_code
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH';
    end if;

    if v_blockchain_transaction.status <>
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
     * Fetch GL mappings.
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
     * Build Gold posting components.
     */
    v_components :=
        public.build_posting_components(
            v_transaction_type,
            v_quantity,
            v_mappings,
            v_user.country_code,
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
     * Fetch configured document prefix.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Generate accounting document.
     */
    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * Create financial transaction header.
     *
     * The blockchain hash becomes the unique financial
     * transaction reference.
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
        v_user.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post financial entries.
     */
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_user.country_code,

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
     * Lock the country treasury Gold wallet.
     */
    select wallet_record.*
    into v_treasury_wallet
    from public.wallet
        wallet_record
    where wallet_record.country_code =
          v_user.country_code

      and wallet_record.user_id =
          v_treasury.id

      and lower(
          wallet_record.currency_code
      ) =
          'gold'

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"
    for update;

    /*
     * Minting may create the treasury Gold wallet if this is
     * the first token supply operation.
     */
    if v_request.adjustment_type =
       'minting'::public."TokenAdjustmentType"
    then
        if not found then
            insert into public.wallet (
                country_code,
                user_id,
                currency_code,
                owner_type,
                balance,
                is_active
            )
            values (
                v_user.country_code,
                v_treasury.id,
                'gold',
                'treasury'::public."WalletOwnerType",
                v_quantity,
                true
            )
            returning *
            into v_treasury_wallet;

            v_wallet_balance_before :=
                0;

            v_wallet_balance_after :=
                v_quantity;
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
            set
                balance =
                    balance +
                    v_quantity
            where id =
                  v_treasury_wallet.id

              and is_active =
                  true
            returning *
            into v_treasury_wallet;

            if not found then
                raise exception
                    'TREASURY_GOLD_WALLET_UPDATE_FAILED';
            end if;

            v_wallet_balance_after :=
                v_treasury_wallet.balance;
        end if;
    else
        /*
         * Burning requires an existing active wallet with
         * enough tokens.
         */
        if not found then
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
        set
            balance =
                balance -
                v_quantity
        where id =
              v_treasury_wallet.id

          and is_active =
              true

          and balance >=
              v_quantity
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
     * Create treasury Gold wallet entry.
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
        v_user.country_code
    );

    /*
     * Update treasury Gold wallet snapshot.
     *
     * Minting is a receiver credit.
     * Burning is a sender debit.
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
        v_user.country_code,
        0
    );

    /*
     * Finalize adjustment request.
     */
    update public.tokenised_asset_adjustment_request
    set
        status =
            v_final_status,

        executed_by =
            v_user.id,

        executed_at =
            now(),

        tx_hash =
            v_request.tx_hash
    where id =
          v_request.id

      and status =
          'approved'::public."AdjustmentStatus"

      and executed_by =
          v_user.id

      and tx_hash =
          v_request.tx_hash;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_COMPLETION_FAILED';
    end if;

    /*
     * Complete the existing blockchain record.
     *
     * blockchain_transaction does not have updated_at.
     */
    update public.blockchain_transaction
    set
        document_number =
            v_document_number,

        status =
            'completed'::public."BlockchainTxStatus"
    where id =
          v_blockchain_transaction.id

      and status =
          'pending'::public."BlockchainTxStatus"

      and document_number is null;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COMPLETION_FAILED';
    end if;

    /*
     * Audit completed mint or burn.
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
        v_user.country_code,
        v_document_number,
        v_user.id,
        v_audit_action,
        'treasury',
        v_treasury.id,

        jsonb_build_object(
            'treasury_gold_balance',
            v_wallet_balance_before::text
        ),

        jsonb_build_object(
            'treasury_gold_balance',
            v_wallet_balance_after::text
        ),

        jsonb_build_object(
            'adjustment_request_id',
            v_request.id::text,

            'blockchain_transaction_id',
            v_blockchain_transaction.id::text,

            'tx_hash',
            v_request.tx_hash,

            'adjustment_type',
            v_request.adjustment_type,

            'quantity',
            v_quantity::text
        ),

        p_ip_address
    );

    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_document_number,

        'adjustment_request_id',
        v_request.id::text,

        'blockchain_transaction_id',
        v_blockchain_transaction.id::text,

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

        'treasury_gold_balance',
        v_wallet_balance_after::text
    );
end;
$function$;


revoke all on function
    public.complete_my_token_adjustment_execution(
        text,
        text,
        text
    )
from public;

revoke all on function
    public.complete_my_token_adjustment_execution(
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.complete_my_token_adjustment_execution(
        text,
        text,
        text
    )
to authenticated;

notify pgrst, 'reload schema';