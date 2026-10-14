create or replace function public.fetch_my_cash_transfer_context(
    p_v text
)
returns table (
    sender_id text,
    country_code text,
    wallet_address text,
    version_time integer
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
    select
        u.id,
        u.country_code,
        u.wallet_address,
        coalesce(
            (
                select tv."time"
                from public.transaction_v tv
                where tv.v = p_v
                limit 1
            ),
            30
        )
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name) in (
          'customer',
          'agent',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;
end;
$$;

revoke execute
on function public.fetch_my_cash_transfer_context(text)
from public, anon;

grant execute
on function public.fetch_my_cash_transfer_context(text)
to authenticated;

notify pgrst, 'reload schema';
