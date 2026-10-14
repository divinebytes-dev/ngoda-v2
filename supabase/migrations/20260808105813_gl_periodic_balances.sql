create or replace function public.fetch_my_gl_periodic_balances(
    p_gl_account_code text,
    p_currency_code text default 'usd'
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_gl_account_code text;
    v_currency_code text;

    v_description text;

    v_fiscal_year integer;

    v_periods jsonb :=
        '[]'::jsonb;
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
            'finance',
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate parameters.
     */
    v_gl_account_code :=
        nullif(
            btrim(p_gl_account_code),
            ''
        );

    if v_gl_account_code is null then
        raise exception
            'GL_ACCOUNT_CODE_REQUIRED';
    end if;

    v_currency_code :=
        lower(
            coalesce(
                nullif(
                    btrim(p_currency_code),
                    ''
                ),
                'usd'
            )
        );

    /*
     * Fetch the authenticated user's country.
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

    /*
     * Validate the GL account and fetch its description.
     */
    select coalesce(
        gl_account_record.description,
        ''
    )
    into v_description
    from public.gl_account
        gl_account_record
    where gl_account_record.code =
          v_gl_account_code;

    if not found then
        raise exception
            'GL_ACCOUNT_NOT_FOUND_%',
            v_gl_account_code;
    end if;

    /*
     * Fetch the current fiscal year.
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
     * Generate all twelve fiscal periods.
     *
     * When a period has no snapshot, the latest earlier
     * closing balance in the same fiscal year is carried
     * forward.
     */
    with fiscal_periods as (
        select generate_series(
            1,
            12
        )::integer as period
    ),

    period_balances as (
        select
            fiscal_period.period,

            current_snapshot.gl_account_code
                is not null
                as snapshot_exists,

            case
                when current_snapshot.gl_account_code
                     is not null
                then
                    current_snapshot.opening_balance

                else
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )
            end as opening_balance,

            coalesce(
                current_snapshot.debit,
                0
            ) as debit,

            coalesce(
                current_snapshot.credit,
                0
            ) as credit,

            case
                when current_snapshot.gl_account_code
                     is not null
                then
                    abs(
                        current_snapshot.closing_balance
                    )

                else
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )
            end as closing_balance
        from fiscal_periods
            fiscal_period
        left join public.gl_balance_snapshot
            current_snapshot
          on current_snapshot.country_code =
             v_user.country_code

         and current_snapshot.gl_account_code =
             v_gl_account_code

         and lower(
             current_snapshot.currency_code
         ) =
             v_currency_code

         and current_snapshot.fiscal_year =
             v_fiscal_year

         and current_snapshot.period =
             fiscal_period.period

        left join lateral (
            select
                previous_record.closing_balance
            from public.gl_balance_snapshot
                previous_record
            where previous_record.country_code =
                  v_user.country_code

              and previous_record.gl_account_code =
                  v_gl_account_code

              and lower(
                  previous_record.currency_code
              ) =
                  v_currency_code

              and previous_record.fiscal_year =
                  v_fiscal_year

              and previous_record.period <
                  fiscal_period.period
            order by
                previous_record.period desc
            limit 1
        ) as previous_snapshot
          on true
    )

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'period',
                period_balance.period,

                'opening_balance',
                period_balance.opening_balance::text,

                'debit',
                period_balance.debit::text,

                'credit',
                period_balance.credit::text,

                'closing_balance',
                period_balance.closing_balance::text
            )
            order by
                period_balance.period
        ),
        '[]'::jsonb
    )
    into v_periods
    from period_balances
        period_balance;

    return jsonb_build_object(
        'gl_account_code',
        v_gl_account_code,

        'description',
        v_description,

        'fiscalYear',
        v_fiscal_year,

        'periods',
        v_periods
    );
end;
$function$;


revoke all on function
    public.fetch_my_gl_periodic_balances(
        text,
        text
    )
from public;

revoke all on function
    public.fetch_my_gl_periodic_balances(
        text,
        text
    )
from anon;

grant execute on function
    public.fetch_my_gl_periodic_balances(
        text,
        text
    )
to authenticated;