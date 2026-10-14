DROP FUNCTION IF EXISTS public.record_gold_buy_blockchain_transaction(
    text,
    jsonb,
    text,
    text,
    text,
    text
);

CREATE OR REPLACE FUNCTION public.record_gold_buy_blockchain_transaction(
    p_user_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_tx_hash text,
    p_explorer_url text,
    p_blockchain_code text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_preparation record;
    v_user public.users%rowtype;

    v_reference text;
    v_blockchain_code text;
    v_blockchain_transaction_id text;

    v_expected_explorer_url text;
begin
    /*
     * =====================================================
     * VALIDATE BLOCKCHAIN CODE
     * =====================================================
     */

    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    /*
     * =====================================================
     * VALIDATE BLOCKCHAIN TRANSACTION HASH
     * =====================================================
     */

    if p_tx_hash is null
       or p_tx_hash !~ '^0x[0-9a-fA-F]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    /*
     * =====================================================
     * VALIDATE TRANSACTION REFERENCE
     * =====================================================
     */

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    /*
     * =====================================================
     * FETCH TRUSTED GOLD BUY PREPARATION
     * =====================================================
     *
     * prepare_gold_buy validates:
     *
     * - Processing transaction state
     * - Signed transaction data
     * - Selected blockchain
     * - Blockchain stored in transaction state
     * - Active blockchain network
     * - Buyer authorization
     * - Treasury configuration
     * - Gold pricing and quantities
     */

    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) as preparation;

    if not found then
        raise exception
            'GOLD_BUY_PREPARATION_NOT_FOUND';
    end if;

    /*
     * =====================================================
     * VERIFY SELECTED BLOCKCHAIN
     * =====================================================
     */

    if v_preparation.blockchain_code
       is distinct from v_blockchain_code
    then
        raise exception
            'BLOCKCHAIN_CODE_MISMATCH';
    end if;

    /*
     * =====================================================
     * VALIDATE EXPLORER URL
     * =====================================================
     *
     * The Edge Function must construct the explorer URL
     * using the selected network's configuration.
     *
     * Assumes explorer_url is a base URL.
     */

    if v_preparation.explorer_url is null
       or btrim(v_preparation.explorer_url) = ''
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_NOT_CONFIGURED';
    end if;

    v_expected_explorer_url :=
        rtrim(v_preparation.explorer_url, '/')
        || '/tx/'
        || lower(p_tx_hash);

    if p_explorer_url is null
       or p_explorer_url is distinct from
          v_expected_explorer_url
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISMATCH';
    end if;

    /*
     * =====================================================
     * FETCH USER
     * =====================================================
     */

    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );

    /*
     * =====================================================
     * RECORD BLOCKCHAIN TRANSACTION
     * =====================================================
     */

    insert into public.blockchain_transaction (
        fiscal_year,
        period,
        country_code,
        tx_hash,
        document_number,
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
        created_by,
        description
    )
    values (
        v_preparation.fiscal_year,
        v_preparation.period,
        p_country_code,
        lower(p_tx_hash),
        null,
        v_reference,
        'gold_token_buy'::public."TransactionType",

        /*
         * Store the blockchain code rather than
         * the network name.
         *
         * Example: gnosis, polygon, ethereum.
         */
        v_blockchain_code,

        v_preparation.treasury_wallet_address,
        v_preparation.user_wallet_address,
        v_preparation.token_quantity::numeric,
        v_preparation.input_amount::numeric,
        0,
        v_preparation.token_fee::numeric,
        v_preparation.input_currency,
        v_expected_explorer_url,
        'pending'::public."BlockchainTxStatus",
        p_user_id,

        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.token_quantity ||
        'g Gold tokens on ' ||
        v_blockchain_code
    )
    returning id::text
    into v_blockchain_transaction_id;

    return v_blockchain_transaction_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'BLOCKCHAIN_TRANSACTION_REPLAY';
end;
$function$;