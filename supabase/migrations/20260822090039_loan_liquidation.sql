ALTER TABLE public.liquidation_job
ADD COLUMN IF NOT EXISTS accounting_retry_count integer NOT NULL DEFAULT 0;


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
    v_failure_message text;

    v_retry_count integer;
    v_retryable boolean;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation cron service may release a
     * failed accounting job.
     */
    v_stage :=
        'authorize service role';

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
    v_stage :=
        'validate input';

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

    v_failure_message :=
        coalesce(
            nullif(
                btrim(
                    p_error_message
                ),
                ''
            ),
            'UNKNOWN_LIQUIDATION_ACCOUNTING_ERROR'
        );

    /*
     * Lock the liquidation job.
     */
    v_stage :=
        'lock liquidation job';

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
     * A completed job must never be moved backwards.
     */
    if v_job.status::text =
       'completed'
    then
        return jsonb_build_object(
            'success',
            true,

            'job_id',
            v_job.id,

            'status',
            v_job.status,

            'retryable',
            false,

            'retry_count',
            coalesce(
                v_job.accounting_retry_count,
                0
            )
        );
    end if;

    if v_job.status::text <>
       'accounting_processing'
    then
        raise exception
            'LIQUIDATION_JOB_NOT_ACCOUNTING_PROCESSING';
    end if;

    /*
     * The blockchain must remain confirmed. Accounting
     * failure must never return the job to blockchain
     * processing.
     */
    perform 1
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
              v_job.blockchain_queue_id

      and queue_record.liquidation_job_id =
              v_job.id::text

      and queue_record.status::text =
              'confirmed'

      and nullif(
          btrim(
              queue_record.tx_hash
          ),
          ''
      ) is not null
    limit 1;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_CONFIRMATION_NOT_FOUND';
    end if;

    v_retry_count :=
        coalesce(
            v_job.accounting_retry_count,
            0
        ) + 1;

    v_retryable :=
        v_retry_count < 5;

    /*
     * Retryable failures return to blockchain_confirmed.
     *
     * The next cron execution can claim the job again
     * without repeating the blockchain movement.
     */
    if v_retryable then
        update public.liquidation_job
        set
            status =
                'blockchain_confirmed'::public."LiquidationJobStatus",

            accounting_retry_count =
                v_retry_count,

            accounting_started_at =
                null,

            error_message =
                left(
                    v_failure_message,
                    1000
                )
        where id =
              v_job.id
        returning *
        into v_job;
    else
        /*
         * Five accounting failures require manual
         * investigation.
         *
         * The blockchain transfer remains confirmed and
         * must never be submitted again.
         */
        update public.liquidation_job
        set
            status =
                'failed'::public."LiquidationJobStatus",

            accounting_retry_count =
                v_retry_count,

            accounting_started_at =
                null,

            error_message =
                left(
                    v_failure_message,
                    1000
                )
        where id =
              v_job.id
        returning *
        into v_job;
    end if;

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

        'retryable',
        v_retryable,

        'retry_count',
        v_retry_count,

        'error_message',
        v_job.error_message
    );

exception
    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_error_message =
                message_text,

            v_error_detail =
                pg_exception_detail,

            v_error_hint =
                pg_exception_hint,

            v_error_context =
                pg_exception_context;

        raise exception using
            errcode =
                v_error_state,

            message =
                format(
                    'LIQUIDATION_ACCOUNTING_FAILURE_HANDLER_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                concat_ws(
                    E'\n',
                    nullif(
                        v_error_detail,
                        ''
                    ),
                    nullif(
                        v_error_context,
                        ''
                    )
                ),

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the liquidation accounting failure-handler stage'
                );
end;
$function$;


