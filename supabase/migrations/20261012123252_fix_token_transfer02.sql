
CREATE OR REPLACE FUNCTION public.record_gold_transfer_blockchain_transaction(
    p_sender_id text,
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
DECLARE
    v_preparation record;

    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;

    v_blockchain_code text;
    v_blockchain_transaction_id text;
BEGIN
    /*
     * ==========================================================
     * AUTHORIZATION
     * ==========================================================
     */
    IF coalesce(auth.role(), '') <> 'service_role'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE INPUTS
     * ==========================================================
     */
    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    IF p_tx_hash IS NULL
       OR btrim(p_tx_hash) !~ '^0x[0-9a-fA-F]{64}$'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    IF p_explorer_url IS NULL
       OR btrim(p_explorer_url) = ''
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_URL_IS_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * PREPARE AND VALIDATE TRANSFER
     * ==========================================================
     */
    SELECT preparation_record.*
    INTO v_preparation
    FROM public.prepare_gold_transfer(
        p_sender_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'GOLD_TRANSFER_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * FETCH USERS
     * ==========================================================
     */
    v_sender :=
        public.fetch_user_by_id(
            v_preparation.sender_id
        );

    v_receiver :=
        public.fetch_user_by_id(
            v_preparation.receiver_id
        );

    IF v_sender.id IS NULL THEN
        RAISE EXCEPTION 'SENDER_NOT_FOUND';
    END IF;

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION 'RECEIVER_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * RECORD BLOCKCHAIN TRANSACTION
     * ==========================================================
     *
     * The transaction has been confirmed on-chain,
     * but remains pending until accounting commits.
     *
     * The chain column now contains the blockchain code,
     * rather than the previously hardcoded network name.
     */
    BEGIN
        INSERT INTO public.blockchain_transaction (
            tx_hash,
            fiscal_year,
            period,
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
            country_code,
            reference,
            description
        )
        VALUES (
            btrim(p_tx_hash),
            v_preparation.fiscal_year,
            v_preparation.period,
            'gold_token_transfer'::public."TransactionType",
            v_blockchain_code,
            v_preparation.sender_wallet_address,
            v_preparation.receiver_wallet_address,
            v_preparation.amount::numeric,
            0,
            0,
            v_preparation.fee::numeric,
            'gold',
            btrim(p_explorer_url),
            'pending'::public."BlockchainTxStatus",
            v_preparation.sender_id,
            v_preparation.country_code,
            p_transaction ->> 'r',
            'User ' ||
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ) ||
            ' transferred ' ||
            v_preparation.amount ||
            'g Gold tokens to user ' ||
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        )
        RETURNING id::text
        INTO v_blockchain_transaction_id;

    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION
                'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    END;

    IF v_blockchain_transaction_id IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    END IF;

    RETURN v_blockchain_transaction_id;
END;
$function$;
