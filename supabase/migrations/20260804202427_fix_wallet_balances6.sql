create or replace function public.get_my_wallet_period_entries(
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer,
    p_page integer default 1,
    p_page_size integer default 50
)
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

    if p_fiscal_year is null then
        raise exception
            'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception
            'PERIOD_IS_REQUIRED';
    end if;

    if p_period < 1 or p_period > 12 then
        raise exception
            'INVALID_PERIOD';
    end if;

    if p_page is null or p_page < 1 then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
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
          'treasury',
          'agent',
          'customer',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'WALLET_PERIOD_ENTRIES_NOT_AUTHORIZED';
    end if;

    return public.get_wallet_period_entries(
        p_user_id =>
            v_user_id,

        p_currency_code =>
            lower(btrim(p_currency_code)),

        p_wallet_owner =>
            p_wallet_owner,

        p_fiscal_year =>
            p_fiscal_year,

        p_period =>
            p_period,

        p_page =>
            p_page,

        p_page_size =>
            p_page_size
    );
end;
$function$;

revoke all
on function public.get_wallet_period_entries(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
)
from public, anon, authenticated;

revoke all
on function public.get_my_wallet_period_entries(
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
)
from public, anon;

grant execute
on function public.get_my_wallet_period_entries(
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
)
to authenticated;