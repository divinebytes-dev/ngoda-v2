create or replace function public.fetch_my_balance_sheet(
    p_as_of_date date,
    p_currency_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_currency_code text;
    v_fiscal_year integer;
    v_currencies jsonb := '{}'::jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_as_of_date is null then
        raise exception
            'AS_OF_DATE_REQUIRED';
    end if;

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    select fiscal_period.fiscal_year
    into v_fiscal_year
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    with balance_rows as (
        select
            financial_entry_record.gl_account_code,

            lower(
                financial_entry_record.currency_code
            ) as currency_code,

            coalesce(
                sum(
                    financial_entry_record.debit
                ),
                0
            ) as debit,

            coalesce(
                sum(
                    financial_entry_record.credit
                ),
                0
            ) as credit
        from public.financial_entry
            financial_entry_record
        where financial_entry_record.country_code =
              v_user.country_code

          and financial_entry_record.fiscal_year =
              v_fiscal_year

          and financial_entry_record.created_at <
              (
                  p_as_of_date +
                  interval '1 day'
              )

          and (
              (
                  v_currency_code is null
                  and lower(
                      financial_entry_record.currency_code
                  ) <> 'gold'
              )
              or
              (
                  v_currency_code is not null
                  and lower(
                      financial_entry_record.currency_code
                  ) =
                      v_currency_code
              )
          )
        group by
            financial_entry_record.gl_account_code,

            lower(
                financial_entry_record.currency_code
            )
    ),

    calculated_balances as (
        select
            balance_row.currency_code,

            balance_row.gl_account_code,

            coalesce(
                gl_account_record.description,
                ''
            ) as gl_account_name,

            lower(
                gl_account_record.type::text
            ) as account_type,

            case
                when lower(
                    gl_account_record.type::text
                ) in (
                    'asset',
                    'expense'
                )
                then
                    balance_row.debit -
                    balance_row.credit

                else
                    balance_row.credit -
                    balance_row.debit
            end as balance
        from balance_rows balance_row
        join public.gl_account
            gl_account_record
          on gl_account_record.code =
             balance_row.gl_account_code
    ),

    non_zero_balances as (
        select calculated_balance.*
        from calculated_balances
            calculated_balance
        where calculated_balance.balance <> 0
    ),

    currency_totals as (
        select
            calculated_balance.currency_code,

            coalesce(
                sum(
                    calculated_balance.balance
                ) filter (
                    where calculated_balance.account_type =
                          'asset'
                ),
                0
            ) as assets,

            coalesce(
                sum(
                    calculated_balance.balance
                ) filter (
                    where calculated_balance.account_type =
                          'liability'
                ),
                0
            ) as liabilities,

            coalesce(
                sum(
                    calculated_balance.balance
                ) filter (
                    where calculated_balance.account_type =
                          'equity'
                ),
                0
            ) as existing_equity,

            coalesce(
                sum(
                    calculated_balance.balance
                ) filter (
                    where calculated_balance.account_type =
                          'revenue'
                ),
                0
            ) as revenue,

            coalesce(
                sum(
                    calculated_balance.balance
                ) filter (
                    where calculated_balance.account_type =
                          'expense'
                ),
                0
            ) as expenses
        from non_zero_balances
            calculated_balance
        group by
            calculated_balance.currency_code
    ),

    statement_rows as (
        select
            calculated_balance.currency_code,
            calculated_balance.gl_account_code,
            calculated_balance.gl_account_name,
            calculated_balance.account_type,
            calculated_balance.balance
        from non_zero_balances
            calculated_balance
        where calculated_balance.account_type
              in (
                  'asset',
                  'liability',
                  'equity'
              )

        union all

        select
            currency_total.currency_code,
            '5003000'::text,
            'Current Year Profit'::text,
            'equity'::text,
            currency_total.revenue -
                currency_total.expenses
        from currency_totals
            currency_total
        where (
            currency_total.revenue -
            currency_total.expenses
        ) <> 0
    ),

    currency_results as (
        select
            currency_total.currency_code,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            statement_row.gl_account_code,

                            'gl_account_name',
                            statement_row.gl_account_name,

                            'balance',
                            statement_row.balance
                        )
                        order by
                            statement_row.gl_account_code
                    )
                    from statement_rows
                        statement_row
                    where statement_row.currency_code =
                          currency_total.currency_code
                      and statement_row.account_type =
                          'asset'
                ),
                '[]'::jsonb
            ) as asset_entries,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            statement_row.gl_account_code,

                            'gl_account_name',
                            statement_row.gl_account_name,

                            'balance',
                            statement_row.balance
                        )
                        order by
                            statement_row.gl_account_code
                    )
                    from statement_rows
                        statement_row
                    where statement_row.currency_code =
                          currency_total.currency_code
                      and statement_row.account_type =
                          'liability'
                ),
                '[]'::jsonb
            ) as liability_entries,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            statement_row.gl_account_code,

                            'gl_account_name',
                            statement_row.gl_account_name,

                            'balance',
                            statement_row.balance
                        )
                        order by
                            statement_row.gl_account_code
                    )
                    from statement_rows
                        statement_row
                    where statement_row.currency_code =
                          currency_total.currency_code
                      and statement_row.account_type =
                          'equity'
                ),
                '[]'::jsonb
            ) as equity_entries,

            currency_total.assets
                as total_assets,

            currency_total.liabilities
                as total_liabilities,

            currency_total.existing_equity +
                currency_total.revenue -
                currency_total.expenses
                as total_equity,

            currency_total.revenue,

            currency_total.expenses
        from currency_totals
            currency_total
    )

    select coalesce(
        jsonb_object_agg(
            currency_result.currency_code,

            jsonb_build_object(
                'assets',
                currency_result.asset_entries,

                'liabilities',
                currency_result.liability_entries,

                'equity',
                currency_result.equity_entries,

                'totals',
                jsonb_build_object(
                    'assets',
                    currency_result.total_assets,

                    'liabilities',
                    currency_result.total_liabilities,

                    'equity',
                    currency_result.total_equity,

                    'balanced',
                    abs(
                        currency_result.total_assets -
                        (
                            currency_result.total_liabilities +
                            currency_result.total_equity
                        )
                    ) < 0.0001
                ),

                'revenue',
                currency_result.revenue,

                'expenses',
                currency_result.expenses
            )
        ),
        '{}'::jsonb
    )
    into v_currencies
    from currency_results
        currency_result;

    return jsonb_build_object(
        'asOfDate',
        p_as_of_date,

        'currencies',
        v_currencies
    );
end;
$function$;


revoke all on function public.fetch_my_balance_sheet(
    date,
    text
)
from public;

revoke all on function public.fetch_my_balance_sheet(
    date,
    text
)
from anon;

grant execute on function public.fetch_my_balance_sheet(
    date,
    text
)
to authenticated;