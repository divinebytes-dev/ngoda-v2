/* Canonical lifecycle RPC repairs for the supplied live schema. */

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
    v_queue_status text;
    v_queue_tx_hash text;
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

            'error_message',
            null,

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

        select
            queue_record.id::text,
            queue_record.status::text,
            queue_record.tx_hash
        into
            v_queue_id,
            v_queue_status,
            v_queue_tx_hash
        from public.liquidation_blockchain_queue
            queue_record
        where queue_record.liquidation_job_id =
              v_job.id::text
        limit 1;

        if found then
            /*
             * Queue existence is not processing. The claim
             * function changes both records only after it
             * obtains a time-limited processing lease.
             */
            update public.liquidation_job
            set
                status =
                    case
                        when v_queue_status = 'confirmed'
                         and nullif(btrim(v_queue_tx_hash), '') is not null
                        then
                            'blockchain_confirmed'
                                ::public."LiquidationJobStatus"
                        else
                            'pending'::public."LiquidationJobStatus"
                    end,

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
         * The country treasury id is for the database
         * ledger only. The global blockchain treasury is
         * obtained and validated by the Edge Function.
         * Its address is saved from the signed payload.
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
            null,
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
            'pending'::public."BlockchainLiquidationStatus"
        )
        returning id::text
        into v_queue_id;

        update public.liquidation_job
        set
            /* Processing begins only when the queue is claimed. */
            status =
                'pending'::public."LiquidationJobStatus",

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
                    'GLOBAL_TREASURY_FROM_EDGE_ENV'
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

revoke all on function
    public.prepare_country_liquidation_blockchain_jobs(text, integer)
from public, anon, authenticated;

grant execute on function
    public.prepare_country_liquidation_blockchain_jobs(text, integer)
to service_role;




create or replace function public.claim_country_liquidation_blockchain_jobs(
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
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_claimed integer := 0;
    v_jobs jsonb := '[]'::jsonb;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_country_code := lower(nullif(btrim(p_country_code), ''));

    if v_country_code is null then
        raise exception 'COUNTRY_CODE_REQUIRED';
    end if;

    if p_batch_size is null
       or p_batch_size < 1
       or p_batch_size > 100
    then
        raise exception 'INVALID_LIQUIDATION_BATCH_SIZE';
    end if;

    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-blockchain-claim:%s',
                v_country_code
            )
        )
    );

    /*
     * A transfer that was never submitted may stop after
     * five abandoned/failed attempts. Submitted transfers
     * are never abandoned because their receipt still has
     * to be reconciled.
     */
    update public.liquidation_blockchain_queue queue_record
    set
        status =
            'failed'::public."BlockchainLiquidationStatus",
        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED',
        lease_expires_at = null,
        updated_at = now()
    where lower(btrim(queue_record.country_code)) =
              v_country_code
      and queue_record.tx_hash is null
      and queue_record.attempt_count >= 5
      and queue_record.status::text in (
          'pending',
          'processing',
          'failed'
      );

    update public.liquidation_job job_record
    set
        status =
            'failed'::public."LiquidationJobStatus",
        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
    where lower(btrim(job_record.country_code)) =
              v_country_code
      and exists (
          select 1
          from public.liquidation_blockchain_queue queue_record
          where queue_record.liquidation_job_id =
                    job_record.id::text
            and queue_record.tx_hash is null
            and queue_record.attempt_count >= 5
            and queue_record.error_message =
                'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
      );

    for v_queue in
        select queue_record.*
        from public.liquidation_blockchain_queue queue_record
        where lower(btrim(queue_record.country_code)) =
                  v_country_code
          and queue_record.manual_review_required = false
          and (
              (
                  queue_record.status::text in (
                      'pending',
                      'failed'
                  )
                  and (
                      queue_record.tx_hash is not null
                      or queue_record.attempt_count < 5
                  )
              )
              or
              (
                  queue_record.status::text = 'processing'
                  and (
                      queue_record.lease_expires_at is null
                      or queue_record.lease_expires_at <= now()
                  )
                  and (
                      queue_record.tx_hash is not null
                      or queue_record.attempt_count < 5
                  )
              )
          )
        order by
            queue_record.created_at,
            queue_record.id
        for update skip locked
        limit p_batch_size
    loop
        update public.liquidation_blockchain_queue
        set
            status =
                'processing'::public."BlockchainLiquidationStatus",
            claimed_at = now(),
            lease_expires_at =
                now() + interval '5 minutes',
            attempt_count = attempt_count + 1,
            manual_review_required = false,
            error_message = null,
            updated_at = now()
        where id = v_queue.id
        returning * into v_queue;

        update public.liquidation_job
        set
            status =
                'blockchain_processing'::public."LiquidationJobStatus",
            blockchain_queue_id =
                v_queue.id::text,
            error_message = null
        where id::text =
              v_queue.liquidation_job_id;

        if not found then
            update public.liquidation_blockchain_queue
            set
                status =
                    'failed'::public."BlockchainLiquidationStatus",
                error_message =
                    'LIQUIDATION_JOB_NOT_FOUND',
                lease_expires_at = null,
                updated_at = now()
            where id = v_queue.id;

            continue;
        end if;

        v_jobs := v_jobs || jsonb_build_array(
            jsonb_build_object(
                'queue_id', v_queue.id::text,
                'liquidation_job_id',
                    v_queue.liquidation_job_id,
                'user_id', v_queue.user_id,
                'wallet_index', v_queue.wallet_index,
                'treasury_id', v_queue.treasury_id,
                'sender_wallet_address',
                    v_queue.sender_wallet_address,
                'collateral',
                    trim_scale(v_queue.collateral)::text,
                'debt_repayment_amount',
                    trim_scale(
                        v_queue.debt_repayment_amount
                    )::text,
                'penalty_amount',
                    trim_scale(v_queue.penalty_amount)::text,
                'total_liquidation_proceeds',
                    trim_scale(
                        v_queue.total_liquidation_proceeds
                    )::text,
                'total_debt',
                    trim_scale(v_queue.total_debt)::text,
                'gold_price',
                    trim_scale(v_queue.gold_price)::text,
                'document_number',
                    v_queue.document_number,
                'fiscal_year', v_queue.fiscal_year,
                'period', v_queue.period,
                'country_code',
                    lower(btrim(v_queue.country_code)),
                'retry_count', v_queue.retry_count,
                'attempt_count', v_queue.attempt_count,
                'manual_review_required',
                    v_queue.manual_review_required,
                'queue_status', v_queue.status::text,
                'tx_hash', v_queue.tx_hash,
                'claimed_at', v_queue.claimed_at,
                'lease_expires_at',
                    v_queue.lease_expires_at,
                'signed_payload', v_queue.signed_payload
            )
        );

        v_claimed := v_claimed + 1;
    end loop;

    return jsonb_build_object(
        'success', true,
        'country_code', v_country_code,
        'claimed', v_claimed,
        'jobs', v_jobs
    );
