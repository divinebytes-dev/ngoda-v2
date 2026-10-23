CREATE OR REPLACE FUNCTION public.create_my_transaction_state(
    p_transaction jsonb,
    p_transaction_type public."TransactionType"
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user_id text;
    v_country_code text;
    v_transaction_id text;
    v_transaction_data jsonb;

    v_receiver_identifier text;
    v_state_user_id text;
    v_receiver public.users%rowtype;
begin
    /*
     * Authenticate the caller.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select
        u.id,
        u.country_code
    into
        v_user_id,
        v_country_code
    from public.users u
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_ACTIVE_OR_NOT_FOUND';
    end if;

    if nullif(btrim(v_country_code), '') is null then
        raise exception 'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Validate the request.
     */
    if p_transaction is null
       or jsonb_typeof(p_transaction) <> 'object'
    then
        raise exception 'TRANSACTION_DATA_IS_MISSING';
    end if;

    if p_transaction_type is null then
        raise exception 'TRANSACTION_TYPE_REQUIRED';
    end if;

    if nullif(btrim(p_transaction ->> 'r'), '') is null then
        raise exception 'TRANSACTION_REFERENCE_REQUIRED';
    end if;

    /*
     * Preserve the existing participant behavior for
     * other transaction types.
     */
    v_state_user_id := p_transaction ->> 's';

    /*
     * Cash transfer:
     *
     * The signed "s" field contains an email or phone.
     * transaction_state.user_id must contain users.id.
     *
     * Resolve the recipient without modifying the
     * signed transaction fields.
     */
    if p_transaction_type =
       'cash_transfer'::public."TransactionType"
    then
        v_receiver_identifier :=
            nullif(btrim(p_transaction ->> 's'), '');

        if v_receiver_identifier is null then
            raise exception 'RECEIVER_IDENTIFIER_MISSING';
        end if;

        v_receiver :=
            public.fetch_user_by_email_or_phone(
                v_receiver_identifier
            );

        if v_receiver.id is null then
            raise exception 'RECEIVER_NOT_FOUND';
        end if;

        if v_receiver.status is distinct from
           'active'::public."UserStatus"
        then
            raise exception 'RECEIVER_NOT_ACTIVE';
        end if;

        if v_receiver.id = v_user_id
           or v_receiver.country_code is distinct from
              v_country_code
        then
            raise exception 'OPERATION_NOT_ALLOWED';
        end if;

        v_state_user_id := v_receiver.id;

        /*
         * Do not require a receiver wallet here.
         * Posting creates it on first receipt if absent.
         */
    end if;

    v_transaction_id :=
        gen_random_uuid()::text;

    /*
     * Preserve the existing transaction-data structure
     * and the original signed field values.
     */
    v_transaction_data :=
        jsonb_build_object(
            'v', p_transaction -> 'v',
            'r', p_transaction -> 'r',
            's', p_transaction -> 's',
            'a', p_transaction -> 'a',
            'f', p_transaction -> 'f',
            'g', p_transaction -> 'g',
            'c', p_transaction -> 'c',
            't', p_transaction -> 't',
            'e', p_transaction -> 'e',
            'ms', p_transaction -> 'ms'
        );

    insert into public.transaction_state (
        id,
        reference,
        status,
        transaction_type,
        country_code,
        transaction_data,
        created_by,
        user_id,
        updated_at
    )
    values (
        v_transaction_id,
        p_transaction ->> 'r',
        'processing'::public."TransactionStatus",
        p_transaction_type,
        v_country_code,
        v_transaction_data,
        v_user_id,
        v_state_user_id,
        now()
    );

    return v_transaction_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$function$;