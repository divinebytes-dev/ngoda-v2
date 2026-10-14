create or replace function public.fetch_country_treasury(
    p_country_code text
)
returns public.users
language plpgsql
stable
as $$
declare
    v_treasury public.users%rowtype;
begin
    select u.*
    into v_treasury
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.country_code = p_country_code
      and r.name = 'treasury'
    limit 1;

    if not found then
        raise exception 'TREASURY_NOT_FOUND';
    end if;

    return v_treasury;
end;
$$;