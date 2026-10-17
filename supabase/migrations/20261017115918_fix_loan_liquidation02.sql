-- Diagnostic-only replacement from the supplied current SQL.
-- Preserves signature, permissions, validation rules and generic error code.
-- Adds non-secret expected/received identity fields to error DETAIL.
-- Does not reset a queue, relax validation or submit a transaction.
BEGIN;

CREATE OR REPLACE FUNCTION public.save_liquidation_blockchain_signed_payload(p_queue_id text, p_signed_payload jsonb)
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
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH',
            DETAIL = jsonb_build_object(
                'stage', 'payload_blockchain_code',
                'queue_id', v_queue.id,
                'already_signed', v_already_signed,
                'expected_blockchain_code', v_queue.blockchain_code,
                'received_blockchain_code', v_payload ->> 'blockchain_code',
                'received_chain_id', v_payload ->> 'chain_id',
                'received_contract_address', v_payload ->> 'contract_address'
            )::text;
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
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH',
            DETAIL = jsonb_build_object(
                'stage', 'resolved_blockchain_config',
                'queue_id', v_queue.id,
                'already_signed', v_already_signed,
                'expected_blockchain_code', v_config.code,
                'queue_blockchain_code', v_queue.blockchain_code,
                'received_blockchain_code', v_payload ->> 'blockchain_code',
                'expected_chain_id', v_config.chain_id::text,
                'received_chain_id', v_payload ->> 'chain_id',
                'expected_contract_address', v_config.contract_address,
                'received_contract_address', v_contract_address,
                'code_mismatch', v_config.code IS DISTINCT FROM v_queue.blockchain_code,
                'chain_id_mismatch', v_config.chain_id::numeric IS DISTINCT FROM v_chain_id,
                'contract_mismatch', lower(v_config.contract_address)
                    IS DISTINCT FROM lower(v_contract_address)
            )::text;
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

COMMIT;
