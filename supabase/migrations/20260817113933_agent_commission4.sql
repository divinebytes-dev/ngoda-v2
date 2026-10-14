CREATE OR REPLACE FUNCTION public.build_my_accounts_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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

    v_kpi jsonb :=
        '{}'::jsonb;

    v_snapshot jsonb :=
        '{}'::jsonb;

    v_bank_net_result jsonb :=
        '{}'::jsonb;

    v_currencies jsonb :=
        '[]'::jsonb;

    v_agent_commission_settlements jsonb :=
        '[]'::jsonb;

    v_government_tax_settlements jsonb :=
        '[]'::jsonb;
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
     * enforce the Accounts role.
     */
    select user_record.*
    into v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
              auth.uid()::text

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'accounts'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'ACCOUNTS_NOT_AUTHORIZED';
    end if;

    /*
     * Current fiscal year.
     */
    select fiscal_period_record.fiscal_year
    into v_fiscal_year
    from public.fiscal_period_config
        fiscal_period_record
    where fiscal_period_record.country_code =
              v_user.country_code

      and fiscal_period_record.opening_date <=
              current_date

      and fiscal_period_record.closing_date >=
              current_date
    order by
        fiscal_period_record.fiscal_year desc,
        fiscal_period_record.period desc
    limit 1;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Calculate accounting totals by currency.
     */
    for v_row in
        select
            lower(
                btrim(
                    financial_entry_record.currency_code
                )
            ) as currency_code,

            coalesce(
                sum(
                    case
                        when gl_account_record.type::text =
                             'revenue'
                        then
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as revenue,

            coalesce(
                sum(
                    case
                        when gl_account_record.type::text =
                             'expense'
                        then
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as expenses,

            coalesce(
                sum(
                    case
                        when gl_account_record.type::text =
                             'asset'
                        then
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as assets,

            coalesce(
                sum(
                    case
                        when gl_account_record.type::text =
                             'liability'
                        then
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as liabilities,

            coalesce(
                sum(
                    case
                        when gl_account_record.type::text =
                             'equity'
                        then
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as equity,

            coalesce(
                sum(
                    case
                        when financial_entry_record.gl_account_code =
                             '1001000'
                        then
                            coalesce(
                                financial_entry_record.debit,
                                0
                            )
                            -
                            coalesce(
                                financial_entry_record.credit,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as bank_net

        from public.financial_entry
            financial_entry_record

        join public.gl_account
            gl_account_record
          on gl_account_record.code =
             financial_entry_record.gl_account_code

        where financial_entry_record.country_code =
                  v_user.country_code

          and financial_entry_record.fiscal_year =
                  v_fiscal_year

          and lower(
              btrim(
                  financial_entry_record.currency_code
              )
          ) <>
                  'gold'

        group by
            lower(
                btrim(
                    financial_entry_record.currency_code
                )
            )

        order by
            lower(
                btrim(
                    financial_entry_record.currency_code
                )
            )
    loop
        v_revenue :=
            coalesce(
                v_row.revenue,
                0
            );

        v_expenses :=
            coalesce(
                v_row.expenses,
                0
            );

        v_assets :=
            coalesce(
                v_row.assets,
                0
            );

        v_liabilities :=
            coalesce(
                v_row.liabilities,
                0
            );

        v_equity :=
            coalesce(
                v_row.equity,
                0
            );

        v_bank_net :=
            coalesce(
                v_row.bank_net,
                0
            );

        v_net_profit :=
            v_revenue -
            v_expenses;

        v_equity_with_profit :=
            v_equity +
            v_net_profit;

        /*
         * Convert balances to USD.
         *
         * USD is already in USD. Other fiat balances are
         * divided by rate_to_usd.
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
            select current_rate_record.rate_to_usd
            into v_rate
            from public.current_rates
                current_rate_record
            where lower(
                btrim(
                    current_rate_record.code
                )
            ) =
                v_row.currency_code
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_FOR_%',
                    upper(
                        v_row.currency_code
                    );
            end if;

            v_revenue_usd :=
                v_revenue /
                v_rate;

            v_expenses_usd :=
                v_expenses /
                v_rate;

            v_net_profit_usd :=
                v_net_profit /
                v_rate;

            v_assets_usd :=
                v_assets /
                v_rate;

            v_liabilities_usd :=
                v_liabilities /
                v_rate;

            v_equity_usd :=
                v_equity_with_profit /
                v_rate;
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
                        trim_scale(
                            v_revenue
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_revenue_usd
                        )::text
                    ),

                    'total_expenses',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_expenses
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_expenses_usd
                        )::text
                    ),

                    'net_profit',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_net_profit
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_net_profit_usd
                        )::text
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
                        trim_scale(
                            v_assets
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_assets_usd
                        )::text
                    ),

                    'liabilities',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_liabilities
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_liabilities_usd
                        )::text
                    ),

                    'equity',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_equity_with_profit
                        )::text,

                        'usd_value',
                        trim_scale(
                            v_equity_usd
                        )::text
                    )
                )
            );

        /*
         * Preserve bank_net as a JSON number, matching
         * toNumber() in the original code.
         */
        v_bank_net_result :=
            v_bank_net_result ||
            jsonb_build_object(
                v_row.currency_code,
                v_bank_net
            );
    end loop;

    /*
     * Supported active fiat currencies for the Accounts
     * user's country.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                supported_currency_record.currency_code,

                'symbol',
                supported_currency_record.symbol,

                'name',
                supported_currency_record.name,

                'is_active',
                supported_currency_record.is_active,

                'is_reporting',
                country_currency_record.is_reporting
            )
            order by
                supported_currency_record.currency_code
        ),
        '[]'::jsonb
    )
    into v_currencies
    from public.country_currencies
        country_currency_record

    join public.supported_currency
        supported_currency_record
      on lower(
          supported_currency_record.currency_code
      ) =
         lower(
             country_currency_record.currency_code
         )

    where country_currency_record.country_code =
              v_user.country_code

      and country_currency_record.is_active =
              true

      and supported_currency_record.is_active =
              true

      and supported_currency_record.currency_category =
              'fiat'::public."CurrencyCategory";

    /*
     * Fetch the latest Agent Commission settlement dates
     * for all commission currencies.
     */
    v_agent_commission_settlements :=
        public.fetch_my_last_agent_commission_settlement();

    /*
     * Fetch the latest Government Tax settlement dates
     * for all tax currencies.
     */
    v_government_tax_settlements :=
        public.fetch_my_last_government_tax_settlement();

    /*
     * Preserve all existing dashboard fields and add the
     * two settlement-date collections.
     */
    return jsonb_build_object(
        'kpi',
        v_kpi,

        'balance_sheet_snapshot',
        v_snapshot,

        'currencies',
        v_currencies,

        'bank_net',
        v_bank_net_result,

        'agent_commission_settlements',
        v_agent_commission_settlements,

        'government_tax_settlements',
        v_government_tax_settlements
    );
end;
$function$;