CREATE OR REPLACE FUNCTION public.fail_liquidation_blockchain_transfer(
    p_queue_id text,
    p_error_message text,
    p_tx_hash text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_error_message text;
    v_supplied_tx_hash text;
    v_tx_hash text;

    v_retryable boolean;
    v_manual_review boolean;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_queue_id := nullif(btrim(p_queue_id), '');

    v_error_message :=
        coalesce(
            nullif(btrim(p_error_message), ''),
            'LIQUIDATION_BLOCKCHAIN_PROCESSING_FAILED'
        );

    v_supplied_tx_hash :=
        nullif(btrim(p_tx_hash), '');

    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;

    IF v_supplied_tx_hash IS NOT NULL
       AND v_supplied_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF v_queue.tx_hash IS NOT NULL
       AND v_supplied_tx_hash IS NOT NULL
       AND lower(btrim(v_queue.tx_hash))
           IS DISTINCT FROM lower(v_supplied_tx_hash)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    END IF;

    /*
     * A late failure must not undo confirmation.
     */
    IF v_queue.status::text = 'confirmed' THEN
        RETURN jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'tx_hash', v_queue.tx_hash,
            'error_message', NULL,
            'retryable', false,
            'manual_review_required',
                v_queue.manual_review_required
        );
    END IF;

    v_tx_hash :=
        coalesce(v_queue.tx_hash, v_supplied_tx_hash);

    IF v_tx_hash IS NOT NULL THEN
        /*
         * Resume the known transaction.
         * Preserve any existing manual-review restriction.
         */
        v_manual_review := v_queue.manual_review_required;
        v_retryable := NOT v_manual_review;

        UPDATE public.liquidation_blockchain_queue
        SET
            status =
                'processing'::public."BlockchainLiquidationStatus",
            tx_hash = v_tx_hash,
            submitted_at = coalesce(submitted_at, now()),
            error_message = v_error_message,
            retry_count = retry_count + 1,
            lease_expires_at = now(),
            updated_at = now()
        WHERE id = v_queue.id;

        UPDATE public.liquidation_job
        SET
            status =
                'blockchain_processing'::public."LiquidationJobStatus",
            error_message = v_error_message
        WHERE id::text = v_queue.liquidation_job_id
          AND status::text IN (
              'pending',
              'failed',
              'blockchain_processing'
          );

    ELSE
        /*
         * A saved signature with no hash is ambiguous.
         *
         * Preserve the signature and its blockchain metadata.
         * Do not automatically create a replacement signature.
         *
         * With the current worker interface, SQL cannot prove
         * whether submission was attempted.
         */
        v_manual_review :=
            v_queue.manual_review_required
            OR v_queue.signed_payload IS NOT NULL;

        v_retryable := NOT v_manual_review;

        UPDATE public.liquidation_blockchain_queue
        SET
            status =
                'failed'::public."BlockchainLiquidationStatus",
            error_message = v_error_message,
            retry_count = retry_count + 1,
            manual_review_required = v_manual_review,
            claimed_at = NULL,
            lease_expires_at = NULL,
            updated_at = now()
        WHERE id = v_queue.id;

        UPDATE public.liquidation_job
        SET
            status =
                'failed'::public."LiquidationJobStatus",
            error_message = v_error_message
        WHERE id::text = v_queue.liquidation_job_id
          AND status::text IN (
              'pending',
              'failed',
              'blockchain_processing'
          );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'tx_hash', v_tx_hash,
        'error_message', v_error_message,
        'retryable', v_retryable,
        'manual_review_required', v_manual_review
    );
END;
$function$;


