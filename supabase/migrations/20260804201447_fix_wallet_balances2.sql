create or replace function public.get_my_wallet_balance_snapshot(
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType"
)
returns jsonb
language plpgsql
stable
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

    if p_currency_code is null
       or btrim(p_currency_code) = ''
    then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception
            'WALLET_OWNER_IS_REQUIRED';
    end if;

    /*
     * Authentication, active-user validation and
     * required-role validation.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'treasury',
          'customer',
          'agent',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'WALLET_BALANCE_SNAPSHOT_NOT_AUTHORIZED';
    end if;

    return public.get_wallet_balance_snapshot(
        p_user_id =>
            v_user.id,

        p_currency_code =>
            lower(btrim(p_currency_code)),

        p_country_code =>
            v_user.country_code,

        p_wallet_owner =>
            p_wallet_owner
    );
end;
$function$;

revoke all
on function public.get_wallet_balance_snapshot(
    text,
    text,
    text,
    public."WalletOwnerType"
)
from public, anon, authenticated;

revoke all
on function public.get_my_wallet_balance_snapshot(
    text,
    public."WalletOwnerType"
)
from public, anon;

grant execute
on function public.get_my_wallet_balance_snapshot(
    text,
    public."WalletOwnerType"
)
to authenticated;