create or replace function public.fetch_my_profit_and_loss(
    p_start_date date,
    p_end_date date,
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

    v_currencies jsonb :=
        '{}'::jsonb;
begin
    /*
     * Authenticate and authorize.
     */
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

    /*
     * Validate report period.
     */
    if p_start_date is null then
        raise exception
            'START_DATE_REQUIRED';
    end if;

    if p_end_date is null then
        raise exception
            'END_DATE_REQUIRED';
    end if;

    if p_end_date < p_start_date then
        raise exception
            'INVALID_REPORT_DATE_RANGE';
    end if;

    /*
     * Fetch the authenticated user's trusted country.
     */
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

    /*
     * Gold is excluded from this fiat Profit and Loss report.
     */
    if v_currency_code = 'gold' then
        raise exception
            'GOLD_CURRENCY_NOT_ALLOWED';
    end if;

    /*
     * Preserve the existing report behaviour by using the
     * current fiscal year for the user's country.
     */
    select fiscal_period.fiscal_year
    into v_fiscal_year
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Build the Profit and Loss report.
     */
    with grouped_entries as (
        select
            lower(
                financial_entry_record.currency_code
            ) as currency_code,

            financial_entry_record.gl_account_code,

            coalesce(
                gl_account_record.description,
                ''
            ) as gl_account_name,

            lower(
                gl_account_record.type::text
            ) as account_type,

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
        join public.gl_account
            gl_account_record
          on gl_account_record.code =
             financial_entry_record.gl_account_code
        where financial_entry_record.country_code =
              v_user.country_code

          and financial_entry_record.fiscal_year =
              v_fiscal_year

          /*
           * Include the whole start and end dates.
           */
          and financial_entry_record.created_at >=
              p_start_date::timestamptz

          and financial_entry_record.created_at <
              (
                  p_end_date +
                  interval '1 day'
              )

          /*
           * Profit and Loss is fiat-only.
           */
          and lower(
              financial_entry_record.currency_code
          ) <> 'gold'

          and (
              v_currency_code is null
              or lower(
                  financial_entry_record.currency_code
              ) = v_currency_code
          )

          and lower(
              gl_account_record.type::text
          ) in (
              'revenue',
              'expense'
          )
        group by
            lower(
                financial_entry_record.currency_code
            ),

            financial_entry_record.gl_account_code,

            gl_account_record.description,

            lower(
                gl_account_record.type::text
            )
    ),

    calculated_entries as (
        select
            grouped_entry.currency_code,
            grouped_entry.gl_account_code,
            grouped_entry.gl_account_name,
            grouped_entry.account_type,

            case
                when grouped_entry.account_type =
                     'revenue'
                then
                    grouped_entry.credit -
                    grouped_entry.debit

                when grouped_entry.account_type =
                     'expense'
                then
                    grouped_entry.debit -
                    grouped_entry.credit

                else
                    0
            end as amount
        from grouped_entries
            grouped_entry
    ),

    currency_totals as (
        select
            calculated_entry.currency_code,

            coalesce(
                sum(
                    calculated_entry.amount
                ) filter (
                    where calculated_entry.account_type =
                          'revenue'
                ),
                0
            ) as total_revenue,

            coalesce(
                sum(
                    calculated_entry.amount
                ) filter (
                    where calculated_entry.account_type =
                          'expense'
                ),
                0
            ) as total_expense
        from calculated_entries
            calculated_entry
        group by
            calculated_entry.currency_code
    ),

    currency_results as (
        select
            currency_total.currency_code,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            calculated_entry.gl_account_code,

                            'gl_account_name',
                            calculated_entry.gl_account_name,

                            'amount',
                            calculated_entry.amount
                        )
                        order by
                            calculated_entry.gl_account_code
                    )
                    from calculated_entries
                        calculated_entry
                    where calculated_entry.currency_code =
                          currency_total.currency_code
                      and calculated_entry.account_type =
                          'revenue'
                ),
                '[]'::jsonb
            ) as revenue_entries,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            calculated_entry.gl_account_code,

                            'gl_account_name',
                            calculated_entry.gl_account_name,

                            'amount',
                            calculated_entry.amount
                        )
                        order by
                            calculated_entry.gl_account_code
                    )
                    from calculated_entries
                        calculated_entry
                    where calculated_entry.currency_code =
                          currency_total.currency_code
                      and calculated_entry.account_type =
                          'expense'
                ),
                '[]'::jsonb
            ) as expense_entries,

            currency_total.total_revenue,

            currency_total.total_expense,

            currency_total.total_revenue -
                currency_total.total_expense
                as net_income
        from currency_totals
            currency_total
    )

    select coalesce(
        jsonb_object_agg(
            currency_result.currency_code,

            jsonb_build_object(
                'revenue',
                currency_result.revenue_entries,

                'expense',
                currency_result.expense_entries,

                'totals',
                jsonb_build_object(
                    'totalRevenue',
                    currency_result.total_revenue,

                    'totalExpense',
                    currency_result.total_expense,

                    'netIncome',
                    currency_result.net_income
                )
            )
        ),
        '{}'::jsonb
    )
    into v_currencies
    from currency_results
        currency_result;

    return jsonb_build_object(
        'period',
        jsonb_build_object(
            'startDate',
            p_start_date,

            'endDate',
            p_end_date
        ),

        'currencies',
        v_currencies
    );
end;
$function$;


revoke all on function public.fetch_my_profit_and_loss(
    date,
    date,
    text
)
from public;

revoke all on function public.fetch_my_profit_and_loss(
    date,
    date,
    text
)
from anon;

grant execute on function public.fetch_my_profit_and_loss(
    date,
    date,
    text
)
to authenticated;