end;
$function$;

revoke all on function
    public.claim_country_liquidation_blockchain_jobs(text, integer)
from public, anon, authenticated;

grant execute on function
    public.claim_country_liquidation_blockchain_jobs(text, integer)
to service_role;


create or replace function public.save_liquidation_blockchain_signed_payload(
    p_queue_id text,
    p_signed_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_queue_id text;
    v_already_signed boolean := false;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id := nullif(btrim(p_queue_id), '');

    if v_queue_id is null then
        raise exception 'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if p_signed_payload is null
       or jsonb_typeof(p_signed_payload) <> 'object'
    then
        raise exception 'INVALID_LIQUIDATION_SIGNED_PAYLOAD';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue queue_record
    where queue_record.id::text = v_queue_id
    for update;

    if not found then
        raise exception 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.manual_review_required then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED';
    end if;

    if v_queue.tx_hash is not null then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_ALREADY_SUBMITTED';
    end if;

    if v_queue.status::text <> 'processing' then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    end if;

    if nullif(btrim(p_signed_payload ->> 'owner'), '') is null
       or nullif(btrim(p_signed_payload ->> 'to'), '') is null
       or nullif(btrim(p_signed_payload ->> 'parsedAmount'), '') is null
       or nullif(btrim(p_signed_payload ->> 'nonce'), '') is null
       or nullif(btrim(p_signed_payload ->> 'deadline'), '') is null
       or nullif(btrim(p_signed_payload ->> 'r'), '') is null
       or nullif(btrim(p_signed_payload ->> 's'), '') is null
       or nullif(btrim(p_signed_payload ->> 'v'), '') is null
    then
        raise exception
            'LIQUIDATION_SIGNED_PAYLOAD_FIELDS_REQUIRED';
    end if;

    if btrim(p_signed_payload ->> 'owner')
           !~ '^0x[0-9A-Fa-f]{40}$'
       or btrim(p_signed_payload ->> 'to')
           !~ '^0x[0-9A-Fa-f]{40}$'
    then
        raise exception
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD_ADDRESS';
    end if;

    if v_queue.signed_payload is null then
        update public.liquidation_blockchain_queue
        set
            signed_payload = p_signed_payload,
            signed_at = now(),
            receiver_wallet_address =
                btrim(p_signed_payload ->> 'to'),
            error_message = null,
            updated_at = now()
        where id = v_queue.id
        returning * into v_queue;
    else
        v_already_signed := true;

        if nullif(btrim(v_queue.receiver_wallet_address), '') is null then
            update public.liquidation_blockchain_queue
            set
                receiver_wallet_address =
                    btrim(v_queue.signed_payload ->> 'to'),
                signed_at = coalesce(signed_at, now()),
                updated_at = now()
            where id = v_queue.id
            returning * into v_queue;
        end if;
    end if;

    return jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'already_signed', v_already_signed,
        'signed_payload', v_queue.signed_payload
    );
