create or replace function public.fetch_my_trial_balance(
    p_start_date date default null,
    p_end_date date default null,
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
     * Both dates must either be supplied together or omitted.
     */
    if (
        p_start_date is null
        and p_end_date is not null
    ) or (
        p_start_date is not null
        and p_end_date is null
    ) then
        raise exception
            'START_AND_END_DATE_REQUIRED_TOGETHER';
    end if;

    if p_start_date is not null
       and p_end_date < p_start_date
    then
        raise exception
            'INVALID_REPORT_DATE_RANGE';
    end if;

    /*
     * Get the trusted user country from auth.uid().
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
     * Preserve the current fiscal-year behaviour.
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
     * Build the trial balance.
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

            coalesce(
                sum(
                    financial_entry_record.debit
                ),
                0
            ) as total_debit,

            coalesce(
                sum(
                    financial_entry_record.credit
                ),
                0
            ) as total_credit
        from public.financial_entry
            financial_entry_record
        left join public.gl_account
            gl_account_record
          on gl_account_record.code =
             financial_entry_record.gl_account_code
        where financial_entry_record.country_code =
              v_user.country_code

          and financial_entry_record.fiscal_year =
              v_fiscal_year

          /*
           * Apply the date range only when both dates exist.
           * The whole end date is included.
           */
          and (
              p_start_date is null
              or (
                  financial_entry_record.created_at >=
                      p_start_date::timestamptz

                  and financial_entry_record.created_at <
                      (
                          p_end_date +
                          interval '1 day'
                      )
              )
          )

          /*
           * Without a selected currency, exclude Gold.
           * When explicitly selected, use that currency.
           */
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
            lower(
                financial_entry_record.currency_code
            ),

            financial_entry_record.gl_account_code,

            gl_account_record.description
    ),

    currency_totals as (
        select
            grouped_entry.currency_code,

            sum(
                grouped_entry.total_debit
            ) as total_debit,

            sum(
                grouped_entry.total_credit
            ) as total_credit
        from grouped_entries
            grouped_entry
        group by
            grouped_entry.currency_code
    ),

    currency_results as (
        select
            currency_total.currency_code,

            coalesce(
                (
                    select jsonb_agg(
                        jsonb_build_object(
                            'gl_account_code',
                            grouped_entry.gl_account_code,

                            'gl_account_name',
                            grouped_entry.gl_account_name,

                            'total_debit',
                            grouped_entry.total_debit,

                            'total_credit',
                            grouped_entry.total_credit
                        )
                        order by
                            grouped_entry.gl_account_code
                    )
                    from grouped_entries
                        grouped_entry
                    where grouped_entry.currency_code =
                          currency_total.currency_code
                ),
                '[]'::jsonb
            ) as accounts,

            currency_total.total_debit,

            currency_total.total_credit
        from currency_totals
            currency_total
    )

    select coalesce(
        jsonb_object_agg(
            currency_result.currency_code,

            jsonb_build_object(
                'accounts',
                currency_result.accounts,

                'totals',
                jsonb_build_object(
                    'total_debit',
                    currency_result.total_debit,

                    'total_credit',
                    currency_result.total_credit,

                    'balanced',
                    currency_result.total_debit =
                        currency_result.total_credit
                )
            )
        ),
        '{}'::jsonb
    )
    into v_currencies
    from currency_results
        currency_result;

    return jsonb_build_object(
        'currencies',
        v_currencies
    );
end;
$function$;


revoke all on function public.fetch_my_trial_balance(
    date,
    date,
    text
)
from public;

revoke all on function public.fetch_my_trial_balance(
    date,
    date,
    text
)
from anon;

grant execute on function public.fetch_my_trial_balance(
    date,
    date,
    text
)
to authenticated;