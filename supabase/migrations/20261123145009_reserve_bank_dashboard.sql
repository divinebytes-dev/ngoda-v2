create or replace function public.get_my_reserve_bank_dashboard()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $function$
declare
    v_country text;
    v_current record;
    v_result jsonb;
begin
    select u.country_code into v_country
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) = 'reserve_bank';

    if nullif(btrim(v_country), '') is null then
        raise exception using errcode = '42501', message = 'RESERVE_BANK_TAX_NOT_AUTHORIZED';
    end if;

    select * into strict v_current
    from public.fetch_fiscal_period(v_country, statement_timestamp() at time zone 'UTC');

    with totals as (
        select lower(btrim(t.currency_code)) as currency,
               sum(t.tax_amount) as tax
        from public.government_tax_payable t
        where t.country_code = v_country
          and t.fiscal_year = v_current.fiscal_year
          and t.period = v_current.period
        group by lower(btrim(t.currency_code))
    ), valued as (
        select totals.*,
               case
                   when currency = 'usd' or tax = 0 then round(tax, 2)
                   when rate > 0 and rate::text not in ('NaN', 'Infinity')
                       then round(case when currency = 'gold' then tax * rate
                                       else tax / rate end, 2)
               end as usd_value
        from totals
        left join lateral (
            select case when count(*) = 1 then max(r.rate_to_usd) end as rate
            from public.current_rates r
            where lower(btrim(r.code)) = totals.currency and totals.currency <> 'usd'
        ) fx on true
    )
    select jsonb_build_object(
        'total_usd', case
            when count(usd_value) = count(*) then coalesce(sum(usd_value), 0.00)::text
        end,
        'currency_breakdown', coalesce(jsonb_agg(jsonb_build_object(
            'currency', currency,
            'tax', tax::text,
            'usd_value', usd_value::text
        ) order by currency), '[]'::jsonb)
    ) into v_result
    from valued;

    return v_result;
end;
$function$;

revoke all on function public.get_my_reserve_bank_dashboard() from public, anon, authenticated;
grant execute on function public.get_my_reserve_bank_dashboard() to authenticated;