end;
$function$;

revoke all on function
    public.save_liquidation_blockchain_signed_payload(text, jsonb)
from public, anon, authenticated;

grant execute on function
    public.save_liquidation_blockchain_signed_payload(text, jsonb)
to service_role;


create or replace function public.record_liquidation_blockchain_submission(
    p_queue_id text,
    p_tx_hash text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_queue_id text;
    v_tx_hash text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_tx_hash := nullif(btrim(p_tx_hash), '');

    if v_queue_id is null then
        raise exception 'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is null
       or v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue queue_record
    where queue_record.id::text = v_queue_id
    for update;

    if not found then
        raise exception 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.tx_hash is not null
       and lower(v_queue.tx_hash) <> lower(v_tx_hash)
    then
        raise exception 'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    if v_queue.status::text = 'confirmed' then
        return jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'tx_hash', v_queue.tx_hash,
            'submitted_at', v_queue.submitted_at
        );
    end if;

    if v_queue.status::text <> 'processing' then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    end if;

    if v_queue.signed_payload is null then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_SIGNED_PAYLOAD_NOT_FOUND';
    end if;

    perform 1
    from public.liquidation_blockchain_queue other_queue
    where lower(btrim(other_queue.tx_hash)) =
          lower(v_tx_hash)
      and other_queue.id <> v_queue.id
    limit 1;

    if found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_ALREADY_ASSIGNED';
    end if;

    update public.liquidation_blockchain_queue
    set
        status =
            'processing'::public."BlockchainLiquidationStatus",
        tx_hash = v_tx_hash,
        submitted_at = coalesce(submitted_at, now()),
        manual_review_required = false,
        lease_expires_at =
            now() + interval '5 minutes',
        error_message = null,
        updated_at = now()
    where id = v_queue.id
    returning * into v_queue;

    update public.liquidation_job
    set
        status =
            'blockchain_processing'::public."LiquidationJobStatus",
        error_message = null
    where id::text = v_queue.liquidation_job_id;

    return jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'tx_hash', v_queue.tx_hash,
        'submitted_at', v_queue.submitted_at
    );
end;
$function$;

revoke all on function
    public.record_liquidation_blockchain_submission(text, text)
from public, anon, authenticated;

grant execute on function
    public.record_liquidation_blockchain_submission(text, text)
to service_role;


drop function if exists
    public.fail_liquidation_blockchain_transfer(text, text);

