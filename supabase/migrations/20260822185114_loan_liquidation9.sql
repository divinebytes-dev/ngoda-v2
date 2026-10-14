CREATE OR REPLACE FUNCTION public.prepare_country_liquidation_blockchain_jobs(
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

    v_treasury public.users%rowtype;
    v_user public.users%rowtype;
    v_job public.liquidation_job%rowtype;

    v_document_prefix text;
    v_document_number text;
    v_queue_id text;
    v_configuration_error text;

    v_prepared integer := 0;
    v_existing integer := 0;
    v_failed integer := 0;

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
     * Only the liquidation cron service may prepare
     * blockchain transfers.
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
     * Prevent overlapping queue preparation for the same
     * country.
     */
    v_stage :=
        'lock country queue preparation';

    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-queue-preparation:%s',
                v_country_code
            )
        )
    );

    /*
     * Exit before fetching configuration when there is no
     * pending work for this country.
     *
     * A treasury and a document prefix are only required
     * when an actual blockchain queue entry will be made.
     */
    v_stage :=
        'check pending liquidation jobs';

    perform 1
    from public.liquidation_job
        job_record
    where lower(
        btrim(
            job_record.country_code
        )
    ) =
        v_country_code

      and job_record.status =
          'pending'::public."LiquidationJobStatus"
    limit 1;

    if not found then
        return jsonb_build_object(
            'success',
            true,

            'country_code',
            v_country_code,

            'prepared',
            0,

            'already_prepared',
            0,

            'failed',
            0,

            'jobs',
            '[]'::jsonb
        );
    end if;

    /*
     * Fetch the trusted country treasury.
     *
     * The treasury user remains country-specific for the
     * database accounting ledger. The Edge Function uses
     * the configured global Gold treasury address for the
     * actual blockchain transfer.
     */
    v_stage :=
        'fetch country treasury';

    begin
        select treasury_record.*
        into v_treasury
        from public.fetch_country_treasury(
            v_country_code
        ) as treasury_record;

        if not found
           or v_treasury.id is null
        then
            v_configuration_error :=
                'COUNTRY_TREASURY_NOT_FOUND';
        elsif nullif(
            btrim(
                v_treasury.wallet_address
            ),
            ''
        ) is null
        then
            v_configuration_error :=
                'TREASURY_BLOCKCHAIN_WALLET_NOT_CONFIGURED';
        end if;

    exception
        when others then
            get stacked diagnostics
                v_configuration_error =
                    message_text;
    end;

    /*
     * Do not raise here. Raising would roll back the job
     * update and leave a pending job with no explanation.
     *
     * Keep the job pending so the next cron run can retry
     * it after configuration is corrected.
     */
    if v_configuration_error is not null then
        update public.liquidation_job
            job_record
        set
            error_message =
                v_configuration_error
        where job_record.id in (
            select pending_job.id
            from public.liquidation_job
                pending_job
            where lower(
                btrim(
                    pending_job.country_code
                )
            ) =
                v_country_code

              and pending_job.status =
                  'pending'::public."LiquidationJobStatus"

            order by
                pending_job.id

            limit p_batch_size
        );

        get diagnostics
            v_failed =
                row_count;

        return jsonb_build_object(
            'success',
            false,

            'country_code',
            v_country_code,

            'prepared',
            0,

            'already_prepared',
            0,

            'failed',
            v_failed,

            'error_message',
            v_configuration_error,

            'jobs',
            '[]'::jsonb
        );
    end if;

    /*
     * Use the configured document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_configuration_error :=
        null;

    begin
        v_document_prefix :=
            public.fetch_transaction_doc_num_prefix(
                'loan_liquidation'::public."TransactionType"
            );

        if nullif(
            btrim(
                v_document_prefix
            ),
            ''
        ) is null
        then
            v_configuration_error :=
                'LOAN_LIQUIDATION_DOCUMENT_PREFIX_NOT_FOUND';
        end if;

    exception
        when others then
            get stacked diagnostics
                v_configuration_error =
                    message_text;
    end;

    if v_configuration_error is not null then
        update public.liquidation_job
            job_record
        set
            error_message =
                v_configuration_error
        where job_record.id in (
            select pending_job.id
            from public.liquidation_job
                pending_job
            where lower(
                btrim(
                    pending_job.country_code
                )
            ) =
                v_country_code

              and pending_job.status =
                  'pending'::public."LiquidationJobStatus"

            order by
                pending_job.id

            limit p_batch_size
        );

        get diagnostics
            v_failed =
                row_count;

        return jsonb_build_object(
            'success',
            false,

            'country_code',
            v_country_code,

            'prepared',
            0,

            'already_prepared',
            0,

            'failed',
            v_failed,

            'error_message',
            v_configuration_error,

            'jobs',
            '[]'::jsonb
        );
    end if;

    /*
     * Lock a limited number of pending jobs.
     *
     * SKIP LOCKED allows another worker to process other
     * jobs without processing the same job.
     */
    for v_job in
        select job_record.*
        from public.liquidation_job
            job_record
        where lower(
            btrim(
                job_record.country_code
            )
        ) =
            v_country_code

          and job_record.status =
              'pending'::public."LiquidationJobStatus"

        order by
            job_record.id

        for update skip locked

        limit p_batch_size
    loop
        v_stage :=
            format(
                'prepare job %s',
                v_job.id
            );

        begin

        /*
         * Resolve the borrower.
         */
        select user_record.*
        into v_user
        from public.users
            user_record
        where user_record.id =
              v_job.user_id
        limit 1;

        if not found then
            update public.liquidation_job
            set
                status =
                    'failed'::public."LiquidationJobStatus",

                error_message =
                    'LIQUIDATION_USER_NOT_FOUND'
            where id =
                  v_job.id;

            v_failed :=
                v_failed + 1;

            continue;
        end if;

        if v_user.wallet_index is null then
            update public.liquidation_job
            set
                status =
                    'failed'::public."LiquidationJobStatus",

                error_message =
                    'USER_BLOCKCHAIN_WALLET_INDEX_NOT_CONFIGURED'
            where id =
                  v_job.id;

            v_failed :=
                v_failed + 1;

            continue;
        end if;

        if nullif(
            btrim(
                v_user.wallet_address
            ),
            ''
        ) is null
        then
            update public.liquidation_job
            set
                status =
                    'failed'::public."LiquidationJobStatus",

                error_message =
                    'USER_BLOCKCHAIN_WALLET_NOT_CONFIGURED'
            where id =
                  v_job.id;

            v_failed :=
                v_failed + 1;

            continue;
        end if;

        /*
         * A queue record may already exist if an earlier
         * invocation stopped after creating the queue.
         */
        v_queue_id :=
            null;

        select queue_record.id::text
        into v_queue_id
        from public.liquidation_blockchain_queue
            queue_record
        where queue_record.liquidation_job_id =
              v_job.id::text
        limit 1;

        if found then
            update public.liquidation_job
            set
                status =
                    'blockchain_processing'::public."LiquidationJobStatus",

                blockchain_queue_id =
                    v_queue_id,

                error_message =
                    null
            where id =
                  v_job.id;

            v_existing :=
                v_existing + 1;

            continue;
        end if;

        /*
         * Generate one document number for the complete
         * liquidation.
         */
        v_document_number :=
            public.generate_document_number(
                v_document_prefix,
                v_job.fiscal_year,
                v_job.period,
                v_country_code
            );

        /*
         * Create the immutable blockchain instruction.
         *
         * receiver_wallet_address is retained for the
         * existing table shape. The transfer code validates
         * and uses the single global Gold treasury address.
         */
        insert into public.liquidation_blockchain_queue (
            liquidation_job_id,
            user_id,
            wallet_index,
            treasury_id,
            sender_wallet_address,
            receiver_wallet_address,
            collateral,
            debt_repayment_amount,
            penalty_amount,
            total_liquidation_proceeds,
            total_debt,
            gold_price,
            document_number,
            fiscal_year,
            period,
            country_code,
            status
        )
        values (
            v_job.id::text,
            v_job.user_id,
            v_user.wallet_index,
            v_treasury.id,
            v_user.wallet_address,
            v_treasury.wallet_address,
            v_job.collateral_required,
            v_job.repayment_required,
            v_job.penalty_amount,
            v_job.total_required,
            v_job.total_debt,
            v_job.gold_price,
            v_document_number,
            v_job.fiscal_year,
            v_job.period,
            v_country_code,
            'pending'::public."LiquidationBlockchainStatus"
        )
        returning id::text
        into v_queue_id;

        update public.liquidation_job
        set
            status =
                'blockchain_processing'::public."LiquidationJobStatus",

            document_number =
                v_document_number,

            blockchain_queue_id =
                v_queue_id,

            error_message =
                null
        where id =
              v_job.id;

        if not found then
            raise exception
                'LIQUIDATION_JOB_UPDATE_FAILED';
        end if;

        v_jobs :=
            v_jobs ||
            jsonb_build_array(
                jsonb_build_object(
                    'job_id',
                    v_job.id,

                    'queue_id',
                    v_queue_id,

                    'document_number',
                    v_document_number,

                    'user_id',
                    v_job.user_id,

                    'currency_code',
                    'gold',

                    'collateral',
                    trim_scale(
                        v_job.collateral_required
                    )::text,

                    'sender_wallet_address',
                    v_user.wallet_address,

                    'receiver_wallet_address',
                    v_treasury.wallet_address
                )
            );

        v_prepared :=
            v_prepared + 1;

        exception
            when others then
                get stacked diagnostics
                    v_error_message =
                        message_text;

                /*
                 * The failed statements inside this block
                 * are rolled back before this handler runs.
                 * Save the reason without raising again so
                 * the error remains visible on the job.
                 */
                update public.liquidation_job
                set
                    status =
                        'pending'::public."LiquidationJobStatus",

                    error_message =
                        v_error_message
                where id =
                      v_job.id;

                v_failed :=
                    v_failed + 1;
        end;
    end loop;

    return jsonb_build_object(
        'success',
        v_failed = 0,

        'country_code',
        v_country_code,

        'prepared',
        v_prepared,

        'already_prepared',
        v_existing,

        'failed',
        v_failed,

        'error_message',
        case
            when v_failed > 0
            then
                'ONE_OR_MORE_LIQUIDATION_JOBS_FAILED_TO_PREPARE'
            else
                null
        end,

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
                    'LIQUIDATION_QUEUE_PREPARATION_FAILED at [%s]: %s',
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
                    'Check the liquidation queue preparation stage'
                );
end;
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
     * Only the liquidation cron service may claim jobs.
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
     * Claim only jobs whose blockchain transfer is
     * confirmed in the queue.
     *
     * accounting_failed is included so a later cron run
     * can retry a database-accounting failure without
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


