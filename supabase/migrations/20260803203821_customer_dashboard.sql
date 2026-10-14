create or replace function public.fetch_my_customer_dashboard_context()
returns table (
    wallet_address text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    return query
    select u.wallet_address
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name) = 'customer'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'CUSTOMER_NOT_AUTHORIZED';
    end if;
end;
$$;