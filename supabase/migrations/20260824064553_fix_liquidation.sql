/*
 * Recoverable liquidation blockchain processing.
 *
 * A processing claim is a five-minute lease.
 * A submitted transaction hash is persisted before waiting
 * for confirmation, preventing duplicate Gold transfers.
 */

alter table public.liquidation_blockchain_queue
    add column if not exists claimed_at timestamptz,
    add column if not exists lease_expires_at timestamptz,
    add column if not exists submitted_at timestamptz,
    add column if not exists confirmed_at timestamptz,
    add column if not exists tx_hash text,
    add column if not exists explorer_url text,
    add column if not exists error_message text,
    add column if not exists manual_review_required
        boolean not null default false,
    add column if not exists attempt_count
        integer not null default 0,
    add column if not exists retry_count
        integer not null default 0,
    add column if not exists updated_at
        timestamptz not null default now();


/*
 * Existing processing rows without a transaction hash
 * cannot safely be retried because we do not know whether
 * their blockchain transfer was submitted.
 */
update public.liquidation_blockchain_queue
set
    manual_review_required = true,

    error_message =
        coalesce(
            nullif(
                error_message,
                ''
            ),
            'LEGACY_PROCESSING_STATE_REQUIRES_RECONCILIATION'
        ),

    updated_at = now()

where status::text = 'processing'
  and tx_hash is null
  and claimed_at is null;


update public.liquidation_job
set
    error_message =
        coalesce(
            nullif(
                error_message,
                ''
            ),
            'LEGACY_PROCESSING_STATE_REQUIRES_RECONCILIATION'
        )

where exists (
    select 1
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.liquidation_job_id =
              liquidation_job.id::text
      and queue_record.manual_review_required =
              true
);


create index if not exists
    liquidation_blockchain_queue_claim_idx
on public.liquidation_blockchain_queue (
    country_code,
    status,
    lease_expires_at,
    created_at
);


create index if not exists
    liquidation_blockchain_queue_job_idx
on public.liquidation_blockchain_queue (
    liquidation_job_id
);


/*
 * Claim blockchain jobs.
 *
 * Processing is protected with a five-minute lease.
 * Expired leases are automatically picked again.
 */
