create or replace function public.build_my_accounts_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_fiscal_year integer;

    v_row record;
    v_rate numeric;

    v_revenue numeric;
    v_expenses numeric;
    v_net_profit numeric;

    v_assets numeric;
    v_liabilities numeric;
    v_equity numeric;
    v_equity_with_profit numeric;

    v_bank_net numeric;

    v_revenue_usd numeric;
    v_expenses_usd numeric;
    v_net_profit_usd numeric;

    v_assets_usd numeric;
    v_liabilities_usd numeric;
    v_equity_usd numeric;

    v_kpi jsonb := '{}'::jsonb;
    v_snapshot jsonb := '{}'::jsonb;
    v_bank_net_result jsonb := '{}'::jsonb;
    v_currencies jsonb := '[]'::jsonb;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Fetch the authenticated application user and
     * enforce the accounts role.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) = 'accounts'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'ACCOUNTS_NOT_AUTHORIZED';
    end if;

    /*
     * Current fiscal year.
     */
    select fp.fiscal_year
    into v_fiscal_year
    from public.fiscal_period_config fp
    where fp.country_code =
          v_user.country_code
      and fp.opening_date <= current_date
      and fp.closing_date >= current_date
    order by
        fp.fiscal_year desc,
        fp.period desc
    limit 1;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Calculate the accounting totals by currency.
     */
    for v_row in
        select
            lower(btrim(fe.currency_code))
                as currency_code,

            coalesce(
                sum(
                    case
                        when ga.type::text = 'revenue'
                        then
                            coalesce(fe.credit, 0) -
                            coalesce(fe.debit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as revenue,

            coalesce(
                sum(
                    case
                        when ga.type::text = 'expense'
                        then
                            coalesce(fe.debit, 0) -
                            coalesce(fe.credit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as expenses,

            coalesce(
                sum(
                    case
                        when ga.type::text = 'asset'
                        then
                            coalesce(fe.debit, 0) -
                            coalesce(fe.credit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as assets,

            coalesce(
                sum(
                    case
                        when ga.type::text = 'liability'
                        then
                            coalesce(fe.credit, 0) -
                            coalesce(fe.debit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as liabilities,

            coalesce(
                sum(
                    case
                        when ga.type::text = 'equity'
                        then
                            coalesce(fe.credit, 0) -
                            coalesce(fe.debit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as equity,

            coalesce(
                sum(
                    case
                        when fe.gl_account_code =
                             '1001000'
                        then
                            coalesce(fe.debit, 0) -
                            coalesce(fe.credit, 0)
                        else 0
                    end
                ),
                0
            )::numeric as bank_net

        from public.financial_entry fe

        join public.gl_account ga
          on ga.code =
             fe.gl_account_code

        where fe.country_code =
              v_user.country_code
          and fe.fiscal_year =
              v_fiscal_year
          and lower(btrim(fe.currency_code))
              <> 'gold'

        group by
            lower(btrim(fe.currency_code))

        order by
            lower(btrim(fe.currency_code))
    loop
        v_revenue :=
            coalesce(v_row.revenue, 0);

        v_expenses :=
            coalesce(v_row.expenses, 0);

        v_assets :=
            coalesce(v_row.assets, 0);

        v_liabilities :=
            coalesce(v_row.liabilities, 0);

        v_equity :=
            coalesce(v_row.equity, 0);

        v_bank_net :=
            coalesce(v_row.bank_net, 0);

        v_net_profit :=
            v_revenue - v_expenses;

        v_equity_with_profit :=
            v_equity + v_net_profit;

        /*
         * Convert balances to USD.
         *
         * USD is already in USD.
         * Other fiat balances are divided by rate_to_usd.
         */
        if v_row.currency_code = 'usd' then
            v_revenue_usd :=
                v_revenue;

            v_expenses_usd :=
                v_expenses;

            v_net_profit_usd :=
                v_net_profit;

            v_assets_usd :=
                v_assets;

            v_liabilities_usd :=
                v_liabilities;

            v_equity_usd :=
                v_equity_with_profit;
        else
            select cr.rate_to_usd
            into v_rate
            from public.current_rates cr
            where lower(btrim(cr.code)) =
                  v_row.currency_code
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_FOR_%',
                    upper(v_row.currency_code);
            end if;

            v_revenue_usd :=
                v_revenue / v_rate;

            v_expenses_usd :=
                v_expenses / v_rate;

            v_net_profit_usd :=
                v_net_profit / v_rate;

            v_assets_usd :=
                v_assets / v_rate;

            v_liabilities_usd :=
                v_liabilities / v_rate;

            v_equity_usd :=
                v_equity_with_profit / v_rate;
        end if;

        /*
         * KPI response.
         */
        v_kpi :=
            v_kpi ||
            jsonb_build_object(
                v_row.currency_code,
                jsonb_build_object(
                    'total_revenue',
                    jsonb_build_object(
                        'balance',
                        trim_scale(v_revenue)::text,
                        'usd_value',
                        trim_scale(v_revenue_usd)::text
                    ),

                    'total_expenses',
                    jsonb_build_object(
                        'balance',
                        trim_scale(v_expenses)::text,
                        'usd_value',
                        trim_scale(v_expenses_usd)::text
                    ),

                    'net_profit',
                    jsonb_build_object(
                        'balance',
                        trim_scale(v_net_profit)::text,
                        'usd_value',
                        trim_scale(v_net_profit_usd)::text
                    )
                )
            );

        /*
         * Balance-sheet snapshot.
         */
        v_snapshot :=
            v_snapshot ||
            jsonb_build_object(
                v_row.currency_code,
                jsonb_build_object(
                    'assets',
                    jsonb_build_object(
                        'balance',
                        trim_scale(v_assets)::text,
                        'usd_value',
                        trim_scale(v_assets_usd)::text
                    ),

                    'liabilities',
                    jsonb_build_object(
                        'balance',
                        trim_scale(v_liabilities)::text,
                        'usd_value',
                        trim_scale(v_liabilities_usd)::text
                    ),

                    'equity',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_equity_with_profit
                        )::text,
                        'usd_value',
                        trim_scale(v_equity_usd)::text
                    )
                )
            );

        /*
         * Preserve bank_net as a JSON number,
         * matching toNumber() in the original code.
         */
        v_bank_net_result :=
            v_bank_net_result ||
            jsonb_build_object(
                v_row.currency_code,
                v_bank_net
            );
    end loop;

    /*
     * Supported fiat currencies for the user's country.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                sc.currency_code,

                'symbol',
                sc.symbol,

                'name',
                sc.name,

                'is_active',
                sc.is_active,

                'is_reporting',
                cc.is_reporting
            )
            order by sc.currency_code
        ),
        '[]'::jsonb
    )
    into v_currencies
    from public.country_currencies cc
    join public.supported_currency sc
      on lower(sc.currency_code) =
         lower(cc.currency_code)
    where cc.country_code =
          v_user.country_code
      and cc.is_active = true
      and sc.is_active = true
      and sc.currency_category =
          'fiat'::public."CurrencyCategory";

    return jsonb_build_object(
        'kpi',
        v_kpi,

        'balance_sheet_snapshot',
        v_snapshot,

        'currencies',
        v_currencies,

        'bank_net',
        v_bank_net_result
    );
end;
$function$;