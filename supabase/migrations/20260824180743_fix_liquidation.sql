/*
 * Recoverable liquidation accounting processing.
 *
 * Accounting runs only after blockchain confirmation.
 * A processing claim lasts five minutes. If an Edge
 * Function stops unexpectedly, another cron invocation
 * can safely reclaim the accounting job.
 *
 * The accounting finalization RPC is one PostgreSQL
 * transaction, so an interrupted call cannot leave
 * partially committed accounting entries.
 */

alter table public.liquidation_job
    add column if not exists
        accounting_started_at timestamptz;


/*
 * Supports accounting claim and stale-job recovery.
 */
create index if not exists
    liquidation_job_accounting_claim_idx
on public.liquidation_job (
    country_code,
    status,
    accounting_started_at,
    created_at
);


/*
 * Claim blockchain-confirmed liquidation jobs for
 * accounting.
 *
 * The following jobs are eligible:
 *
 * 1. blockchain_confirmed
 * 2. accounting_failed
 * 3. stale accounting_processing
 *
 * A stale accounting job can safely be retried because
 * finalise_liquidation_accounting_job executes atomically.
 */
create or replace function
public.claim_country_liquidation_accounting_jobs(
    p_country_code text,
    p_batch_size integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_country_code text;

    v_claimed integer :=
        0;

    v_jobs jsonb :=
        '[]'::jsonb;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation cron service may claim
     * accounting jobs.
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

    v_country_code :=
        lower(
            nullif(
                btrim(
                    p_country_code
                ),
                ''
            )
        );

    if v_country_code is null then
        raise exception
            'COUNTRY_CODE_REQUIRED';
    end if;

    if p_batch_size is null
       or p_batch_size < 1
       or p_batch_size > 100
    then
        raise exception
            'INVALID_LIQUIDATION_BATCH_SIZE';
    end if;

    /*
     * Prevent simultaneous accounting claims for the same
     * country.
     */
    v_stage :=
        'lock country accounting claim';

    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-accounting-claim:%s',
                v_country_code
            )
        )
    );

    /*
     * Claim only jobs with a confirmed blockchain queue
     * and a recorded transaction hash.
     *
     * A processing job becomes reclaimable after five
     * minutes.
     */
    v_stage :=
        'claim confirmed liquidation jobs';

    with candidate_jobs as materialized (
        select
            job_record.id

        from public.liquidation_job
            job_record

        where lower(
            btrim(
                job_record.country_code
            )
        ) =
            v_country_code

          and (
              job_record.status::text in (
                  'blockchain_confirmed',
                  'accounting_failed'
              )

              or (
                  job_record.status::text =
                      'accounting_processing'

                  and (
                      job_record.accounting_started_at
                          is null

                      or job_record.accounting_started_at <=
                          now() -
                          interval '5 minutes'
                  )
              )
          )

          and exists (
              select 1

              from public.liquidation_blockchain_queue
                  queue_record

              where queue_record.liquidation_job_id =
                        job_record.id::text

                and queue_record.status::text =
                        'confirmed'

                and nullif(
                    btrim(
                        queue_record.tx_hash
                    ),
                    ''
                ) is not null
          )

        order by
            job_record.created_at,
            job_record.id

        for update skip locked

        limit p_batch_size
    ),

    claimed_jobs as (
        update public.liquidation_job
            job_record

        set
            status =
                'accounting_processing'
                    ::public."LiquidationJobStatus",

            accounting_started_at =
                now(),

            error_message =
                null

        from candidate_jobs

        where job_record.id =
              candidate_jobs.id

        returning
            job_record.id,

            lower(
                btrim(
                    job_record.country_code
                )
            ) as country_code
    )

    select
        count(*)::integer,

        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'job_id',
                    claimed_job.id,

                    'country_code',
                    claimed_job.country_code
                )
                order by
                    claimed_job.id
            ),
            '[]'::jsonb
        )

    into
        v_claimed,
        v_jobs

    from claimed_jobs
        claimed_job;

    return jsonb_build_object(
        'success',
        true,

        'country_code',
        v_country_code,

        'claimed',
        v_claimed,

        'jobs',
        v_jobs
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
                    'LIQUIDATION_ACCOUNTING_CLAIM_FAILED at [%s]: %s',
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
                    'Check the liquidation accounting claim stage'
                );
end;
$function$;


revoke all on function
    public.claim_country_liquidation_accounting_jobs(
        text,
        integer
    )
from public, anon, authenticated;

grant execute on function
    public.claim_country_liquidation_accounting_jobs(
        text,
        integer
    )
to service_role;


/*
 * Record an accounting failure.
 *
 * This function never changes the confirmed blockchain
 * queue. Therefore, retrying this job cannot transfer Gold
 * again.
 */
create or replace function
public.fail_liquidation_accounting_job(
    p_job_id text,
    p_error_message text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_job
        public.liquidation_job%rowtype;

    v_job_id text;
    v_error_message text;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_database_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation cron service may record the
     * accounting failure.
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

    v_error_message :=
        coalesce(
            nullif(
                btrim(
                    p_error_message
                ),
                ''
            ),
            'LIQUIDATION_ACCOUNTING_FAILED'
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
     * If finalization committed but the Edge Function lost
     * the response, never downgrade the completed job.
     */
    if v_job.status::text =
       'completed'
    then
        return jsonb_build_object(
            'success',
            true,

            'already_completed',
            true,

            'job_id',
            v_job.id,

            'status',
            v_job.status,

            'error_message',
            null,

            'retryable',
            false,

            'blockchain_transfer_required',
            false
        );
    end if;

    /*
     * Repeating the failure update is idempotent.
     */
    if v_job.status::text =
       'accounting_failed'
    then
        update public.liquidation_job
        set
            accounting_started_at =
                null,

            error_message =
                v_error_message

        where id =
              v_job.id

        returning *
        into v_job;

        return jsonb_build_object(
            'success',
            true,

            'already_completed',
            false,

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
    end if;

    if v_job.status::text <>
       'accounting_processing'
    then
        raise exception
            'INVALID_LIQUIDATION_JOB_STATUS_FOR_ACCOUNTING_FAILURE_%',
            upper(
                v_job.status::text
            );
    end if;

    /*
     * The blockchain transfer must already be confirmed.
     *
     * This prevents this function from being used to skip
     * the blockchain stage.
     */
    v_stage :=
        'validate confirmed blockchain transfer';

    perform 1
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.liquidation_job_id =
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
            'LIQUIDATION_BLOCKCHAIN_NOT_CONFIRMED';
    end if;

    /*
     * Make the job retryable by the accounting claim
     * function. The confirmed blockchain transfer remains
     * untouched.
     */
    v_stage :=
        'mark accounting failed';

    update public.liquidation_job
    set
        status =
            'accounting_failed'
                ::public."LiquidationJobStatus",

        accounting_started_at =
            null,

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

        'already_completed',
        false,

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

exception
    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_database_error_message =
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
                    'LIQUIDATION_ACCOUNTING_FAILURE_UPDATE_FAILED at [%s]: %s',
                    v_stage,
                    v_database_error_message
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
                    'Check the liquidation accounting failure stage'
                );
end;
$function$;


revoke all on function
    public.fail_liquidation_accounting_job(
        text,
        text
    )
from public, anon, authenticated;

grant execute on function
    public.fail_liquidation_accounting_job(
        text,
        text
    )
to service_role;