create or replace function public.fail_liquidation_blockchain_transfer(
    p_queue_id text,
    p_error_message text,
    p_tx_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_queue_id text;
    v_error_message text;
    v_tx_hash text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_error_message :=
        coalesce(
            nullif(btrim(p_error_message), ''),
            'LIQUIDATION_BLOCKCHAIN_PROCESSING_FAILED'
        );
    v_tx_hash := nullif(btrim(p_tx_hash), '');

    if v_queue_id is null then
        raise exception 'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is not null
       and v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue queue_record
    where queue_record.id::text = v_queue_id
    for update;

    if not found then
        raise exception 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.status::text = 'confirmed' then
        return jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'tx_hash', v_queue.tx_hash,
            'error_message', null,
            'retryable', false
        );
    end if;

    v_tx_hash := coalesce(v_queue.tx_hash, v_tx_hash);

    if v_queue.tx_hash is not null
       and p_tx_hash is not null
       and lower(v_queue.tx_hash) <>
           lower(btrim(p_tx_hash))
    then
        raise exception 'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    if v_tx_hash is not null then
        /*
         * Submission may already be on-chain. Keep the hash
         * and make the lease immediately reclaimable. The
         * next worker checks the receipt; it does not relay.
         */
        update public.liquidation_blockchain_queue
        set
            status =
                'processing'::public."BlockchainLiquidationStatus",
            tx_hash = v_tx_hash,
            submitted_at = coalesce(submitted_at, now()),
            manual_review_required = false,
            error_message = v_error_message,
            retry_count = retry_count + 1,
            lease_expires_at = now(),
            updated_at = now()
        where id = v_queue.id;

        update public.liquidation_job
        set
            status =
                'blockchain_processing'::public."LiquidationJobStatus",
            error_message = v_error_message
        where id::text = v_queue.liquidation_job_id;
    else
        /* No transaction was submitted, so a clean retry is safe. */
        update public.liquidation_blockchain_queue
        set
            status =
                'failed'::public."BlockchainLiquidationStatus",
            error_message = v_error_message,
            retry_count = retry_count + 1,
            signed_payload = null,
            manual_review_required = false,
            claimed_at = null,
            lease_expires_at = null,
            updated_at = now()
        where id = v_queue.id;

        update public.liquidation_job
        set
            status =
                'failed'::public."LiquidationJobStatus",
            error_message = v_error_message
        where id::text = v_queue.liquidation_job_id;
    end if;

    return jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'tx_hash', v_tx_hash,
        'error_message', v_error_message,
        'retryable', true
    );
end;
$function$;

revoke all on function
    public.fail_liquidation_blockchain_transfer(text, text, text)
from public, anon, authenticated;

grant execute on function
    public.fail_liquidation_blockchain_transfer(text, text, text)
to service_role;


create or replace function public.confirm_liquidation_blockchain_transfer(
    p_queue_id text,
    p_tx_hash text,
    p_explorer_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_queue_id text;
    v_tx_hash text;
    v_receiver text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_tx_hash := nullif(btrim(p_tx_hash), '');

    if v_queue_id is null then
        raise exception 'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is null
       or v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue queue_record
    where queue_record.id::text = v_queue_id
    for update;

    if not found then
        raise exception 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.tx_hash is not null
       and lower(v_queue.tx_hash) <> lower(v_tx_hash)
    then
        raise exception 'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    if v_queue.status::text = 'confirmed' then
        return jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'liquidation_job_id', v_queue.liquidation_job_id,
            'status', v_queue.status,
            'tx_hash', v_queue.tx_hash,
            'confirmed_at', v_queue.confirmed_at
        );
    end if;

    perform 1
    from public.liquidation_blockchain_queue other_queue
    where lower(btrim(other_queue.tx_hash)) =
          lower(v_tx_hash)
      and other_queue.id <> v_queue.id
    limit 1;

    if found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_ALREADY_ASSIGNED';
    end if;

    v_receiver :=
        nullif(
            btrim(v_queue.signed_payload ->> 'to'),
            ''
        );

    if v_receiver is null
       or v_receiver !~ '^0x[0-9A-Fa-f]{40}$'
    then
        raise exception
            'INVALID_LIQUIDATION_BLOCKCHAIN_RECEIVER';
    end if;

    update public.liquidation_blockchain_queue
    set
        status =
            'confirmed'::public."BlockchainLiquidationStatus",
        tx_hash = v_tx_hash,
        receiver_wallet_address = v_receiver,
        explorer_url = nullif(btrim(p_explorer_url), ''),
        submitted_at = coalesce(submitted_at, now()),
        confirmed_at = coalesce(confirmed_at, now()),
        manual_review_required = false,
        error_message = null,
        lease_expires_at = null,
        updated_at = now()
    where id = v_queue.id
    returning * into v_queue;

    /* Idempotent blockchain audit row. */
    if not exists (
        select 1
        from public.blockchain_transaction blockchain_record
        where lower(blockchain_record.tx_hash) =
              lower(v_tx_hash)
    ) then
        insert into public.blockchain_transaction (
            document_number,
            fiscal_year,
            country_code,
            period,
            tx_hash,
            reference,
            transaction_type,
            chain,
            sender,
            receiver,
            quantity,
            gross_amount,
            net_amount,
            fee_amount,
            currency_code,
            chain_status,
            status,
            description,
            explorer_url,
            created_by
        )
        values (
            v_queue.document_number,
            v_queue.fiscal_year,
            lower(btrim(v_queue.country_code)),
            v_queue.period,
            v_tx_hash,
            v_queue.document_number,
            'loan_liquidation'::public."TransactionType",
            'chiado',
            v_queue.sender_wallet_address,
            v_receiver,
            v_queue.collateral,
            v_queue.total_debt,
            v_queue.debt_repayment_amount,
            v_queue.penalty_amount,
            'gold',
            'completed',
            'completed'::public."BlockchainTxStatus",
            format(
                'Loan liquidation blockchain transfer for user %s',
                v_queue.user_id
            ),
            nullif(btrim(p_explorer_url), ''),
            'system'
        );
    end if;

    update public.liquidation_job
    set
        status =
            'blockchain_confirmed'::public."LiquidationJobStatus",
        error_message = null
    where id::text = v_queue.liquidation_job_id;

    if not found then
        raise exception 'LIQUIDATION_JOB_NOT_FOUND';
    end if;

    return jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'liquidation_job_id',
            v_queue.liquidation_job_id,
        'status', v_queue.status,
        'tx_hash', v_queue.tx_hash,
        'confirmed_at', v_queue.confirmed_at
    );
