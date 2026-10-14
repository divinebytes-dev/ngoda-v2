create or replace function public.fetch_fiscal_period(
    p_country_code text,
    p_date timestamp without time zone default now()
)
returns table (
    fiscal_year integer,
    period integer,
    period_name text
)
language plpgsql
stable
as $$
begin
    return query
    select
        f.fiscal_year,
        f.period,
        f.period_name
    from public.fiscal_period_config f
    where f.country_code = p_country_code
      and f.opening_date <= p_date
      and f.closing_date >= p_date
    limit 1;

    if not found then
        raise exception 'FISCAL_PERIOD_NOT_FOUND';
    end if;
end;
$$;