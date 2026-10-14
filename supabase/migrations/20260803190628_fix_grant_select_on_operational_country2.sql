create or replace function public.fetch_operational_countries()
returns table (
    name text,
    country_code text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        c.name::text,
        c.country_code::text
    from public.operational_country c
    where c.is_active = true
    order by c.name;
$$;