CREATE OR REPLACE FUNCTION public.claim_country_liquidation_accounting_jobs(
    p_country_code text,
    p_batch_size integer DEFAULT 25
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_country_code text;

    v_claimed integer := 0;

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
     * Serialize accounting claims for this country.
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
     * Claim only jobs where:
     *
     * 1. The blockchain queue is confirmed.
     * 2. The liquidation job is blockchain_confirmed or
     *    accounting_failed.
     *
     * accounting_failed jobs can be retried without
     * repeating the blockchain transfer.
     */
    v_stage :=
        'claim confirmed liquidation jobs';

    with candidate_jobs as (
        select job_record.id

        from public.liquidation_job
            job_record

        where lower(
            btrim(
                job_record.country_code
            )
        ) =
            v_country_code

          and job_record.status::text in (
              'blockchain_confirmed',
              'accounting_failed'
          )

          and exists (
              select 1

              from public.liquidation_blockchain_queue
                  queue_record

              where queue_record.liquidation_job_id =
                    job_record.id::text

                and queue_record.status::text =
                    'confirmed'

                and queue_record.tx_hash is not null
          )

        order by
            job_record.id

        for update skip locked

        limit p_batch_size
    ),

    claimed_jobs as (
        update public.liquidation_job
            job_record

        set
            status =
                'accounting_processing'::public."LiquidationJobStatus",

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


REVOKE ALL ON FUNCTION
    public.claim_country_liquidation_accounting_jobs(
        text,
        integer
    )
FROM public, anon, authenticated;


GRANT EXECUTE ON FUNCTION
    public.claim_country_liquidation_accounting_jobs(
        text,
        integer
    )
TO service_role;