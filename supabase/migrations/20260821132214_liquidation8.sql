ALTER TYPE public."BlockchainLiquidationStatus"
ADD VALUE IF NOT EXISTS 'processing';

ALTER TABLE public.liquidation_blockchain_queue
ADD COLUMN IF NOT EXISTS processing_started_at timestamptz,
ADD COLUMN IF NOT EXISTS last_attempt_at timestamptz,
ADD COLUMN IF NOT EXISTS signed_payload jsonb;

CREATE OR REPLACE FUNCTION public.claim_country_liquidation_blockchain_jobs(
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

    v_jobs jsonb :=
        '[]'::jsonb;

    v_claimed integer := 0;

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
     * blockchain jobs.
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
     * Claim:
     *
     * - new pending jobs;
     * - retryable failed jobs;
     * - processing jobs abandoned for more than five
     *   minutes by an interrupted Edge Function.
     *
     * SKIP LOCKED prevents concurrent cron executions
     * from claiming the same rows.
     */
    v_stage :=
        'claim blockchain jobs';

    with candidate_jobs as (
        select queue_record.id
        from public.liquidation_blockchain_queue
            queue_record

        where lower(
            btrim(
                queue_record.country_code
            )
        ) =
            v_country_code

          and coalesce(
              queue_record.retry_count,
              0
          ) < 5

          and (
              queue_record.status::text in (
                  'pending',
                  'failed'
              )

              or (
                  queue_record.status::text =
                      'processing'

                  and queue_record.processing_started_at <
                      now() -
                      interval '5 minutes'
              )
          )

        order by
            queue_record.id

        for update skip locked

        limit p_batch_size
    ),

    claimed_jobs as (
        update public.liquidation_blockchain_queue
            queue_record
        set
            status =
                'processing'::public."BlockchainLiquidationStatus",

            processing_started_at =
                now(),

            last_attempt_at =
                now(),

            reason =
                null

        from candidate_jobs
            candidate_record

        where queue_record.id =
              candidate_record.id

        returning
            queue_record.id,
            queue_record.liquidation_job_id,
            queue_record.user_id,
            queue_record.wallet_index,
            queue_record.treasury_id,
            queue_record.sender_wallet_address,
            queue_record.receiver_wallet_address,
            queue_record.collateral,
            queue_record.debt_repayment_amount,
            queue_record.penalty_amount,
            queue_record.total_liquidation_proceeds,
            queue_record.total_debt,
            queue_record.gold_price,
            queue_record.document_number,
            queue_record.fiscal_year,
            queue_record.period,
            queue_record.country_code,
            queue_record.retry_count,
            queue_record.signed_payload
    )

    select
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'queue_id',
                    claimed_record.id,

                    'liquidation_job_id',
                    claimed_record.liquidation_job_id,

                    'user_id',
                    claimed_record.user_id,

                    'wallet_index',
                    claimed_record.wallet_index,

                    'treasury_id',
                    claimed_record.treasury_id,

                    'sender_wallet_address',
                    claimed_record.sender_wallet_address,

                    'receiver_wallet_address',
                    claimed_record.receiver_wallet_address,

                    'collateral',
                    trim_scale(
                        claimed_record.collateral
                    )::text,

                    'debt_repayment_amount',
                    trim_scale(
                        claimed_record.debt_repayment_amount
                    )::text,

                    'penalty_amount',
                    trim_scale(
                        claimed_record.penalty_amount
                    )::text,

                    'total_liquidation_proceeds',
                    trim_scale(
                        claimed_record.total_liquidation_proceeds
                    )::text,

                    'total_debt',
                    trim_scale(
                        claimed_record.total_debt
                    )::text,

                    'gold_price',
                    trim_scale(
                        claimed_record.gold_price
                    )::text,

                    'document_number',
                    claimed_record.document_number,

                    'fiscal_year',
                    claimed_record.fiscal_year,

                    'period',
                    claimed_record.period,

                    'country_code',
                    claimed_record.country_code,

                    'retry_count',
                    coalesce(
                        claimed_record.retry_count,
                        0
                    ),

                    'signed_payload',
                    claimed_record.signed_payload
                )
                order by
                    claimed_record.id
            ),
            '[]'::jsonb
        ),

        count(*)::integer

    into
        v_jobs,
        v_claimed

    from claimed_jobs
        claimed_record;

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
                    'LIQUIDATION_BLOCKCHAIN_CLAIM_FAILED at [%s]: %s',
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
                    'Check the liquidation blockchain claim stage'
                );
end;
$function$;