CREATE OR REPLACE FUNCTION public.claim_country_liquidation_accounting_jobs(
    p_country_code text,
    p_batch_size integer DEFAULT 25
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_country_code text;
    v_claimed integer := 0;
    v_jobs jsonb := '[]'::jsonb;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    v_stage := 'authorize service role';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_stage := 'validate input';

    v_country_code :=
        lower(nullif(btrim(p_country_code), ''));

    IF v_country_code IS NULL THEN
        RAISE EXCEPTION 'COUNTRY_CODE_REQUIRED';
    END IF;

    IF p_batch_size IS NULL
       OR p_batch_size < 1
       OR p_batch_size > 100
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_BATCH_SIZE';
    END IF;

    v_stage := 'lock country accounting claim';

    PERFORM pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-accounting-claim:%s',
                v_country_code
            )
        )
    );

    v_stage := 'claim confirmed liquidation jobs';

    WITH candidate_jobs AS MATERIALIZED (
        SELECT j.id
        FROM public.liquidation_job AS j
        WHERE lower(btrim(j.country_code)) = v_country_code
          AND nullif(btrim(j.blockchain_code), '') IS NOT NULL
          AND (
              j.status::text IN (
                  'blockchain_confirmed',
                  'accounting_failed'
              )
              OR (
                  j.status::text = 'accounting_processing'
                  AND (
                      j.accounting_started_at IS NULL
                      OR j.accounting_started_at <=
                         now() - interval '5 minutes'
                  )
              )
          )
          AND EXISTS (
              SELECT 1
              FROM public.liquidation_blockchain_queue AS q
              WHERE q.id::text = j.blockchain_queue_id
                AND q.liquidation_job_id = j.id::text
                AND q.user_id = j.user_id
                AND lower(btrim(q.country_code)) =
                    v_country_code
                AND q.blockchain_code = j.blockchain_code
                AND q.document_number = j.document_number
                AND q.status::text = 'confirmed'
                AND q.tx_hash ~ '^0x[0-9A-Fa-f]{64}$'
                AND q.confirmed_at IS NOT NULL
                AND q.manual_review_required = false
          )
        ORDER BY j.created_at, j.id
        LIMIT p_batch_size
        FOR UPDATE OF j SKIP LOCKED
    ),
    claimed_jobs AS (
        UPDATE public.liquidation_job AS j
        SET
            status =
                'accounting_processing'::public."LiquidationJobStatus",
            accounting_started_at = now(),
            accounting_retry_count =
                CASE
                    WHEN j.status::text IN (
                        'accounting_failed',
                        'accounting_processing'
                    )
                    THEN coalesce(j.accounting_retry_count, 0) + 1
                    ELSE coalesce(j.accounting_retry_count, 0)
                END,
            error_message = NULL
        FROM candidate_jobs AS candidate
        WHERE j.id = candidate.id
        RETURNING
            j.id,
            lower(btrim(j.country_code)) AS country_code
    )
    SELECT
        count(*)::integer,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'job_id', claimed.id,
                    'country_code', claimed.country_code
                )
                ORDER BY claimed.id
            ),
            '[]'::jsonb
        )
    INTO v_claimed, v_jobs
    FROM claimed_jobs AS claimed;

    RETURN jsonb_build_object(
        'success', true,
        'country_code', v_country_code,
        'claimed', v_claimed,
        'jobs', v_jobs
    );

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
                'LIQUIDATION_ACCOUNTING_CLAIM_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the liquidation accounting claim stage'
            );
END;
$function$;


