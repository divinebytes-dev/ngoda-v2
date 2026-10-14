create or replace function public.fetch_my_current_gl_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_fiscal_year integer;
    v_period integer;

    v_data jsonb :=
        '{}'::jsonb;

    v_totals jsonb :=
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
            'finance',
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch trusted user context.
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
     * Fetch current fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    with current_snapshots as (
        select
            snapshot_record.gl_account_code,

            lower(
                snapshot_record.currency_code
            ) as currency_code,

            snapshot_record.opening_balance,
            snapshot_record.debit,
            snapshot_record.credit,
            snapshot_record.closing_balance
        from public.gl_balance_snapshot
            snapshot_record
        where snapshot_record.country_code =
              v_user.country_code

          and snapshot_record.fiscal_year =
              v_fiscal_year

          and snapshot_record.period =
              v_period

          and lower(
              snapshot_record.currency_code
          ) <> 'gold'
    ),

    /*
     * Include currencies that have either a current snapshot
     * or an earlier snapshot with a balance carried forward.
     */
    available_currencies as (
        select distinct
            lower(
                snapshot_record.currency_code
            ) as currency_code
        from public.gl_balance_snapshot
            snapshot_record
        where snapshot_record.country_code =
              v_user.country_code

          and lower(
              snapshot_record.currency_code
          ) <> 'gold'

          and (
              snapshot_record.fiscal_year <
                  v_fiscal_year

              or (
                  snapshot_record.fiscal_year =
                      v_fiscal_year

                  and snapshot_record.period <=
                      v_period
              )
          )
    ),

    /*
     * Find the latest snapshot before the current period for
     * every GL account and currency.
     */
    previous_snapshots as (
        select distinct on (
            snapshot_record.gl_account_code,
            lower(
                snapshot_record.currency_code
            )
        )
            snapshot_record.gl_account_code,

            lower(
                snapshot_record.currency_code
            ) as currency_code,

            snapshot_record.closing_balance
        from public.gl_balance_snapshot
            snapshot_record
        where snapshot_record.country_code =
              v_user.country_code

          and lower(
              snapshot_record.currency_code
          ) <> 'gold'

          and (
              snapshot_record.fiscal_year <
                  v_fiscal_year

              or (
                  snapshot_record.fiscal_year =
                      v_fiscal_year

                  and snapshot_record.period <
                      v_period
              )
          )
        order by
            snapshot_record.gl_account_code,

            lower(
                snapshot_record.currency_code
            ),

            snapshot_record.fiscal_year desc,

            snapshot_record.period desc
    ),

    /*
     * GL accounts of type token are excluded from the
     * standard fiat GL balance report.
     */
    display_gl_accounts as (
        select
            gl_account_record.code,
            coalesce(
                gl_account_record.description,
                ''
            ) as description,

            lower(
                gl_account_record.type::text
            ) as gl_type
        from public.gl_account
            gl_account_record
        where lower(
            gl_account_record.type::text
        ) <> 'token'

          and lower(
              gl_account_record.type::text
          ) in (
              'asset',
              'liability',
              'equity',
              'revenue',
              'expense'
          )
    ),

    base_rows as (
        select
            available_currency.currency_code,

            gl_account_record.code
                as gl_account_code,

            gl_account_record.description,

            gl_account_record.gl_type,

            case
                when current_snapshot.gl_account_code
                     is null
                then
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )

                when coalesce(
                    current_snapshot.opening_balance,
                    0
                ) = 0
                then
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )

                else
                    current_snapshot.opening_balance
            end as opening_balance,

            coalesce(
                current_snapshot.debit,
                0
            ) as debit,

            coalesce(
                current_snapshot.credit,
                0
            ) as credit,

            coalesce(
                current_snapshot.closing_balance,
                0
            ) as stored_closing_balance,

            current_snapshot.gl_account_code
                is not null
                as current_snapshot_exists
        from available_currencies
            available_currency
        cross join display_gl_accounts
            gl_account_record
        left join current_snapshots
            current_snapshot
          on current_snapshot.currency_code =
             available_currency.currency_code

         and current_snapshot.gl_account_code =
             gl_account_record.code
        left join previous_snapshots
            previous_snapshot
          on previous_snapshot.currency_code =
             available_currency.currency_code

         and previous_snapshot.gl_account_code =
             gl_account_record.code
    ),

    enriched_rows as (
        select
            base_row.currency_code
                as currency,

            base_row.gl_account_code,

            base_row.description,

            base_row.gl_type,

            base_row.opening_balance,

            base_row.debit,

            base_row.credit,

            case
                when not base_row.current_snapshot_exists
                then
                    base_row.opening_balance +
                    base_row.debit -
                    base_row.credit

                when base_row.stored_closing_balance = 0
                then
                    base_row.opening_balance +
                    base_row.debit -
                    base_row.credit

                else
                    base_row.stored_closing_balance
            end as closing_balance
        from base_rows
            base_row
    ),

    currency_results as (
        select
            enriched_row.currency,

            jsonb_build_object(
                'asset',
                coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'currency',
                            enriched_row.currency,

                            'gl_account_code',
                            enriched_row.gl_account_code,

                            'description',
                            enriched_row.description,

                            'gl_type',
                            enriched_row.gl_type,

                            'opening_balance',
                            enriched_row.opening_balance::text,

                            'debit',
                            enriched_row.debit::text,

                            'credit',
                            enriched_row.credit::text,

                            'closing_balance',
                            enriched_row.closing_balance::text
                        )
                        order by
                            enriched_row.gl_account_code
                    ) filter (
                        where enriched_row.gl_type =
                              'asset'
                    ),
                    '[]'::jsonb
                ),

                'liability',
                coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'currency',
                            enriched_row.currency,

                            'gl_account_code',
                            enriched_row.gl_account_code,

                            'description',
                            enriched_row.description,

                            'gl_type',
                            enriched_row.gl_type,

                            'opening_balance',
                            enriched_row.opening_balance::text,

                            'debit',
                            enriched_row.debit::text,

                            'credit',
                            enriched_row.credit::text,

                            'closing_balance',
                            enriched_row.closing_balance::text
                        )
                        order by
                            enriched_row.gl_account_code
                    ) filter (
                        where enriched_row.gl_type =
                              'liability'
                    ),
                    '[]'::jsonb
                ),

                'equity',
                coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'currency',
                            enriched_row.currency,

                            'gl_account_code',
                            enriched_row.gl_account_code,

                            'description',
                            enriched_row.description,

                            'gl_type',
                            enriched_row.gl_type,

                            'opening_balance',
                            enriched_row.opening_balance::text,

                            'debit',
                            enriched_row.debit::text,

                            'credit',
                            enriched_row.credit::text,

                            'closing_balance',
                            enriched_row.closing_balance::text
                        )
                        order by
                            enriched_row.gl_account_code
                    ) filter (
                        where enriched_row.gl_type =
                              'equity'
                    ),
                    '[]'::jsonb
                ),

                'revenue',
                coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'currency',
                            enriched_row.currency,

                            'gl_account_code',
                            enriched_row.gl_account_code,

                            'description',
                            enriched_row.description,

                            'gl_type',
                            enriched_row.gl_type,

                            'opening_balance',
                            enriched_row.opening_balance::text,

                            'debit',
                            enriched_row.debit::text,

                            'credit',
                            enriched_row.credit::text,

                            'closing_balance',
                            enriched_row.closing_balance::text
                        )
                        order by
                            enriched_row.gl_account_code
                    ) filter (
                        where enriched_row.gl_type =
                              'revenue'
                    ),
                    '[]'::jsonb
                ),

                'expense',
                coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'currency',
                            enriched_row.currency,

                            'gl_account_code',
                            enriched_row.gl_account_code,

                            'description',
                            enriched_row.description,

                            'gl_type',
                            enriched_row.gl_type,

                            'opening_balance',
                            enriched_row.opening_balance::text,

                            'debit',
                            enriched_row.debit::text,

                            'credit',
                            enriched_row.credit::text,

                            'closing_balance',
                            enriched_row.closing_balance::text
                        )
                        order by
                            enriched_row.gl_account_code
                    ) filter (
                        where enriched_row.gl_type =
                              'expense'
                    ),
                    '[]'::jsonb
                )
            ) as grouped_data,

            jsonb_build_object(
                'opening',
                sum(
                    enriched_row.opening_balance
                )::text,

                'debit',
                sum(
                    enriched_row.debit
                )::text,

                'credit',
                sum(
                    enriched_row.credit
                )::text,

                'closing',
                sum(
                    enriched_row.closing_balance
                )::text
            ) as currency_totals
        from enriched_rows
            enriched_row
        group by
            enriched_row.currency
    )

    select
        coalesce(
            jsonb_object_agg(
                currency_result.currency,
                currency_result.grouped_data
            ),
            '{}'::jsonb
        ),

        coalesce(
            jsonb_object_agg(
                currency_result.currency,
                currency_result.currency_totals
            ),
            '{}'::jsonb
        )
    into
        v_data,
        v_totals
    from currency_results
        currency_result;

    return jsonb_build_object(
        'fiscalYear',
        v_fiscal_year,

        'period',
        v_period,

        'totals',
        v_totals,

        'data',
        v_data
    );
end;
$function$;


revoke all on function
    public.fetch_my_current_gl_balances()
from public;

revoke all on function
    public.fetch_my_current_gl_balances()
from anon;

grant execute on function
    public.fetch_my_current_gl_balances()
to authenticated;