create or replace function
public.claim_country_liquidation_blockchain_jobs(
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

    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_claimed integer := 0;

    v_jobs jsonb :=
        '[]'::jsonb;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

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

    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'liquidation-blockchain-claim:%s',
                v_country_code
            )
        )
    );

    /*
     * Stop clean, unsubmitted retries after five failed
     * attempts.
     *
     * A row with tx_hash is never abandoned automatically
     * because its blockchain receipt must be reconciled.
     */
    update public.liquidation_blockchain_queue
    set
        status =
            'failed'::public."LiquidationBlockchainStatus",

        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED',

        lease_expires_at =
            null,

        updated_at =
            now()

    where lower(
        btrim(
            country_code
        )
    ) =
        v_country_code

      and tx_hash is null

      and attempt_count >= 5

      and status::text in (
          'pending',
          'processing',
          'failed'
      );


    update public.liquidation_job
    set
        status =
            'failed'::public."LiquidationJobStatus",

        error_message =
            'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'

    where lower(
        btrim(
            country_code
        )
    ) =
        v_country_code

      and exists (
          select 1
          from public.liquidation_blockchain_queue
              queue_record

          where queue_record.liquidation_job_id =
                    liquidation_job.id::text

            and queue_record.tx_hash is null

            and queue_record.attempt_count >= 5

            and queue_record.error_message =
                'LIQUIDATION_BLOCKCHAIN_MAX_ATTEMPTS_REACHED'
      );


    for v_queue in
        select queue_record.*
        from public.liquidation_blockchain_queue
            queue_record

        where lower(
            btrim(
                queue_record.country_code
            )
        ) =
            v_country_code

          and queue_record.manual_review_required =
              false

          and (
              /*
               * Normal pending or failed jobs.
               */
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

              /*
               * Recover a worker whose processing lease
               * expired.
               */
              (
                  queue_record.status::text =
                      'processing'

                  and (
                      queue_record.lease_expires_at
                          is null

                      or queue_record.lease_expires_at <=
                          now()
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
                'processing'::public."LiquidationBlockchainStatus",

            claimed_at =
                now(),

            lease_expires_at =
                now() +
                interval '5 minutes',

            attempt_count =
                attempt_count + 1,

            manual_review_required =
                false,

            error_message =
                null,

            updated_at =
                now()

        where id =
              v_queue.id

        returning *
        into v_queue;


        update public.liquidation_job
        set
            status =
                'blockchain_processing'::public."LiquidationJobStatus",

            blockchain_queue_id =
                v_queue.id::text,

            error_message =
                null

        where id::text =
              v_queue.liquidation_job_id;


        if not found then
            update public.liquidation_blockchain_queue
            set
                status =
                    'failed'::public."LiquidationBlockchainStatus",

                error_message =
                    'LIQUIDATION_JOB_NOT_FOUND',

                lease_expires_at =
                    null,

                updated_at =
                    now()

            where id =
                  v_queue.id;

            continue;
        end if;


        v_jobs :=
            v_jobs ||
            jsonb_build_array(
                jsonb_build_object(
                    'queue_id',
                    v_queue.id::text,

                    'liquidation_job_id',
                    v_queue.liquidation_job_id,

                    'user_id',
                    v_queue.user_id,

                    'wallet_index',
                    v_queue.wallet_index,

                    'treasury_id',
                    v_queue.treasury_id,

                    'sender_wallet_address',
                    v_queue.sender_wallet_address,

                    'collateral',
                    trim_scale(
                        v_queue.collateral
                    )::text,

                    'debt_repayment_amount',
                    trim_scale(
                        v_queue.debt_repayment_amount
                    )::text,

                    'penalty_amount',
                    trim_scale(
                        v_queue.penalty_amount
                    )::text,

                    'total_liquidation_proceeds',
                    trim_scale(
                        v_queue.total_liquidation_proceeds
                    )::text,

                    'total_debt',
                    trim_scale(
                        v_queue.total_debt
                    )::text,

                    'gold_price',
                    trim_scale(
                        v_queue.gold_price
                    )::text,

                    'document_number',
                    v_queue.document_number,

                    'fiscal_year',
                    v_queue.fiscal_year,

                    'period',
                    v_queue.period,

                    'country_code',
                    lower(
                        btrim(
                            v_queue.country_code
                        )
                    ),

                    'retry_count',
                    v_queue.retry_count,

                    'attempt_count',
                    v_queue.attempt_count,

                    'manual_review_required',
                    v_queue.manual_review_required,

                    'queue_status',
                    v_queue.status::text,

                    'tx_hash',
                    v_queue.tx_hash,

                    'claimed_at',
                    v_queue.claimed_at,

                    'lease_expires_at',
                    v_queue.lease_expires_at,

                    'signed_payload',
                    v_queue.signed_payload
                )
            );

        v_claimed :=
            v_claimed + 1;
    end loop;


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
end;
$function$;


revoke all on function
    public.claim_country_liquidation_blockchain_jobs(
        text,
        integer
    )
from public, anon, authenticated;


grant execute on function
    public.claim_country_liquidation_blockchain_jobs(
        text,
        integer
    )
to service_role;


/*
 * Save the signed permit before blockchain submission.
 */
create or replace function
public.save_liquidation_blockchain_signed_payload(
    p_queue_id text,
    p_signed_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;

    v_already_signed boolean :=
        false;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id :=
        nullif(
            btrim(
                p_queue_id
            ),
            ''
        );

    if v_queue_id is null then
        raise exception
            'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if p_signed_payload is null
       or jsonb_typeof(
           p_signed_payload
       ) <> 'object'
    then
        raise exception
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
          v_queue_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.manual_review_required then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED';
    end if;

    if v_queue.tx_hash is not null then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_ALREADY_SUBMITTED';
    end if;

    if v_queue.signed_payload is null then
        update public.liquidation_blockchain_queue
        set
            signed_payload =
                p_signed_payload,

            updated_at =
                now()

        where id =
              v_queue.id

        returning *
        into v_queue;
    else
        v_already_signed :=
            true;
    end if;

    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'already_signed',
        v_already_signed,

        'signed_payload',
        v_queue.signed_payload
    );
end;
$function$;


revoke all on function
    public.save_liquidation_blockchain_signed_payload(
        text,
        jsonb
    )
from public, anon, authenticated;


grant execute on function
    public.save_liquidation_blockchain_signed_payload(
        text,
        jsonb
    )
to service_role;


/*
 * Persist the blockchain transaction hash immediately
 * after the relayer submits it.
 */
create or replace function
public.record_liquidation_blockchain_submission(
    p_queue_id text,
    p_tx_hash text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_tx_hash text;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id :=
        nullif(
            btrim(
                p_queue_id
            ),
            ''
        );

    v_tx_hash :=
        nullif(
            btrim(
                p_tx_hash
            ),
            ''
        );

    if v_queue_id is null then
        raise exception
            'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is null
       or v_tx_hash !~
          '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
          v_queue_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.tx_hash is not null
       and lower(
           v_queue.tx_hash
       ) <>
           lower(
               v_tx_hash
           )
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    update public.liquidation_blockchain_queue
    set
        status =
            'processing'::public."LiquidationBlockchainStatus",

        tx_hash =
            v_tx_hash,

        submitted_at =
            coalesce(
                submitted_at,
                now()
            ),

        manual_review_required =
            false,

        lease_expires_at =
            now() +
            interval '5 minutes',

        error_message =
            null,

        updated_at =
            now()

    where id =
          v_queue.id

    returning *
    into v_queue;


    update public.liquidation_job
    set
        status =
            'blockchain_processing'::public."LiquidationJobStatus",

        error_message =
            null

    where id::text =
          v_queue.liquidation_job_id;


    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'tx_hash',
        v_queue.tx_hash,

        'submitted_at',
        v_queue.submitted_at
    );
end;
$function$;


revoke all on function
    public.record_liquidation_blockchain_submission(
        text,
        text
    )
from public, anon, authenticated;


grant execute on function
    public.record_liquidation_blockchain_submission(
        text,
        text
    )
to service_role;


/*
 * Replace the previous two-argument failure function.
 */
drop function if exists
    public.fail_liquidation_blockchain_transfer(
        text,
        text
    );


create or replace function
public.fail_liquidation_blockchain_transfer(
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
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_error_message text;
    v_tx_hash text;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id :=
        nullif(
            btrim(
                p_queue_id
            ),
            ''
        );

    v_error_message :=
        coalesce(
            nullif(
                btrim(
                    p_error_message
                ),
                ''
            ),
            'LIQUIDATION_BLOCKCHAIN_PROCESSING_FAILED'
        );

    v_tx_hash :=
        nullif(
            btrim(
                p_tx_hash
            ),
            ''
        );

    if v_queue_id is null then
        raise exception
            'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is not null
       and v_tx_hash !~
           '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
          v_queue_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.tx_hash is not null
       and v_tx_hash is not null
       and lower(
           v_queue.tx_hash
       ) <>
           lower(
               v_tx_hash
           )
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    v_tx_hash :=
        coalesce(
            v_queue.tx_hash,
            v_tx_hash
        );

    if v_tx_hash is not null then
        /*
         * The transfer may already exist on-chain.
         * Keep the hash and make the lease immediately
         * reclaimable. The next worker checks the receipt.
         */
        update public.liquidation_blockchain_queue
        set
            status =
                'processing'::public."LiquidationBlockchainStatus",

            tx_hash =
                v_tx_hash,

            submitted_at =
                coalesce(
                    submitted_at,
                    now()
                ),

            manual_review_required =
                false,

            error_message =
                v_error_message,

            retry_count =
                retry_count + 1,

            lease_expires_at =
                now(),

            updated_at =
                now()

        where id =
              v_queue.id;


        update public.liquidation_job
        set
            status =
                'blockchain_processing'::public."LiquidationJobStatus",

            error_message =
                v_error_message

        where id::text =
              v_queue.liquidation_job_id;
    else
        /*
         * No transaction was submitted. A clean retry is
         * safe.
         */
        update public.liquidation_blockchain_queue
        set
            status =
                'failed'::public."LiquidationBlockchainStatus",

            error_message =
                v_error_message,

            retry_count =
                retry_count + 1,

            signed_payload =
                null,

            manual_review_required =
                false,

            claimed_at =
                null,

            lease_expires_at =
                null,

            updated_at =
                now()

        where id =
              v_queue.id;


        update public.liquidation_job
        set
            status =
                'failed'::public."LiquidationJobStatus",

            error_message =
                v_error_message

        where id::text =
              v_queue.liquidation_job_id;
    end if;


    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'tx_hash',
        v_tx_hash,

        'error_message',
        v_error_message,

        'retryable',
        true
    );
end;
$function$;


revoke all on function
    public.fail_liquidation_blockchain_transfer(
        text,
        text,
        text
    )
from public, anon, authenticated;


grant execute on function
    public.fail_liquidation_blockchain_transfer(
        text,
        text,
        text
    )
to service_role;


/*
 * Confirm the blockchain transfer and unlock accounting.
 */
create or replace function
public.confirm_liquidation_blockchain_transfer(
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
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_tx_hash text;
    v_receiver text;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_queue_id :=
        nullif(
            btrim(
                p_queue_id
            ),
            ''
        );

    v_tx_hash :=
        nullif(
            btrim(
                p_tx_hash
            ),
            ''
        );

    if v_queue_id is null then
        raise exception
            'LIQUIDATION_QUEUE_ID_REQUIRED';
    end if;

    if v_tx_hash is null
       or v_tx_hash !~
          '^0x[0-9A-Fa-f]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
          v_queue_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.tx_hash is not null
       and lower(
           v_queue.tx_hash
       ) <>
           lower(
               v_tx_hash
           )
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    end if;

    v_receiver :=
        coalesce(
            nullif(
                v_queue.signed_payload ->> 'to',
                ''
            ),
            v_queue.receiver_wallet_address
        );

    update public.liquidation_blockchain_queue
    set
        status =
            'confirmed'::public."LiquidationBlockchainStatus",

        tx_hash =
            v_tx_hash,

        explorer_url =
            nullif(
                btrim(
                    p_explorer_url
                ),
                ''
            ),

        submitted_at =
            coalesce(
                submitted_at,
                now()
            ),

        confirmed_at =
            coalesce(
                confirmed_at,
                now()
            ),

        manual_review_required =
            false,

        error_message =
            null,

        lease_expires_at =
            null,

        updated_at =
            now()

    where id =
          v_queue.id

    returning *
    into v_queue;


    /*
     * Store the blockchain audit transaction once.
     */
    if not exists (
        select 1
        from public.blockchain_transaction
            blockchain_record
        where lower(
            blockchain_record.tx_hash
        ) =
            lower(
                v_tx_hash
            )
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
            description,
            explorer_url,
            created_by
        )
        values (
            v_queue.document_number,
            v_queue.fiscal_year,
            lower(
                btrim(
                    v_queue.country_code
                )
            ),
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
            format(
                'Loan liquidation blockchain transfer for user %s',
                v_queue.user_id
            ),
            nullif(
                btrim(
                    p_explorer_url
                ),
                ''
            ),
            'system'
        );
    end if;


    update public.liquidation_job
    set
        status =
            'blockchain_confirmed'::public."LiquidationJobStatus",

        error_message =
            null

    where id::text =
          v_queue.liquidation_job_id;


    if not found then
        raise exception
            'LIQUIDATION_JOB_NOT_FOUND';
    end if;


    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'liquidation_job_id',
        v_queue.liquidation_job_id,

        'status',
        v_queue.status,

        'tx_hash',
        v_queue.tx_hash,

        'confirmed_at',
        v_queue.confirmed_at
    );
end;
$function$;


revoke all on function
    public.confirm_liquidation_blockchain_transfer(
        text,
        text,
        text
    )
from public, anon, authenticated;


grant execute on function
    public.confirm_liquidation_blockchain_transfer(
        text,
        text,
        text
    )
to service_role;