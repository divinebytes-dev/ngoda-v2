ALTER TABLE public.liquidation_blockchain_queue
ADD COLUMN IF NOT EXISTS submission_started_at timestamptz;


CREATE OR REPLACE FUNCTION public.begin_liquidation_blockchain_submission(
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
    v_queue_id text;
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
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF v_queue.manual_review_required THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED';
    END IF;

    IF v_queue.tx_hash IS NOT NULL THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_ALREADY_SUBMITTED';
    END IF;

    /*
     * Never automatically reopen submission after this
     * marker has been set, even if the lease expires.
     */
    IF v_queue.submission_started_at IS NOT NULL THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_SUBMISSION_ALREADY_STARTED';
    END IF;

    IF v_queue.status::text <> 'processing' THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    END IF;

    IF v_queue.lease_expires_at IS NULL
       OR v_queue.lease_expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_LEASE_EXPIRED';
    END IF;

    /*
     * The worker must submit exactly the payload saved
     * in PostgreSQL, including its blockchain metadata.
     */
    IF v_queue.signed_payload IS NULL
       OR v_queue.signed_payload IS DISTINCT FROM p_signed_payload
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_PAYLOAD_MISMATCH';
    END IF;

    IF (v_queue.signed_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_queue.blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * Refuse an expired or nearly expired permit.
     */
    IF coalesce(
        v_queue.signed_payload ->> 'deadline',
        ''
    ) !~ '^[0-9]+$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_SIGNATURE_DEADLINE';
    END IF;

    IF (v_queue.signed_payload ->> 'deadline')::numeric <=
       extract(epoch FROM clock_timestamp()) + 30
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNATURE_EXPIRED_OR_EXPIRING';
    END IF;

    UPDATE public.liquidation_blockchain_queue
    SET
        submission_started_at = clock_timestamp(),
        updated_at = now()
    WHERE id = v_queue.id
    RETURNING * INTO v_queue;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'blockchain_code', v_queue.blockchain_code,
        'submission_started_at', v_queue.submission_started_at
    );
END;
$function$;


REVOKE ALL ON FUNCTION
    public.begin_liquidation_blockchain_submission(text, jsonb)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.begin_liquidation_blockchain_submission(text, jsonb)
TO service_role;