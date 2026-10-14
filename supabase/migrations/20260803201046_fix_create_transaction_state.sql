create or replace function public.create_my_transaction_state(
    p_transaction jsonb,
    p_transaction_type public."TransactionType"
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_country_code text;
    v_transaction_id text;
    v_transaction_data jsonb;
begin
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
      and u.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_ACTIVE_OR_NOT_FOUND';
    end if;

    if v_country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if nullif(
        trim(p_transaction ->> 'r'),
        ''
    ) is null then
        raise exception
            'TRANSACTION_REFERENCE_REQUIRED';
    end if;

    v_transaction_id :=
        gen_random_uuid()::text;

    /*
     * Preserve the same fields stored by the TypeScript service.
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
        p_transaction ->> 's',
        now()
    );

    return v_transaction_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$$;

create or replace function public.update_my_transaction_state(
    p_transaction_id text,
    p_status public."TransactionStatus",
    p_message text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    update public.transaction_state
    set
        status = p_status,
        message = p_message,
        updated_at = now()
    where id = p_transaction_id
      and created_by = auth.uid()::text;

    if not found then
        raise exception
            'TRANSACTION_STATE_NOT_FOUND';
    end if;
end;
$$;

revoke execute
on function public.create_my_transaction_state(
    jsonb,
    public."TransactionType"
)
from public, anon;

grant execute
on function public.create_my_transaction_state(
    jsonb,
    public."TransactionType"
)
to authenticated;

revoke execute
on function public.update_my_transaction_state(
    text,
    public."TransactionStatus",
    text
)
from public, anon;

grant execute
on function public.update_my_transaction_state(
    text,
    public."TransactionStatus",
    text
)
to authenticated;

notify pgrst, 'reload schema';
