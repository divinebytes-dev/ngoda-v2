CREATE OR REPLACE FUNCTION public.save_liquidation_blockchain_signed_payload(
    p_queue_id text,
    p_signed_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_config record;

    v_queue_id text;
    v_payload jsonb;
    v_already_signed boolean;

    v_owner text;
    v_receiver text;
    v_contract_address text;
    v_chain_id numeric;
    v_amount numeric;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_queue_id := nullif(btrim(p_queue_id), '');

    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;

    IF p_signed_payload IS NULL
       OR jsonb_typeof(p_signed_payload) IS DISTINCT FROM 'object'
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_SIGNED_PAYLOAD';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF v_queue.manual_review_required THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED';
    END IF;

    IF v_queue.tx_hash IS NOT NULL THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_ALREADY_SUBMITTED';
    END IF;

    IF v_queue.status::text <> 'processing' THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    END IF;

    IF nullif(btrim(v_queue.blockchain_code), '') IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    PERFORM 1
    FROM public.liquidation_job AS j
    WHERE j.id::text = v_queue.liquidation_job_id
      AND j.user_id = v_queue.user_id
      AND lower(btrim(j.country_code)) =
          lower(btrim(v_queue.country_code))
      AND j.blockchain_code = v_queue.blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_BLOCKCHAIN_MISMATCH_OR_NOT_FOUND';
    END IF;

    /*
     * A previously stored signature wins.
     * Never overwrite it with a competing signature.
     */
    v_already_signed := v_queue.signed_payload IS NOT NULL;

    v_payload :=
        CASE
            WHEN v_already_signed THEN v_queue.signed_payload
            ELSE p_signed_payload
        END;

    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_SIGNED_PAYLOAD';
    END IF;

    IF (v_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_queue.blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * Validate unsigned integer fields before casting.
     */
    IF coalesce(v_payload ->> 'chain_id', '') !~ '^[0-9]+$'
       OR coalesce(v_payload ->> 'parsedAmount', '') !~ '^[0-9]+$'
       OR coalesce(v_payload ->> 'nonce', '') !~ '^[0-9]+$'
       OR coalesce(v_payload ->> 'deadline', '') !~ '^[0-9]+$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD_NUMERIC_FIELDS';
    END IF;

    IF (v_payload ->> 'chain_id')::numeric <= 0
       OR (v_payload ->> 'parsedAmount')::numeric <= 0
       OR (v_payload ->> 'deadline')::numeric <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD_NUMERIC_FIELDS';
    END IF;

    /*
     * Liquidation transfers have no additional GOLD fee.
     */
    IF coalesce(v_payload ->> 'parsedFee', '') !~ '^[0-9]+$'
       OR coalesce(v_payload ->> 'fee', '') !~ '^[0-9]+([.][0-9]+)?$'
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_TRANSFER_FEE';
    END IF;

    IF (v_payload ->> 'parsedFee')::numeric <> 0
       OR (v_payload ->> 'fee')::numeric <> 0
    THEN
        RAISE EXCEPTION 'LIQUIDATION_TRANSFER_FEE_NOT_ALLOWED';
    END IF;

    IF coalesce(v_payload ->> 'amount', '')
       !~ '^[0-9]+([.][0-9]+)?$'
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_COLLATERAL_AMOUNT';
    END IF;

    v_amount := (v_payload ->> 'amount')::numeric;

    IF v_amount <= 0
       OR v_amount IS DISTINCT FROM v_queue.collateral
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_COLLATERAL_AMOUNT_MISMATCH';
    END IF;

    IF coalesce(v_payload ->> 'v', '') NOT IN ('27', '28')
       OR coalesce(v_payload ->> 'r', '') !~ '^0x[0-9A-Fa-f]{64}$'
       OR coalesce(v_payload ->> 's', '') !~ '^0x[0-9A-Fa-f]{64}$'
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_SIGNATURE_FIELDS';
    END IF;

    v_owner := v_payload ->> 'owner';
    v_receiver := v_payload ->> 'to';
    v_contract_address := v_payload ->> 'contract_address';
    v_chain_id := (v_payload ->> 'chain_id')::numeric;

    IF v_owner IS NULL
       OR v_owner !~ '^0x[0-9A-Fa-f]{40}$'
       OR v_receiver IS NULL
       OR v_receiver !~ '^0x[0-9A-Fa-f]{40}$'
       OR v_contract_address IS NULL
       OR v_contract_address !~ '^0x[0-9A-Fa-f]{40}$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD_ADDRESS';
    END IF;

    IF lower(v_owner)
       IS DISTINCT FROM lower(v_queue.sender_wallet_address)
    THEN
        RAISE EXCEPTION 'LIQUIDATION_OWNER_ADDRESS_MISMATCH';
    END IF;

    /*
     * For a new signature this resolves current configuration.
     * For a saved signature it resolves the pinned network.
     */
    SELECT c.*
    INTO v_config
    FROM public.fetch_liquidation_blockchain_config(
        v_queue.id
    ) AS c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CONFIG_NOT_FOUND';
    END IF;

    IF v_config.code IS DISTINCT FROM v_queue.blockchain_code
       OR v_config.chain_id::numeric IS DISTINCT FROM v_chain_id
       OR lower(v_config.contract_address)
          IS DISTINCT FROM lower(v_contract_address)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    IF lower(v_receiver)
       IS DISTINCT FROM lower(v_config.treasury_wallet_address)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_TREASURY_ADDRESS_MISMATCH';
    END IF;

    IF v_queue.receiver_wallet_address IS NOT NULL
       AND lower(btrim(v_queue.receiver_wallet_address))
           IS DISTINCT FROM lower(v_receiver)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_RECEIVER_ADDRESS_MISMATCH';
    END IF;

    /*
     * Preserve the entire payload, including:
     * blockchain_code, chain_id and contract_address.
     */
    UPDATE public.liquidation_blockchain_queue
    SET
        signed_payload = v_payload,
        signed_at = coalesce(signed_at, now()),
        receiver_wallet_address = v_receiver,
        error_message = NULL,
        updated_at = now()
    WHERE id = v_queue.id
    RETURNING * INTO v_queue;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'already_signed', v_already_signed,
        'signed_payload', v_queue.signed_payload
    );
END;
$function$;


CREATE OR REPLACE FUNCTION public.confirm_liquidation_blockchain_transfer(
    p_queue_id text,
    p_tx_hash text,
    p_explorer_url text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_existing_tx public.blockchain_transaction%rowtype;

    v_queue_id text;
    v_tx_hash text;
    v_receiver text;
    v_explorer_url text;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_tx_hash := nullif(btrim(p_tx_hash), '');
    v_explorer_url := nullif(btrim(p_explorer_url), '');

    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;

    IF v_tx_hash IS NULL
       OR v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF nullif(btrim(v_queue.blockchain_code), '') IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    IF (v_queue.signed_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_queue.blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    PERFORM 1
    FROM public.liquidation_job AS j
    WHERE j.id::text = v_queue.liquidation_job_id
      AND j.user_id = v_queue.user_id
      AND lower(btrim(j.country_code)) =
          lower(btrim(v_queue.country_code))
      AND j.blockchain_code = v_queue.blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_BLOCKCHAIN_MISMATCH_OR_NOT_FOUND';
    END IF;

    IF v_queue.tx_hash IS NOT NULL
       AND lower(btrim(v_queue.tx_hash)) <> lower(v_tx_hash)
    THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    END IF;

    /*
     * Preserve idempotency without moving an already
     * completed accounting job back to blockchain_confirmed.
     */
    IF v_queue.status::text = 'confirmed' THEN
        IF v_queue.tx_hash IS NULL THEN
            RAISE EXCEPTION
                'CONFIRMED_LIQUIDATION_TX_HASH_REQUIRED';
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'liquidation_job_id', v_queue.liquidation_job_id,
            'status', v_queue.status,
            'tx_hash', v_queue.tx_hash,
            'confirmed_at', v_queue.confirmed_at
        );
    END IF;

    /*
     * PostgreSQL records the receipt result supplied by
     * the service worker; it does not fetch the receipt itself.
     */
    PERFORM 1
    FROM public.liquidation_blockchain_queue AS other_queue
    WHERE lower(btrim(other_queue.tx_hash)) = lower(v_tx_hash)
      AND other_queue.id <> v_queue.id;

    IF FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_ALREADY_ASSIGNED';
    END IF;

    v_receiver :=
        nullif(btrim(v_queue.signed_payload ->> 'to'), '');

    IF v_receiver IS NULL
       OR v_receiver !~ '^0x[0-9A-Fa-f]{40}$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_BLOCKCHAIN_RECEIVER';
    END IF;

    IF lower(v_receiver)
       IS DISTINCT FROM lower(v_queue.receiver_wallet_address)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_RECEIVER_ADDRESS_MISMATCH';
    END IF;

    /*
     * Check an existing audit row instead of silently
     * accepting a hash belonging to a different operation.
     */
    SELECT bt.*
    INTO v_existing_tx
    FROM public.blockchain_transaction AS bt
    WHERE lower(btrim(bt.tx_hash)) = lower(v_tx_hash);

    IF FOUND THEN
        IF v_existing_tx.transaction_type IS DISTINCT FROM
           'loan_liquidation'::public."TransactionType"
           OR v_existing_tx.chain IS DISTINCT FROM
              v_queue.blockchain_code
           OR v_existing_tx.reference IS DISTINCT FROM
              v_queue.document_number
           OR v_existing_tx.document_number IS DISTINCT FROM
              v_queue.document_number
           OR lower(v_existing_tx.sender) IS DISTINCT FROM
              lower(v_queue.sender_wallet_address)
           OR lower(v_existing_tx.receiver) IS DISTINCT FROM
              lower(v_receiver)
           OR v_existing_tx.quantity IS DISTINCT FROM
              v_queue.collateral
        THEN
            RAISE EXCEPTION
                'LIQUIDATION_BLOCKCHAIN_AUDIT_MISMATCH';
        END IF;
    ELSE
        INSERT INTO public.blockchain_transaction (
            document_number,
            fiscal_year,
            country_code,
            period,
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
            chain_status,
            status,
            description,
            explorer_url,
            created_by
        )
        VALUES (
            v_queue.document_number,
            v_queue.fiscal_year,
            lower(btrim(v_queue.country_code)),
            v_queue.period,
            v_tx_hash,
            v_queue.document_number,
            'loan_liquidation'::public."TransactionType",

            -- Selected blockchain code, replacing 'chiado'.
            v_queue.blockchain_code,

            v_queue.sender_wallet_address,
            v_receiver,
            v_queue.collateral,
            v_queue.total_debt,
            v_queue.debt_repayment_amount,
            v_queue.penalty_amount,
            'gold',
            'completed',
            'completed'::public."BlockchainTxStatus",
            format(
                'Loan liquidation blockchain transfer for user %s',
                v_queue.user_id
            ),
            v_explorer_url,
            'system'
        );
    END IF;

    UPDATE public.liquidation_blockchain_queue
    SET
        status =
            'confirmed'::public."BlockchainLiquidationStatus",
        tx_hash = v_tx_hash,
        receiver_wallet_address = v_receiver,
        explorer_url = v_explorer_url,
        submitted_at = coalesce(submitted_at, now()),
        confirmed_at = coalesce(confirmed_at, now()),
        manual_review_required = false,
        error_message = NULL,
        lease_expires_at = NULL,
        updated_at = now()
    WHERE id = v_queue.id
    RETURNING * INTO v_queue;

    UPDATE public.liquidation_job
    SET
        status =
            'blockchain_confirmed'::public."LiquidationJobStatus",
        error_message = NULL
    WHERE id::text = v_queue.liquidation_job_id
      AND blockchain_code = v_queue.blockchain_code
      AND status::text IN (
          'pending',
          'blockchain_processing',
          'failed',
          'blockchain_confirmed'
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_JOB_STATE';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'liquidation_job_id', v_queue.liquidation_job_id,
        'status', v_queue.status,
        'tx_hash', v_queue.tx_hash,
        'confirmed_at', v_queue.confirmed_at
    );
END;
$function$;