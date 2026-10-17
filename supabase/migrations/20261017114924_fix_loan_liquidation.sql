-- Supersedes liquidation_automatic_retry.sql. Five-attempt hard stop retained.
-- Full replacements: claim_country_liquidation_blockchain_jobs and
-- fail_liquidation_blockchain_transfer. No worker/Edge changes required.
-- Adds one SERVICE-ONLY reviewed requeue action, with a required resolution
-- note. This is a backend operation, not an operator UI or notification.
-- Known hashes are never resubmitted; after five failed recovery attempts
-- they also require review. Uncertain submission always requires review.
-- Actual error text is retained with the exhaustion prefix. Errors already
-- overwritten by the old MAX_ATTEMPTS logic cannot be recovered by this SQL.
-- Applying this file FLAGS stuck rows; it does not reset or submit them.
BEGIN;

CREATE OR REPLACE FUNCTION public.claim_country_liquidation_blockchain_jobs(p_country_code text, p_batch_size integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_country_code text;
    v_queue public.liquidation_blockchain_queue%rowtype;

    v_claimed integer := 0;
    v_jobs jsonb := '[]'::jsonb;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

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

    PERFORM pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-blockchain-claim:%s',
                v_country_code
            )
        )
    );

    /*
     * Submission started but no hash was recorded.
     * Do not authorize another submission after lease expiry.
     *
     * Preserve the signature and submission marker.
     */
    UPDATE public.liquidation_blockchain_queue AS q
    SET
        manual_review_required = true,
        error_message =
            'LIQUIDATION_SUBMISSION_OUTCOME_UNKNOWN',
        updated_at = now()
    WHERE lower(btrim(q.country_code)) = v_country_code
      AND q.submission_started_at IS NOT NULL
      AND q.tx_hash IS NULL
      AND q.manual_review_required = false
      AND q.status::text IN (
          'pending',
          'processing',
          'failed'
      )
      AND (
          q.lease_expires_at IS NULL
          OR q.lease_expires_at <= clock_timestamp()
      );

    /* Five attempts is a hard stop, including receipt-recovery attempts.
     * Do not interrupt a live fifth attempt: its worker may still succeed.
     * If its lease expires, make the failure visible for operator review.
     * Preserve actual error text rather than replacing it with only MAX.
     */
    UPDATE public.liquidation_blockchain_queue AS q
    SET status = 'failed'::public."BlockchainLiquidationStatus",
        manual_review_required = true,
        error_message = CASE
            WHEN nullif(btrim(q.error_message), '') IS NULL
                THEN 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
            WHEN q.error_message LIKE 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED%'
                THEN q.error_message
            ELSE 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED: ' || q.error_message
        END,
        lease_expires_at = NULL,
        updated_at = now()
    WHERE lower(btrim(q.country_code)) = v_country_code
      AND q.attempt_count >= 5
      AND q.manual_review_required = false
      AND q.status::text IN ('pending', 'processing', 'failed')
      AND (q.status::text <> 'processing'
           OR q.lease_expires_at IS NULL
           OR q.lease_expires_at <= clock_timestamp());

    UPDATE public.liquidation_job AS j
    SET status = 'failed'::public."LiquidationJobStatus",
        error_message = q.error_message
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.liquidation_job_id = j.id::text
      AND j.blockchain_queue_id = q.id::text
      AND lower(btrim(j.country_code)) = v_country_code
      AND q.manual_review_required = true
      AND q.attempt_count >= 5
      AND q.status::text = 'failed'
      AND j.status::text IN ('pending', 'failed', 'blockchain_processing');

    /* Jobs with submission evidence are never recreated. A known hash
     * resumes receipt checking while attempts remain. No-hash recovery
     * requires that the submission marker has never been set. */
    FOR v_queue IN
        SELECT q.*
        FROM public.liquidation_blockchain_queue AS q
        WHERE lower(btrim(q.country_code)) = v_country_code
          AND q.manual_review_required = false
          AND (
              q.tx_hash IS NOT NULL
              OR q.submission_started_at IS NULL
          )
          AND q.attempt_count < 5
          AND (
              q.status::text IN ('pending', 'failed')
              OR (
                  q.status::text = 'processing'
                  AND (
                      q.lease_expires_at IS NULL
                      OR q.lease_expires_at <= clock_timestamp()
                  )
              )
          )
        ORDER BY q.created_at, q.id
        LIMIT p_batch_size
        FOR UPDATE OF q SKIP LOCKED
    LOOP
        IF nullif(btrim(v_queue.blockchain_code), '') IS NULL
           OR v_queue.blockchain_code IS DISTINCT FROM
              lower(btrim(v_queue.blockchain_code))
        THEN
            UPDATE public.liquidation_blockchain_queue
            SET
                manual_review_required = true,
                error_message =
                    'LIQUIDATION_BLOCKCHAIN_CODE_REQUIRED_OR_INVALID',
                updated_at = now()
            WHERE id = v_queue.id;

            CONTINUE;
        END IF;

        /*
         * Require the queue and original calculation to agree.
         * Never substitute a different chain during recovery.
         */
        PERFORM 1
        FROM public.liquidation_job AS j
        WHERE j.id::text = v_queue.liquidation_job_id
          AND j.user_id = v_queue.user_id
          AND lower(btrim(j.country_code)) = v_country_code
          AND j.blockchain_code = v_queue.blockchain_code
          AND j.blockchain_queue_id = v_queue.id::text
          AND j.document_number = v_queue.document_number
          AND j.status::text IN (
              'pending',
              'failed',
              'blockchain_processing'
          );

        IF NOT FOUND THEN
            UPDATE public.liquidation_blockchain_queue
            SET
                manual_review_required = true,
                error_message =
                    'LIQUIDATION_JOB_QUEUE_MISMATCH_OR_INVALID_STATE',
                updated_at = now()
            WHERE id = v_queue.id;

            CONTINUE;
        END IF;

        UPDATE public.liquidation_blockchain_queue
        SET
            status =
                'processing'::public."BlockchainLiquidationStatus",
            claimed_at = clock_timestamp(),
            lease_expires_at =
                clock_timestamp() + interval '5 minutes',
            attempt_count = attempt_count + 1,
            last_attempt_at = clock_timestamp(),
            updated_at = now()
        WHERE id = v_queue.id
        RETURNING * INTO v_queue;

        UPDATE public.liquidation_job
        SET
            status =
                'blockchain_processing'::public."LiquidationJobStatus"
        WHERE id::text = v_queue.liquidation_job_id
          AND blockchain_queue_id = v_queue.id::text
          AND blockchain_code = v_queue.blockchain_code
          AND status::text IN (
              'pending',
              'failed',
              'blockchain_processing'
          );

        IF NOT FOUND THEN
            UPDATE public.liquidation_blockchain_queue
            SET
                manual_review_required = true,
                error_message =
                    'LIQUIDATION_JOB_STATE_CHANGED',
                lease_expires_at = NULL,
                updated_at = now()
            WHERE id = v_queue.id;

            CONTINUE;
        END IF;

        v_jobs := v_jobs || jsonb_build_array(
            jsonb_build_object(
                'queue_id', v_queue.id::text,
                'liquidation_job_id', v_queue.liquidation_job_id,
                'user_id', v_queue.user_id,
                'wallet_index', v_queue.wallet_index,
                'treasury_id', v_queue.treasury_id,
                'sender_wallet_address',
                    v_queue.sender_wallet_address,
                'collateral',
                    trim_scale(v_queue.collateral)::text,
                'debt_repayment_amount',
                    trim_scale(v_queue.debt_repayment_amount)::text,
                'penalty_amount',
                    trim_scale(v_queue.penalty_amount)::text,
                'total_liquidation_proceeds',
                    trim_scale(v_queue.total_liquidation_proceeds)::text,
                'total_debt',
                    trim_scale(v_queue.total_debt)::text,
                'gold_price',
                    trim_scale(v_queue.gold_price)::text,
                'document_number', v_queue.document_number,
                'fiscal_year', v_queue.fiscal_year,
                'period', v_queue.period,
                'country_code',
                    lower(btrim(v_queue.country_code)),
                'blockchain_code', v_queue.blockchain_code,
                'retry_count', v_queue.retry_count,
                'attempt_count', v_queue.attempt_count,
                'manual_review_required',
                    v_queue.manual_review_required,
                'queue_status', v_queue.status::text,
                'tx_hash', v_queue.tx_hash,
                'claimed_at', v_queue.claimed_at,
                'lease_expires_at', v_queue.lease_expires_at,
                'signed_payload', v_queue.signed_payload
            )
        );

        v_claimed := v_claimed + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'country_code', v_country_code,
        'claimed', v_claimed,
        'jobs', v_jobs
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fail_liquidation_blockchain_transfer(p_queue_id text, p_error_message text, p_tx_hash text DEFAULT NULL::text)
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

    -- Escalate immediately when the fifth attempt fails, not only when
    -- the next cron run notices an exhausted row.
    IF v_queue.attempt_count >= 5 THEN
        IF v_error_message NOT LIKE 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED%' THEN
            v_error_message := 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED: ' ||
                               v_error_message;
        END IF;
    END IF;

    IF v_tx_hash IS NOT NULL THEN
        /*
         * Resume the known transaction.
         * Preserve any existing manual-review restriction.
         */
        v_manual_review := v_queue.manual_review_required
                           OR v_queue.attempt_count >= 5;
        v_retryable := NOT v_manual_review;

        UPDATE public.liquidation_blockchain_queue
        SET
            status =
                CASE WHEN v_manual_review
                    THEN 'failed'::public."BlockchainLiquidationStatus"
                    ELSE 'processing'::public."BlockchainLiquidationStatus"
                END,
            manual_review_required = v_manual_review,
            tx_hash = v_tx_hash,
            submitted_at = coalesce(submitted_at, now()),
            error_message = v_error_message,
            retry_count = retry_count + 1,
            lease_expires_at = CASE WHEN v_manual_review THEN NULL ELSE now() END,
            updated_at = now()
        WHERE id = v_queue.id;

        UPDATE public.liquidation_job
        SET
            status =
                CASE WHEN v_manual_review
                    THEN 'failed'::public."LiquidationJobStatus"
                    ELSE 'blockchain_processing'::public."LiquidationJobStatus"
                END,
            error_message = v_error_message
        WHERE id::text = v_queue.liquidation_job_id
          AND status::text IN (
              'pending',
              'failed',
              'blockchain_processing'
          );

    ELSE
        /* Never reopen an uncertain submission automatically.
         * A signed no-hash failure is conservatively escalated too. */
        v_manual_review := v_queue.manual_review_required
                           OR v_queue.attempt_count >= 5
                           OR v_queue.submission_started_at IS NOT NULL
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

