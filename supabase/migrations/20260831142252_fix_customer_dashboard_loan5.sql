create or replace function public.fetch_my_additional_collateral_context()
returns table (
    user_id text,
    country_code text,
    user_wallet_address text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

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
    into v_user
    from public.users user_record
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if nullif(
        btrim(v_user.country_code),
        ''
    ) is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if nullif(
        btrim(v_user.wallet_address),
        ''
    ) is null then
        raise exception
            'USER_WALLET_ADDRESS_NOT_FOUND';
    end if;

    return query
    select
        v_user.id::text,
        v_user.country_code::text,
        v_user.wallet_address::text;
end;
$function$;


revoke all
on function public.fetch_my_additional_collateral_context()
from public, anon;

grant execute
on function public.fetch_my_additional_collateral_context()
to authenticated;


notify pgrst, 'reload schema';