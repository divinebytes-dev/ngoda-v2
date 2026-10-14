drop function if exists public.fetch_all_transaction_configs(
    text,
    text
);

create function public.fetch_all_transaction_configs(
    p_country_code text
)
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
as $$
begin
    return query
    select
        lower(f.transaction_type::text),
        lower(f.currency_code),
        coalesce(f.rate, 0)::numeric,
        f.fixed_amount::numeric,
        f.min_amount::numeric,
        f.max_amount::numeric
    from public.transaction_type_fee_config f
    where f.country_code = p_country_code
      and f.is_active = true;

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
    where t.country_code = p_country_code
      and t.is_active = true;

    return query
    select *
    from public.fetch_spread_by_direction(
        'buy'::public."SpreadDirection",
        'gold'::public."AssetType"
    );

    return query
    select *
    from public.fetch_spread_by_direction(
        'sell'::public."SpreadDirection",
        'gold'::public."AssetType"
    );
end;
$$;