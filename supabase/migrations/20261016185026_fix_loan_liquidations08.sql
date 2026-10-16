CREATE OR REPLACE FUNCTION public.claim_country_liquidation_blockchain_jobs(
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

    /*
     * Stop exhausted attempts only when submission has
     * not started and no manual-review restriction exists.
     */
    UPDATE public.liquidation_blockchain_queue AS q
    SET
        status =
            'failed'::public."BlockchainLiquidationStatus",
        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED',
        lease_expires_at = NULL,
        updated_at = now()
    WHERE lower(btrim(q.country_code)) = v_country_code
      AND q.tx_hash IS NULL
      AND q.submission_started_at IS NULL
      AND q.manual_review_required = false
      AND q.attempt_count >= 5
      AND q.status::text IN (
          'pending',
          'processing',
          'failed'
      )
      AND (
          q.status::text <> 'processing'
          OR q.lease_expires_at IS NULL
          OR q.lease_expires_at <= clock_timestamp()
      );

    UPDATE public.liquidation_job AS j
    SET
        status = 'failed'::public."LiquidationJobStatus",
        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
    WHERE lower(btrim(j.country_code)) = v_country_code
      AND j.status::text IN (
          'pending',
          'failed',
          'blockchain_processing'
      )
      AND EXISTS (
          SELECT 1
          FROM public.liquidation_blockchain_queue AS q
          WHERE q.liquidation_job_id = j.id::text
            AND q.tx_hash IS NULL
            AND q.submission_started_at IS NULL
            AND q.manual_review_required = false
            AND q.attempt_count >= 5
            AND q.status::text = 'failed'
            AND q.error_message =
                'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
      );

    /*
     * Known hashes remain recoverable regardless of
     * attempt count.
     *
     * Without a hash, only jobs whose submission has
     * never started may be claimed automatically.
     */
    FOR v_queue IN
        SELECT q.*
        FROM public.liquidation_blockchain_queue AS q
        WHERE lower(btrim(q.country_code)) = v_country_code
          AND q.manual_review_required = false
          AND (
              q.tx_hash IS NOT NULL
              OR q.submission_started_at IS NULL
          )
          AND (
              q.tx_hash IS NOT NULL
              OR q.attempt_count < 5
          )
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
            error_message = NULL,
            updated_at = now()
        WHERE id = v_queue.id
        RETURNING * INTO v_queue;

        UPDATE public.liquidation_job
        SET
            status =
                'blockchain_processing'::public."LiquidationJobStatus",
            error_message = NULL
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