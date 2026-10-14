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

    return query
    select *
    from public.fetch_all_transaction_configs(
        v_country_code
    );
end;
$$;

