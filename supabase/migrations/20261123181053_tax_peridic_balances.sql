create or replace function public.get_my_tax_payable_periods(p_currency text)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
    v_country text;
    v_currency text := lower(btrim(p_currency));
    v_fiscal_year integer;
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

    if nullif(v_currency, '') is null then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_IS_REQUIRED';
    end if;

    select fp.fiscal_year
    into strict v_fiscal_year
    from public.fetch_fiscal_period(
        v_country,
        statement_timestamp() at time zone 'UTC'
    ) fp;

    return (
        select jsonb_build_object(
            'currency_code', v_currency,
            'fiscal_year', v_fiscal_year,
            'periods', coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'period', s.period,
                        'gross_amount', s.gross_amount::text,
                        'tax_amount', s.tax_amount::text,
                        'tax_rate', s.tax_rate::text
                    )
                    order by s.period
                ),
                '[]'::jsonb
            )
        )
        from public.government_tax_payable_snapshot s
        where s.country_code = v_country
          and s.fiscal_year = v_fiscal_year
          and lower(btrim(s.currency)) = v_currency
    );
end;
$function$;

revoke all on function public.get_my_tax_payable_periods(text)
    from public, anon, authenticated;

grant execute on function public.get_my_tax_payable_periods(text)
    to authenticated;