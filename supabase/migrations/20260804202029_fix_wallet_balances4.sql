create or replace function public.get_my_wallet_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Required-role validation:
     * - treasury
     * - customer
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
          'treasury',
          'customer'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'WALLET_BALANCES_NOT_AUTHORIZED';
    end if;

    return public.get_wallet_balances(
        v_user_id
    );
end;
$function$;

revoke all
on function public.get_wallet_balances(text)
from public, anon, authenticated;

revoke all
on function public.get_my_wallet_balances()
from public, anon;

grant execute
on function public.get_my_wallet_balances()
to authenticated;