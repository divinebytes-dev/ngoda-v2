create or replace function public.get_my_reserve_bank_dashboard()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
    v_country text;
    v_current record;
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

    select *
    into strict v_current
    from public.fetch_fiscal_period(
        v_country,
        statement_timestamp() at time zone 'UTC'
    );

    with totals as (
        select
            lower(btrim(s.currency)) as currency,
            s.tax_amount as tax
        from public.government_tax_payable_snapshot s
        where s.country_code = v_country
          and s.fiscal_year = v_current.fiscal_year
          and s.period = v_current.period
    ), valued as (
        select
            totals.currency,
            totals.tax,
            case
                when totals.currency = 'usd' or totals.tax = 0
                    then round(totals.tax, 2)
                when fx.rate > 0
                     and fx.rate::text not in ('NaN', 'Infinity')
                    then round(
                        case
                            when totals.currency = 'gold' then totals.tax * fx.rate
                            else totals.tax / fx.rate
                        end,
                        2
                    )
            end as usd_value
        from totals
        left join lateral (
            select case when count(*) = 1 then max(r.rate_to_usd) end as rate
            from public.current_rates r
            where lower(btrim(r.code)) = totals.currency
              and totals.currency <> 'usd'
        ) fx on true
    )
    select jsonb_build_object(
        'total_usd', case
            when count(usd_value) = count(*)
                then coalesce(sum(usd_value), 0.00)::text
        end,
        'currency_breakdown', coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'currency', currency,
                    'tax', tax::text,
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