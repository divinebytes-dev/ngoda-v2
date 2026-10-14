DROP FUNCTION IF EXISTS public.record_gold_sell_blockchain_transaction(
    text,
    jsonb,
    text,
    text,
    text,
    text
);

CREATE OR REPLACE FUNCTION public.record_gold_sell_blockchain_transaction(
    p_seller_id text,
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
    v_state public.transaction_state%rowtype;

    v_preparation record;

    v_blockchain_code text;
    v_reference text;
    v_tx_hash text;
    v_explorer_url text;

    v_blockchain_id text;

    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_network_explorer_url text;

    v_stage text := 'INITIALIZATION';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'SERVICE_ROLE_VALIDATION';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_IS_MISSING';
    END IF;

    IF p_seller_id IS NULL
       OR btrim(p_seller_id) = ''
    THEN
        RAISE EXCEPTION
            'SELLER_ID_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION
            'COUNTRY_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_stage := 'BLOCKCHAIN_VALIDATION';

    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Confirm the blockchain is active and has
     * an active network.
     *
     * The active network's explorer URL is used
     * to validate the supplied explorer link.
     */
    SELECT
        n.explorer_url
    INTO
        v_network_explorer_url
    FROM public.supported_blockchain AS b
    JOIN LATERAL (
        SELECT
            network.explorer_url
        FROM public.supported_blockchain_network AS network
        WHERE network.blockchain_id = b.id
          AND network.is_active = true
        ORDER BY
            network.is_default DESC,
            network.created_at DESC,
            network.id
        LIMIT 1
    ) AS n ON true
    WHERE b.code = v_blockchain_code
      AND b.is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    /*
     * ==========================================================
     * 3. VALIDATE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'TRANSACTION_STATE_VALIDATION';

    SELECT state_record.*
    INTO v_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND state_record.created_by = p_seller_id
      AND state_record.user_id = p_seller_id
      AND state_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_state.transaction_data
       IS DISTINCT FROM p_transaction
    THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_MISMATCH';
    END IF;

    IF lower(btrim(v_state.blockchain_code))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF p_transaction ->> 'v'
       IS DISTINCT FROM 'v7'
    THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    IF v_state.reference
       IS DISTINCT FROM v_reference
    THEN
        RAISE EXCEPTION
            'TRANSACTION_REFERENCE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 4. VALIDATE BLOCKCHAIN TRANSACTION HASH
     * ==========================================================
     */
    v_stage := 'TRANSACTION_HASH_VALIDATION';

    v_tx_hash :=
        nullif(
            btrim(p_tx_hash),
            ''
        );

    IF v_tx_hash IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_HASH_REQUIRED';
    END IF;

    IF v_tx_hash !~ '^0x[0-9a-fA-F]{64}$' THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    /*
     * ==========================================================
     * 5. VALIDATE EXPLORER URL
     * ==========================================================
     */
    v_stage := 'EXPLORER_URL_VALIDATION';

    v_explorer_url :=
        nullif(
            btrim(p_explorer_url),
            ''
        );

    IF v_explorer_url IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_URL_REQUIRED';
    END IF;

    IF v_network_explorer_url IS NULL
       OR btrim(v_network_explorer_url) = ''
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_NOT_CONFIGURED';
    END IF;

    /*
     * Ensure the explorer URL belongs to the
     * selected blockchain network.
     */
    IF v_explorer_url IS DISTINCT FROM
       (
           rtrim(
               btrim(v_network_explorer_url),
               '/'
           ) || '/tx/' || v_tx_hash
       )
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_URL_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 6. PREPARE GOLD SELL
     * ==========================================================
     */
    v_stage := 'PREPARE_GOLD_SELL';

    SELECT preparation.*
    INTO v_preparation
    FROM public.prepare_gold_sell(
        p_seller_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'GOLD_SELL_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'PREPARATION_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 7. VALIDATE SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'VALIDATE_SELLER_AND_TREASURY';

    v_seller :=
        public.fetch_user_by_id(
            p_seller_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION
            'TREASURY_NOT_FOUND';
    END IF;

    IF lower(btrim(v_seller.wallet_address))
       IS DISTINCT FROM
       lower(btrim(v_preparation.seller_wallet_address))
    THEN
        RAISE EXCEPTION
            'SELLER_WALLET_ADDRESS_MISMATCH';
    END IF;

    IF lower(btrim(v_treasury.wallet_address))
       IS DISTINCT FROM
       lower(btrim(v_preparation.treasury_wallet_address))
    THEN
        RAISE EXCEPTION
            'TREASURY_WALLET_ADDRESS_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 8. VALIDATE PREPARED VALUES
     * ==========================================================
     */
    v_stage := 'VALIDATE_PREPARED_VALUES';

    IF v_preparation.token_quantity::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_TOKEN_QUANTITY';
    END IF;

    IF v_preparation.gross_amount::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GROSS_AMOUNT';
    END IF;

    IF v_preparation.net_amount::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_NET_AMOUNT';
    END IF;

    IF v_preparation.token_fee_equivalent::numeric < 0 THEN
        RAISE EXCEPTION
            'INVALID_TOKEN_FEE';
    END IF;

    /*
     * ==========================================================
     * 9. RECORD BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'INSERT_BLOCKCHAIN_TRANSACTION';

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
            v_tx_hash,
            v_preparation.fiscal_year,
            v_preparation.period,
            'gold_token_sell'::public."TransactionType",
            v_blockchain_code,
            v_preparation.seller_wallet_address,
            v_preparation.treasury_wallet_address,
            v_preparation.token_quantity::numeric,
            v_preparation.gross_amount::numeric,
            v_preparation.net_amount::numeric,
            v_preparation.token_fee_equivalent::numeric,
            v_preparation.input_currency,
            v_explorer_url,
            'pending',
            p_seller_id,
            lower(btrim(p_country_code)),
            v_reference,
            'Gold token sell on ' || v_blockchain_code
        )
        RETURNING id::text
        INTO v_blockchain_id;

    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION USING
                ERRCODE = '23505',
                MESSAGE = 'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    END;

    /*
     * ==========================================================
     * 10. VALIDATE INSERT RESULT
     * ==========================================================
     */
    v_stage := 'VALIDATE_INSERT_RESULT';

    IF v_blockchain_id IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    END IF;

    RETURN v_blockchain_id;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'RECORD_GOLD_SELL_BLOCKCHAIN_TRANSACTION_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the blockchain transaction recording stage reported in the error'
            );
END;
$function$;