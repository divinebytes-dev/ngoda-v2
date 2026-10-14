create or replace function public.fetch_my_gold_transfer_context(
    p_v text
)
returns table (
    sender_id text,
    country_code text,
    wallet_address text,
    wallet_index bigint,
    version_time bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_sender public.users%rowtype;
    v_version_time bigint;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_v is distinct from 'v6' then
        raise exception using
            errcode = '42501',
            message = 'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Continue using the existing centralized
     * authenticated role function.
     */
    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_sender
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    if v_sender.country_code is null
       or btrim(
           v_sender.country_code
       ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_sender.wallet_address is null
       or btrim(
           v_sender.wallet_address
       ) = ''
    then
        raise exception
            'USER_WALLET_NOT_CONFIGURED';
    end if;

    if v_sender.wallet_index is null then
        raise exception
            'USER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    /*
     * Correct existing function name.
     */
    select public.get_transaction_v(
        p_v
    )::bigint
    into v_version_time;

    if v_version_time is null
       or v_version_time <= 0
    then
        raise exception
            'INVALID_TRANSACTION_VERSION';
    end if;

    return query
    select
        v_sender.id,
        lower(
            btrim(
                v_sender.country_code
            )
        ),
        v_sender.wallet_address,
        v_sender.wallet_index::bigint,
        v_version_time;
end;
$function$;

alter function public.fetch_my_gold_transfer_context(
    text
)
owner to postgres;

revoke all
on function public.fetch_my_gold_transfer_context(
    text
)
from public, anon, authenticated, service_role;

grant execute
on function public.fetch_my_gold_transfer_context(
    text
)
to authenticated;