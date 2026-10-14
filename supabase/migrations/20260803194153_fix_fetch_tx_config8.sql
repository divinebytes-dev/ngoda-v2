create or replace function public.fetch_my_transaction_configs()
returns table (
    config_key text,
    currency_code text,
    percentage numeric,
    fixed_amount numeric,
    min_amount numeric,
    max_amount numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_country_code text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select u.country_code
    into v_country_code
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name) in (
          'customer',
          'treasury',
          'finance',
          'agent',
          'admin',
          'accounts',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    if v_country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Active transaction fees for every currency in the
     * authenticated user's country.
     */
    return query
    select
        lower(f.transaction_type::text),
        lower(f.currency_code),
        coalesce(f.rate, 0)::numeric,
        f.fixed_amount::numeric,
        f.min_amount::numeric,
        f.max_amount::numeric
    from public.transaction_type_fee_config f
    where f.country_code = v_country_code
      and f.is_active = true;

    /*
     * Active government taxes for the user's country.
     */
    return query
    select
        lower(t.transaction_type::text) ||
            '_tax',
        lower(t.currency_code),
        coalesce(t.rate, 0)::numeric,
        t.fixed_amount::numeric,
        t.min_amount::numeric,
        t.max_amount::numeric
    from public.government_tax_config t
    where t.country_code = v_country_code
      and t.is_active = true;

    /*
     * Global gold buy spread.
     */
    return query
    select
        'gold_spread_' ||
            lower(s.direction::text),
        'gold'::text,
        coalesce(s.rate, 0)::numeric,
        null::numeric,
        null::numeric,
        null::numeric
    from public.spread_config s
    where s.direction =
          'buy'::public."SpreadDirection"
      and s.asset =
          'gold'::public."AssetType"
      and s.is_active = true
    limit 1;

    /*
     * Global gold sell spread.
     */
    return query
    select
        'gold_spread_' ||
            lower(s.direction::text),
        'gold'::text,
        coalesce(s.rate, 0)::numeric,
        null::numeric,
        null::numeric,
        null::numeric
    from public.spread_config s
    where s.direction =
          'sell'::public."SpreadDirection"
      and s.asset =
          'gold'::public."AssetType"
      and s.is_active = true
    limit 1;
end;
$$;


revoke execute
on function public.fetch_my_transaction_configs()
from public, anon;

grant execute
on function public.fetch_my_transaction_configs()
to authenticated;

notify pgrst, 'reload schema';