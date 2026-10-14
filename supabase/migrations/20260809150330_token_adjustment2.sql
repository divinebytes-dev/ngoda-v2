create or replace function public.record_my_token_adjustment_blockchain_transaction(
    p_adjustment_request_id text,
    p_tx_hash text,
    p_treasury_address text,
    p_explorer_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_request
        public.tokenised_asset_adjustment_request%rowtype;

    v_transaction_type
        public."TransactionType";

    v_fiscal_year integer;
    v_period integer;

    v_sender text;
    v_receiver text;
    v_description text;

    v_tx_hash text;
    v_treasury_address text;
    v_explorer_url text;

    v_blockchain_transaction_id
        public.blockchain_transaction.id%type;
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
     * Validate request identifier.
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null
    then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    /*
     * Validate confirmed blockchain hash.
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
     * Validate treasury blockchain address.
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

    v_explorer_url :=
        nullif(
            btrim(p_explorer_url),
            ''
        );

    /*
     * Fetch authenticated treasury user.
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
     * Lock the claimed adjustment request.
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

    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

    /*
     * Resolve blockchain transaction context.
     */
    if v_request.adjustment_type =
       'minting'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_mint'::public."TransactionType";

        v_sender :=
            'contract';

        v_receiver :=
            v_treasury_address;

        v_description :=
            'Gold token minting';
    elsif v_request.adjustment_type =
          'burning'::public."TokenAdjustmentType"
    then
        v_transaction_type :=
            'gold_token_burn'::public."TransactionType";

        v_sender :=
            v_treasury_address;

        v_receiver :=
            'contract';

        v_description :=
            'Gold token burning';
    else
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * Prevent the same transaction hash from being recorded
     * more than once.
     */
    perform 1
    from public.blockchain_transaction
        blockchain_record
    where lower(
        blockchain_record.tx_hash
    ) =
        lower(
            v_tx_hash
        )
    limit 1;

    if found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end if;

    /*
     * Prevent more than one blockchain transaction from being
     * attached to the same adjustment request.
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
     * Fetch fiscal period.
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
     * Store the confirmed blockchain transaction as pending.
     *
     * pending means blockchain execution succeeded but the
     * accounting document has not yet been committed.
     */
    insert into public.blockchain_transaction (
        fiscal_year,
        period,
        country_code,
        tx_hash,
        reference,
        transaction_type,
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
        'chiado',
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
     * Attach the irreversible hash to the request immediately.
     *
     * The status remains approved until accounting completes.
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

        'status',
        'pending',

        'explorer_url',
        v_explorer_url
    );
end;
$function$;


revoke all on function
    public.record_my_token_adjustment_blockchain_transaction(
        text,
        text,
        text,
        text
    )
from public;

revoke all on function
    public.record_my_token_adjustment_blockchain_transaction(
        text,
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.record_my_token_adjustment_blockchain_transaction(
        text,
        text,
        text,
        text
    )
to authenticated;

notify pgrst, 'reload schema';