create or replace function public.get_my_tax_payable_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    v_country text;
    v_fiscal_year integer;
    v_result jsonb;
begin
    select u.country_code
    into v_country
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) = 'reserve_bank';

    if nullif(btrim(v_country), '') is null then
        raise exception using
            errcode = '42501',
            message = 'RESERVE_BANK_TAX_NOT_AUTHORIZED';
    end if;

    select fp.fiscal_year
    into strict v_fiscal_year
    from public.fetch_fiscal_period(
        v_country,
        statement_timestamp() at time zone 'UTC'
    ) fp;

    with totals as (
        select
            lower(btrim(s.currency)) as currency,
            sum(s.tax_amount) as tax_amount
        from public.government_tax_payable_snapshot s
        where s.country_code = v_country
          and s.fiscal_year = v_fiscal_year
        group by lower(btrim(s.currency))
    ), valued as (
        select
            t.currency,
            t.tax_amount,
            case
                when t.currency = 'usd' or t.tax_amount = 0
                    then round(t.tax_amount, 2)
                when fx.rate > 0
                     and fx.rate::text not in ('NaN', 'Infinity')
                    then round(
                        case
                            when t.currency = 'gold' then t.tax_amount * fx.rate
                            else t.tax_amount / fx.rate
                        end,
                        2
                    )
            end as usd_value
        from totals t
        left join lateral (
            select case when count(*) = 1 then max(r.rate_to_usd) end as rate
            from public.current_rates r
            where lower(btrim(r.code)) = t.currency
              and t.currency <> 'usd'
        ) fx on true
    )
    select jsonb_build_object(
        'fiscal_year', v_fiscal_year,
        'total_usd', case
            when count(usd_value) = count(*)
                then coalesce(sum(usd_value), 0.00)::text
        end,
        'currency_breakdown', coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'currency', currency,
                    'tax_amount', tax_amount::text,
                    'usd_value', usd_value::text
                )
                order by currency
            ),
            '[]'::jsonb
        )
    )
    into v_result
    from valued;

    return v_result;
end;
$function$;

revoke all on function public.get_my_tax_payable_summary()
    from public, anon, authenticated;

grant execute on function public.get_my_tax_payable_summary()
    to authenticated;