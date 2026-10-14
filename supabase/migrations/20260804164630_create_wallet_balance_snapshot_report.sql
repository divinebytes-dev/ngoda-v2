/* =========================================================
 * WALLET BALANCE SNAPSHOT REPORT
 * ========================================================= */

create or replace function public.get_wallet_balance_snapshot(
    p_user_id text,
    p_currency_code text,
    p_country_code text,
    p_wallet_owner public."WalletOwnerType"
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_fiscal_year integer;
    v_result jsonb;
begin
    /*
     * Fetch the current fiscal year.
     */
    select fp.fiscal_year
    into v_fiscal_year
    from public.fetch_fiscal_period(
        p_country_code
    ) fp
    limit 1;

    with snapshots as (
        select
            s.period,
            s.opening_balance,
            s.debit,
            s.credit,
            s.closing_balance

        from public.wallet_balance_snapshot s

        where s.user_id = p_user_id
          and s.wallet_owner = p_wallet_owner
          and lower(btrim(s.currency_code)) =
              lower(btrim(p_currency_code))
          and s.fiscal_year = v_fiscal_year
    ),

    period_values as (
        select
            generated_period.period,

            case
                when current_snapshot.period is not null
                then current_snapshot.opening_balance

                else coalesce(
                    previous_snapshot.closing_balance,
                    0
                )
            end as opening_balance,

            case
                when current_snapshot.period is not null
                then current_snapshot.debit
                else 0
            end as debit,

            case
                when current_snapshot.period is not null
                then current_snapshot.credit
                else 0
            end as credit,

            case
                when current_snapshot.period is not null
                then abs(
                    current_snapshot.closing_balance
                )

                else coalesce(
                    previous_snapshot.closing_balance,
                    0
                )
            end as closing_balance

        from generate_series(
            1,
            12
        ) as generated_period(period)

        left join snapshots current_snapshot
            on current_snapshot.period =
               generated_period.period

        left join lateral (
            select previous.closing_balance
            from snapshots previous
            where previous.period <
                  generated_period.period
            order by previous.period desc
            limit 1
        ) previous_snapshot on true
    )

    select jsonb_build_object(
        'currency_code',
        lower(btrim(p_currency_code)),

        'fiscalYear',
        v_fiscal_year,

        'periods',
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'period',
                    period,

                    'opening_balance',
                    opening_balance::text,

                    'debit',
                    debit::text,

                    'credit',
                    credit::text,

                    'closing_balance',
                    closing_balance::text
                )
                order by period
            ),
            '[]'::jsonb
        )
    )
    into v_result
    from period_values;

    return v_result;
end;
$$;

revoke all
on function public.get_wallet_balance_snapshot(
    text,
    text,
    text,
    public."WalletOwnerType"
)
from public, anon;

grant usage on schema public
to authenticated;

grant execute
on function public.get_wallet_balance_snapshot(
    text,
    text,
    text,
    public."WalletOwnerType"
)
to authenticated;