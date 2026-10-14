create or replace function public.get_my_multi_wallet_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Resolve the active application user and validate
     * the required role.
     */
    select u.id
    into v_user_id
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'agent',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    end if;

    return public.get_multi_wallet_balances(
        v_user_id
    );
end;
$function$;

revoke all
on function public.get_multi_wallet_balances(text)
from public, anon, authenticated;

revoke all
on function public.get_my_multi_wallet_balances()
from public, anon;

grant execute
on function public.get_my_multi_wallet_balances()
to authenticated;