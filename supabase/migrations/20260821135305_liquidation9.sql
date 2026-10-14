ALTER TABLE public.liquidation_blockchain_queue
ADD COLUMN IF NOT EXISTS signed_at timestamptz;

CREATE OR REPLACE FUNCTION public.save_liquidation_blockchain_signed_payload(
    p_queue_id text,
    p_signed_payload jsonb
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

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation cron may save blockchain
     * signatures.
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

    if p_signed_payload is null
       or jsonb_typeof(
           p_signed_payload
       ) <> 'object'
    then
        raise exception
            'INVALID_LIQUIDATION_SIGNED_PAYLOAD';
    end if;

    if nullif(
        btrim(
            p_signed_payload ->> 'owner'
        ),
        ''
    ) is null
    then
        raise exception
            'SIGNED_PAYLOAD_OWNER_REQUIRED';
    end if;

    if nullif(
        btrim(
            p_signed_payload ->> 'to'
        ),
        ''
    ) is null
    then
        raise exception
            'SIGNED_PAYLOAD_RECEIVER_REQUIRED';
    end if;

    if nullif(
        btrim(
            p_signed_payload ->> 'parsedAmount'
        ),
        ''
    ) is null
    then
        raise exception
            'SIGNED_PAYLOAD_AMOUNT_REQUIRED';
    end if;

    if nullif(
        btrim(
            p_signed_payload ->> 'deadline'
        ),
        ''
    ) is null
    then
        raise exception
            'SIGNED_PAYLOAD_DEADLINE_REQUIRED';
    end if;

    if nullif(
        btrim(
            p_signed_payload ->> 'v'
        ),
        ''
    ) is null
       or nullif(
           btrim(
               p_signed_payload ->> 'r'
           ),
           ''
       ) is null
       or nullif(
           btrim(
               p_signed_payload ->> 's'
           ),
           ''
       ) is null
       or nullif(
           btrim(
               p_signed_payload ->> 'nonce'
           ),
           ''
       ) is null
    then
        raise exception
            'INCOMPLETE_LIQUIDATION_SIGNATURE';
    end if;

    /*
     * Lock the claimed queue row.
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

    if v_queue.status::text =
       'confirmed'
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_ALREADY_CONFIRMED';
    end if;

    if v_queue.status::text <>
       'processing'
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING';
    end if;

    /*
     * If a signature was already stored, return it.
     * Never generate a new blockchain nonce for the same
     * queue entry.
     */
    if v_queue.signed_payload is not null then
        return jsonb_build_object(
            'success',
            true,

            'queue_id',
            v_queue.id,

            'already_signed',
            true,

            'signed_payload',
            v_queue.signed_payload
        );
    end if;

    /*
     * Store the immutable signed payload before sending
     * it to the blockchain.
     */
    v_stage :=
        'save signed payload';

    update public.liquidation_blockchain_queue
    set
        signed_payload =
            p_signed_payload,

        signed_at =
            now(),

        reason =
            null
    where id =
          v_queue.id

      and signed_payload is null
    returning *
    into v_queue;

    if not found then
        raise exception
            'LIQUIDATION_SIGNED_PAYLOAD_SAVE_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'queue_id',
        v_queue.id,

        'already_signed',
        false,

        'signed_payload',
        v_queue.signed_payload
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
                    'LIQUIDATION_BLOCKCHAIN_SIGNATURE_FAILED at [%s]: %s',
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
                    'Check the liquidation blockchain signing stage'
                );
end;
$function$;

