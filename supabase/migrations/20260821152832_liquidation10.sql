CREATE OR REPLACE FUNCTION public.confirm_liquidation_blockchain_transfer(
    p_queue_id text,
    p_tx_hash text,
    p_explorer_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_tx_hash text;
    v_explorer_url text;

    v_sender_address text;
    v_receiver_address text;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
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

    v_queue_id :=
        nullif(
            btrim(
                p_queue_id
            ),
            ''
        );

    if v_queue_id is null then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_ID_REQUIRED';
    end if;

    v_tx_hash :=
        nullif(
            btrim(
                p_tx_hash
            ),
            ''
        );

    if v_tx_hash is null
       or v_tx_hash !~
          '^0x[0-9a-fA-F]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;

    v_explorer_url :=
        nullif(
            btrim(
                p_explorer_url
            ),
            ''
        );

    /*
     * Lock the blockchain queue.
     */
    v_stage :=
        'lock blockchain queue';

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

    /*
     * Idempotent confirmation.
     */
    if v_queue.status::text =
       'confirmed'
    then
        if lower(
            coalesce(
                v_queue.tx_hash,
                ''
            )
        ) <>
           lower(v_tx_hash)
        then
            raise exception
                'LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH_MISMATCH';
        end if;

        return jsonb_build_object(
            'success',
            true,

            'already_confirmed',
            true,

            'queue_id',
            v_queue.id,

            'liquidation_job_id',
            v_queue.liquidation_job_id,

            'tx_hash',
            v_queue.tx_hash,

            'status',
            v_queue.status
        );
    end if;

    if v_queue.status::text <>
       'processing'
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    end if;

    if v_queue.signed_payload is null then
        raise exception
            'LIQUIDATION_SIGNED_PAYLOAD_NOT_FOUND';
    end if;

    v_sender_address :=
        nullif(
            btrim(
                v_queue.signed_payload ->> 'owner'
            ),
            ''
        );

    v_receiver_address :=
        nullif(
            btrim(
                v_queue.signed_payload ->> 'to'
            ),
            ''
        );

    if v_sender_address is null
       or v_receiver_address is null
    then
        raise exception
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD_ADDRESSES';
    end if;

    /*
     * Prevent the same blockchain transaction from being
     * assigned to another queue.
     */
    perform 1
    from public.liquidation_blockchain_queue
        existing_queue
    where lower(
        coalesce(
            existing_queue.tx_hash,
            ''
        )
    ) =
        lower(v_tx_hash)

      and existing_queue.id <>
          v_queue.id
    limit 1;

    if found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ALREADY_ASSIGNED';
    end if;

    /*
     * Record the blockchain transaction.
     *
     * quantity is Gold.
     *
     * gross_amount, net_amount and fee_amount are the USD
     * liquidation values.
     */
    v_stage :=
        'record blockchain transaction';

    perform 1
    from public.blockchain_transaction
        blockchain_record
    where lower(
        blockchain_record.tx_hash
    ) =
        lower(v_tx_hash)
    limit 1;

    if not found then
        insert into public.blockchain_transaction (
            document_number,
            reference,

            fiscal_year,
            period,
            country_code,

            tx_hash,
            transaction_type,
            chain,

            sender,
            receiver,

            quantity,

            gross_amount,
            net_amount,
            fee_amount,

            currency_code,
            status,
            explorer_url,
            created_by
        )
        values (
            v_queue.document_number,
            v_queue.document_number,

            v_queue.fiscal_year,
            v_queue.period,
            v_queue.country_code,

            v_tx_hash,
            'loan_liquidation'::public."TransactionType",
            'chiado'::public."Blockchain",

            v_sender_address,
            v_receiver_address,

            v_queue.collateral,

            v_queue.total_liquidation_proceeds,
            v_queue.debt_repayment_amount,
            v_queue.penalty_amount,

            'usd',
            'completed'::public."BlockchainTxStatus",
            v_explorer_url,
            'system'
        );
    end if;

    /*
     * Confirm the queue.
     */
    v_stage :=
        'confirm blockchain queue';

    update public.liquidation_blockchain_queue
    set
        status =
            'confirmed'::public."LiquidationBlockchainStatus",

        tx_hash =
            v_tx_hash,

        confirmed_at =
            now(),

        processing_started_at =
            null,

        reason =
            null
    where id =
          v_queue.id
    returning *
    into v_queue;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_CONFIRMATION_FAILED';
    end if;

    /*
     * The liquidation is now ready for accounting.
     */
    v_stage :=
        'mark liquidation blockchain confirmed';

    update public.liquidation_job
    set
        status =
            'blockchain_confirmed'::public."LiquidationJobStatus",

        error_message =
            null
    where id::text =
          v_queue.liquidation_job_id

      and status =
          'blockchain_processing'::public."LiquidationJobStatus";

    if not found then
        raise exception
            'LIQUIDATION_JOB_BLOCKCHAIN_CONFIRMATION_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'already_confirmed',
        false,

        'queue_id',
        v_queue.id,

        'liquidation_job_id',
        v_queue.liquidation_job_id,

        'document_number',
        v_queue.document_number,

        'tx_hash',
        v_tx_hash,

        'status',
        v_queue.status
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
                    'LIQUIDATION_BLOCKCHAIN_CONFIRMATION_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                concat_ws(
                    E'\n',
                    nullif(v_error_detail, ''),
                    nullif(v_error_context, '')
                ),

            hint =
                coalesce(
                    nullif(v_error_hint, ''),
                    'Check the liquidation blockchain confirmation stage'
                );
end;
$function$;



CREATE OR REPLACE FUNCTION public.fail_liquidation_blockchain_transfer(
    p_queue_id text,
    p_error_message text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_queue_id text;
    v_error_message text;

    v_retry_count integer;
    v_retryable boolean;
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
            'LIQUIDATION_BLOCKCHAIN_QUEUE_ID_REQUIRED';
    end if;

    v_error_message :=
        coalesce(
            nullif(
                btrim(
                    p_error_message
                ),
                ''
            ),
            'UNKNOWN_BLOCKCHAIN_ERROR'
        );

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

    /*
     * A confirmed transfer must never be changed to
     * failed.
     */
    if v_queue.status::text =
       'confirmed'
    then
        return jsonb_build_object(
            'success',
            true,

            'queue_id',
            v_queue.id,

            'status',
            v_queue.status,

            'retryable',
            false,

            'retry_count',
            coalesce(
                v_queue.retry_count,
                0
            )
        );
    end if;

    v_retry_count :=
        coalesce(
            v_queue.retry_count,
            0
        ) + 1;

    v_retryable :=
        v_retry_count < 5;

    update public.liquidation_blockchain_queue
    set
        status =
            'failed'::public."LiquidationBlockchainStatus",

        retry_count =
            v_retry_count,

        processing_started_at =
            null,

        last_attempt_at =
            now(),

        reason =
            left(
                v_error_message,
                1000
            )
    where id =
          v_queue.id
    returning *
    into v_queue;

    /*
     * After five failed attempts, mark the parent job as
     * failed. The signed payload remains stored for
     * investigation or controlled retry.
     */
    if not v_retryable then
        update public.liquidation_job
        set
            status =
                'failed'::public."LiquidationJobStatus",

            error_message =
                left(
                    v_error_message,
                    1000
                )
        where id::text =
              v_queue.liquidation_job_id;
    end if;

    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'status',
        v_queue.status,

        'retry_count',
        v_retry_count,

        'retryable',
        v_retryable
    );
end;
$function$;