end;
$function$;

revoke all on function
    public.confirm_liquidation_blockchain_transfer(text, text, text)
from public, anon, authenticated;

grant execute on function
    public.confirm_liquidation_blockchain_transfer(text, text, text)
to service_role;


create or replace function public.claim_country_liquidation_accounting_jobs(
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
    v_claimed integer := 0;
    v_jobs jsonb := '[]'::jsonb;
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    v_stage := 'authorize service role';

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_stage := 'validate input';
    v_country_code := lower(nullif(btrim(p_country_code), ''));

    if v_country_code is null then
        raise exception 'COUNTRY_CODE_REQUIRED';
    end if;

    if p_batch_size is null
       or p_batch_size < 1
       or p_batch_size > 100
    then
        raise exception 'INVALID_LIQUIDATION_BATCH_SIZE';
    end if;

    v_stage := 'lock country accounting claim';
    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-accounting-claim:%s',
                v_country_code
            )
        )
    );

    v_stage := 'claim confirmed liquidation jobs';

    with candidate_jobs as materialized (
        select job_record.id
        from public.liquidation_job job_record
        where lower(btrim(job_record.country_code)) =
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
                      job_record.accounting_started_at is null
                      or job_record.accounting_started_at <=
                          now() - interval '5 minutes'
                  )
              )
          )
          and exists (
              select 1
              from public.liquidation_blockchain_queue queue_record
              where queue_record.liquidation_job_id =
                    job_record.id::text
                and queue_record.status::text = 'confirmed'
                and nullif(btrim(queue_record.tx_hash), '') is not null
          )
        order by job_record.created_at, job_record.id
        for update skip locked
        limit p_batch_size
    ),
    claimed_jobs as (
        update public.liquidation_job job_record
        set
            status =
                'accounting_processing'::public."LiquidationJobStatus",
            accounting_started_at = now(),
            accounting_retry_count =
                case
                    when job_record.status::text in (
                        'accounting_failed',
                        'accounting_processing'
                    )
                    then job_record.accounting_retry_count + 1
                    else job_record.accounting_retry_count
                end,
            error_message = null
        from candidate_jobs
        where job_record.id = candidate_jobs.id
        returning
            job_record.id,
            lower(btrim(job_record.country_code)) as country_code
    )
    select
        count(*)::integer,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'job_id', claimed_job.id,
                    'country_code', claimed_job.country_code
                )
                order by claimed_job.id
            ),
            '[]'::jsonb
        )
    into v_claimed, v_jobs
    from claimed_jobs claimed_job;

    return jsonb_build_object(
        'success', true,
        'country_code', v_country_code,
        'claimed', v_claimed,
        'jobs', v_jobs
    );
exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,
            message = format(
                'LIQUIDATION_ACCOUNTING_CLAIM_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),
            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the liquidation accounting claim stage'
            );
end;
$function$;

revoke all on function
    public.claim_country_liquidation_accounting_jobs(text, integer)
from public, anon, authenticated;

grant execute on function
    public.claim_country_liquidation_accounting_jobs(text, integer)
to service_role;