CREATE OR REPLACE FUNCTION public.requeue_reviewed_liquidation_blockchain_job(
    p_queue_id text,
    p_resolution_note text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_queue_id text;
    v_note text;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;
    v_queue_id := nullif(btrim(p_queue_id), '');
    v_note := nullif(btrim(p_resolution_note), '');
    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;
    IF v_note IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_REVIEW_RESOLUTION_REQUIRED';
    END IF;

    -- Same lock order as claim/failure/confirmation: queue, then job.
    SELECT q.* INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;
    IF NOT v_queue.manual_review_required OR v_queue.status::text <> 'failed' THEN
        RAISE EXCEPTION 'LIQUIDATION_FAILED_MANUAL_REVIEW_REQUIRED';
    END IF;
    IF v_queue.tx_hash IS NOT NULL
       OR v_queue.signed_payload IS NOT NULL
       OR v_queue.signed_at IS NOT NULL
       OR v_queue.submission_started_at IS NOT NULL
       OR v_queue.submitted_at IS NOT NULL
       OR v_queue.confirmed_at IS NOT NULL
    THEN
        RAISE EXCEPTION 'LIQUIDATION_RECONCILIATION_REQUIRED_BEFORE_REQUEUE';
    END IF;

    PERFORM 1 FROM public.liquidation_job AS j
    WHERE j.id::text = v_queue.liquidation_job_id
      AND j.blockchain_queue_id = v_queue.id::text
      AND j.user_id = v_queue.user_id
      AND lower(btrim(j.country_code)) = lower(btrim(v_queue.country_code))
      AND j.blockchain_code = v_queue.blockchain_code
      AND j.document_number = v_queue.document_number
      AND j.status::text IN ('failed', 'pending', 'blockchain_processing')
    FOR UPDATE OF j;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_JOB_QUEUE_MISMATCH_OR_INVALID_STATE';
    END IF;

    -- Reject unresolved structural blockchain configuration problems.
    -- This is not proof that every operational issue has been corrected.
    PERFORM 1 FROM public.fetch_liquidation_blockchain_config(v_queue.id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CONFIG_NOT_FOUND';
    END IF;

    UPDATE public.liquidation_blockchain_queue
    SET status = 'pending'::public."BlockchainLiquidationStatus",
        manual_review_required = false,
        attempt_count = 0,
        -- retry_count remains the lifetime failure count.
        reason = concat_ws(E'\n', nullif(reason, ''),
            format('REVIEWED %s; previous attempts=%s; previous error=%s; resolution=%s',
                clock_timestamp(), v_queue.attempt_count,
                coalesce(v_queue.error_message, '(none)'), v_note)),
        error_message = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        last_attempt_at = NULL,
        processing_started_at = NULL,
        updated_at = now()
    WHERE id = v_queue.id;

    UPDATE public.liquidation_job
    SET status = 'pending'::public."LiquidationJobStatus", error_message = NULL
    WHERE id::text = v_queue.liquidation_job_id;

    RETURN jsonb_build_object(
        'success', true, 'queue_id', v_queue.id,
        'liquidation_job_id', v_queue.liquidation_job_id,
        'status', 'pending', 'attempt_count', 0,
        'manual_review_required', false
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.requeue_reviewed_liquidation_blockchain_job(text, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.requeue_reviewed_liquidation_blockchain_job(text, text)
TO service_role;

-- Flag already-exhausted rows now, including the reported stuck job.
-- Do not interrupt a worker whose current processing lease is still live.
WITH escalated AS (
    UPDATE public.liquidation_blockchain_queue AS q
    SET status = 'failed'::public."BlockchainLiquidationStatus",
        manual_review_required = true,
        lease_expires_at = NULL,
        error_message = CASE
            WHEN nullif(btrim(q.error_message), '') IS NULL
                THEN 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
            WHEN q.error_message LIKE 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED%'
                THEN q.error_message
            ELSE 'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED: ' || q.error_message
        END,
        updated_at = now()
    WHERE q.attempt_count >= 5 AND q.manual_review_required = false
      AND q.status::text IN ('pending', 'failed', 'processing')
      AND (q.status::text <> 'processing' OR q.lease_expires_at IS NULL
           OR q.lease_expires_at <= clock_timestamp())
    RETURNING q.id, q.liquidation_job_id, q.error_message
)
UPDATE public.liquidation_job AS j
SET status = 'failed'::public."LiquidationJobStatus", error_message = e.error_message
FROM escalated AS e
WHERE j.id::text = e.liquidation_job_id
  AND j.blockchain_queue_id = e.id::text
  AND j.status::text IN ('pending', 'failed', 'blockchain_processing');

COMMIT;