CREATE OR REPLACE FUNCTION public.record_liquidation_blockchain_submission(
    p_queue_id text,
    p_tx_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_tx_hash text;
    v_job_status text;
    v_already_recorded boolean;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_tx_hash := nullif(btrim(p_tx_hash), '');

    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;

    IF v_tx_hash IS NULL
       OR v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    /*
     * Lock job before queue, matching accounting finalisation.
     * Queue/job linkage is checked again after both are locked.
     */
    SELECT j.status::text
    INTO v_job_status
    FROM public.liquidation_job AS j
    WHERE j.id::text = (
        SELECT q.liquidation_job_id
        FROM public.liquidation_blockchain_queue AS q
        WHERE q.id = v_queue_id
    )
    FOR UPDATE OF j;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_OR_QUEUE_NOT_FOUND';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF nullif(btrim(v_queue.blockchain_code), '') IS NULL
       OR v_queue.blockchain_code IS DISTINCT FROM
          lower(btrim(v_queue.blockchain_code))
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_BLOCKCHAIN_CODE';
    END IF;

    PERFORM 1
    FROM public.liquidation_job AS j
    WHERE j.id::text = v_queue.liquidation_job_id
      AND j.blockchain_queue_id = v_queue.id::text
      AND j.user_id = v_queue.user_id
      AND lower(btrim(j.country_code)) =
          lower(btrim(v_queue.country_code))
      AND j.blockchain_code = v_queue.blockchain_code
      AND j.document_number = v_queue.document_number;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_QUEUE_MISMATCH';
    END IF;

    IF v_queue.tx_hash IS NOT NULL
       AND lower(btrim(v_queue.tx_hash))
           IS DISTINCT FROM lower(v_tx_hash)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    END IF;

    v_already_recorded := v_queue.tx_hash IS NOT NULL;

    /*
     * A delayed callback must not downgrade confirmation
     * or completed accounting.
     */
    IF v_queue.status::text = 'confirmed' THEN
        IF v_queue.tx_hash IS NULL THEN
            RAISE EXCEPTION
                'CONFIRMED_LIQUIDATION_TX_HASH_REQUIRED';
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'tx_hash', v_queue.tx_hash,
            'submitted_at', v_queue.submitted_at,
            'already_recorded', true,
            'manual_review_required',
                v_queue.manual_review_required
        );
    END IF;

    /*
     * Accept late submission callbacks after a failure
     * or expired lease. Recording the known hash prevents
     * the transfer from being treated as unsubmitted.
     *
     * This does not authorize another blockchain submission.
     */
    IF v_queue.status::text NOT IN (
        'pending',
        'processing',
        'failed'
    ) THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SUBMISSION_QUEUE_STATE';
    END IF;

    IF v_job_status NOT IN (
        'pending',
        'blockchain_processing',
        'failed'
    ) THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SUBMISSION_JOB_STATE';
    END IF;

    IF v_queue.signed_payload IS NULL
       OR jsonb_typeof(v_queue.signed_payload)
          IS DISTINCT FROM 'object'
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_SIGNED_PAYLOAD_NOT_FOUND';
    END IF;

    IF (v_queue.signed_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_queue.blockchain_code
       OR coalesce(
           v_queue.signed_payload ->> 'chain_id',
           ''
       ) !~ '^[0-9]+$'
       OR coalesce(
           v_queue.signed_payload ->> 'contract_address',
           ''
       ) !~ '^0x[0-9A-Fa-f]{40}$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SAVED_BLOCKCHAIN_METADATA';
    END IF;

    IF (v_queue.signed_payload ->> 'chain_id')::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SAVED_CHAIN_ID';
    END IF;

    IF lower(v_queue.signed_payload ->> 'owner')
       IS DISTINCT FROM lower(v_queue.sender_wallet_address)
       OR lower(v_queue.signed_payload ->> 'to')
          IS DISTINCT FROM lower(v_queue.receiver_wallet_address)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_ADDRESS_MISMATCH';
    END IF;

    PERFORM 1
    FROM public.liquidation_blockchain_queue AS other_queue
    WHERE lower(btrim(other_queue.tx_hash)) = lower(v_tx_hash)
      AND other_queue.id <> v_queue.id;

    IF FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_ALREADY_ASSIGNED';
    END IF;

    UPDATE public.liquidation_blockchain_queue
    SET
        status =
            'processing'::public."BlockchainLiquidationStatus",
        tx_hash = coalesce(tx_hash, v_tx_hash),
        submitted_at = coalesce(submitted_at, now()),

        /*
         * Preserve existing manual-review flags and reasons.
         */
        error_message =
            CASE
                WHEN manual_review_required THEN error_message
                ELSE NULL
            END,

        /*
         * A first submission gets time to await its receipt.
         * Repeated callbacks do not extend another worker's lease.
         */
        lease_expires_at =
            CASE
                WHEN v_already_recorded THEN lease_expires_at
                ELSE now() + interval '5 minutes'
            END,
        updated_at = now()
    WHERE id = v_queue.id
    RETURNING * INTO v_queue;

    UPDATE public.liquidation_job
    SET
        status =
            'blockchain_processing'::public."LiquidationJobStatus",
        error_message =
            CASE
                WHEN v_queue.manual_review_required
                THEN error_message
                ELSE NULL
            END
    WHERE id::text = v_queue.liquidation_job_id
      AND blockchain_queue_id = v_queue.id::text
      AND blockchain_code = v_queue.blockchain_code
      AND status::text IN (
          'pending',
          'blockchain_processing',
          'failed'
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SUBMISSION_JOB_STATE';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'tx_hash', v_queue.tx_hash,
        'submitted_at', v_queue.submitted_at,
        'already_recorded', v_already_recorded,
        'manual_review_required',
            v_queue.manual_review_required
    );
END;
$function$;