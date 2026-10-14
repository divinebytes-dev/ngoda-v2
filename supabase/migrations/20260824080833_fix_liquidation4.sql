CREATE OR REPLACE FUNCTION public.fail_liquidation_accounting_job(
    p_job_id text,
    p_error_message text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_job
        public.liquidation_job%rowtype;

    v_job_id text;
    v_error_message text;
begin
    /*
     * Only the liquidation cron service may update
     * accounting failures.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    /*
     * Validate input.
     */
    v_job_id :=
        nullif(
            btrim(
                p_job_id
            ),
            ''
        );

    if v_job_id is null then
        raise exception
            'LIQUIDATION_JOB_ID_REQUIRED';
    end if;

    v_error_message :=
        coalesce(
            nullif(
                btrim(
                    p_error_message
                ),
                ''
            ),
            'LIQUIDATION_ACCOUNTING_PROCESSING_FAILED'
        );

    /*
     * Lock the liquidation job.
     */
    select job_record.*
    into v_job
    from public.liquidation_job
        job_record
    where job_record.id::text =
          v_job_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_JOB_NOT_FOUND';
    end if;

    /*
     * A completed liquidation must never be moved back to
     * an accounting failure state.
     */
    if v_job.status::text in (
        'completed',
        'liquidated'
    ) then
        raise exception
            'COMPLETED_LIQUIDATION_JOB_CANNOT_BE_FAILED';
    end if;

    /*
     * The blockchain transfer must already be confirmed.
     *
     * An accounting failure must never cause the Gold
     * transfer to be submitted again.
     */
    if not exists (
        select 1

        from public.liquidation_blockchain_queue
            queue_record

        where queue_record.liquidation_job_id =
              v_job.id::text

          and queue_record.status::text =
              'confirmed'

          and queue_record.tx_hash is not null
    ) then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TRANSFER_NOT_CONFIRMED';
    end if;

    /*
     * Mark the accounting stage as failed and retryable.
     *
     * claim_country_liquidation_accounting_jobs() includes
     * accounting_failed jobs in its next claim.
     */
    update public.liquidation_job
    set
        status =
            'accounting_failed'::public."LiquidationJobStatus",

        error_message =
            v_error_message

    where id =
          v_job.id

    returning *
    into v_job;

    if not found then
        raise exception
            'LIQUIDATION_ACCOUNTING_FAILURE_UPDATE_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'job_id',
        v_job.id,

        'status',
        v_job.status,

        'error_message',
        v_job.error_message,

        'retryable',
        true,

        'blockchain_transfer_required',
        false
    );
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fail_liquidation_accounting_job(
        text,
        text
    )
FROM public, anon, authenticated;


GRANT EXECUTE ON FUNCTION
    public.fail_liquidation_accounting_job(
        text,
        text
    )
TO service_role;