create or replace function public.fail_liquidation_accounting_job(
    p_job_id text,
    p_error_message text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_job public.liquidation_job%rowtype;
    v_job_id text;
    v_error_message text;
    v_stage text := 'initialization';
    v_error_state text;
    v_database_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    v_stage := 'authorize service role';

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_stage := 'validate input';
    v_job_id := nullif(btrim(p_job_id), '');

    if v_job_id is null then
        raise exception 'LIQUIDATION_JOB_ID_REQUIRED';
    end if;

    v_error_message := coalesce(
        nullif(btrim(p_error_message), ''),
        'LIQUIDATION_ACCOUNTING_FAILED'
    );

    v_stage := 'lock liquidation job';

    select job_record.*
    into v_job
    from public.liquidation_job job_record
    where job_record.id::text = v_job_id
    for update;

    if not found then
        raise exception 'LIQUIDATION_JOB_NOT_FOUND';
    end if;

    if v_job.status::text = 'completed' then
        return jsonb_build_object(
            'success', true,
            'already_completed', true,
            'job_id', v_job.id,
            'status', v_job.status,
            'error_message', null,
            'retryable', false,
            'blockchain_transfer_required', false
        );
    end if;

    if v_job.status::text not in (
        'accounting_processing',
        'accounting_failed'
    ) then
        raise exception
            'INVALID_LIQUIDATION_JOB_STATUS_FOR_ACCOUNTING_FAILURE_%',
            upper(v_job.status::text);
    end if;

    v_stage := 'validate confirmed blockchain transfer';

    perform 1
    from public.liquidation_blockchain_queue queue_record
    where queue_record.liquidation_job_id = v_job.id::text
      and queue_record.status::text = 'confirmed'
      and nullif(btrim(queue_record.tx_hash), '') is not null
    limit 1;

    if not found then
        raise exception 'LIQUIDATION_BLOCKCHAIN_NOT_CONFIRMED';
    end if;

    v_stage := 'mark accounting failed';

    update public.liquidation_job
    set
        status =
            'accounting_failed'::public."LiquidationJobStatus",
        accounting_started_at = null,
        error_message = v_error_message
    where id = v_job.id
    returning * into v_job;

    return jsonb_build_object(
        'success', true,
        'already_completed', false,
        'job_id', v_job.id,
        'status', v_job.status,
        'error_message', v_job.error_message,
        'retryable', true,
        'blockchain_transfer_required', false
    );
exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_database_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,
            message = format(
                'LIQUIDATION_ACCOUNTING_FAILURE_UPDATE_FAILED at [%s]: %s',
                v_stage,
                v_database_error_message
            ),
            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),
            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the liquidation accounting failure stage'
            );
end;
$function$;

revoke all on function
    public.fail_liquidation_accounting_job(text, text)
from public, anon, authenticated;

grant execute on function
    public.fail_liquidation_accounting_job(text, text)
to service_role;


/* Remove obsolete PostgREST overloads and lock down RPC execution. */
drop function if exists
    public.update_gold_rate_from_ounce_price(text);

drop function if exists
    public.fail_liquidation_blockchain_transfer(text, text);

drop function if exists
    public.fetch_my_liquidated_loans_today(integer, integer);

revoke all on function
    public.update_gold_rate_from_ounce_price(numeric)
from public, anon, authenticated;

grant execute on function
    public.update_gold_rate_from_ounce_price(numeric)
to service_role;

revoke all on function
    public.fetch_active_operational_countries()
from public, anon, authenticated;

grant execute on function
    public.fetch_active_operational_countries()
to service_role;

revoke all on function
    public.fetch_gold_rate_api()
from public, anon, authenticated;

grant execute on function
    public.fetch_gold_rate_api()
to service_role;

revoke all on function
    public.detect_unhealthy_loan_positions(text, numeric)
from public, anon, authenticated;

grant execute on function
    public.detect_unhealthy_loan_positions(text, numeric)
to service_role;

revoke all on function
    public.finalise_liquidation_accounting_job(text)
from public, anon, authenticated;

grant execute on function
    public.finalise_liquidation_accounting_job(text)
to service_role;

revoke all on function
    public.fetch_my_liquidated_loans_by_date(date, integer, integer)
from public, anon;

grant execute on function
    public.fetch_my_liquidated_loans_by_date(date, integer, integer)
to authenticated;

revoke all on function
    public.fetch_my_incomplete_liquidation_jobs(integer, integer)
from public, anon;

grant execute on function
    public.fetch_my_incomplete_liquidation_jobs(integer, integer)
to authenticated;

revoke all on function
    public.fetch_incomplete_blockchain_transactions(integer, integer)
from public, anon;

grant execute on function
    public.fetch_incomplete_blockchain_transactions(integer, integer)
to authenticated;
