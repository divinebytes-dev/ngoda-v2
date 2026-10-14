/* =========================================================
 * SINGLE WALLET BALANCES REPORT
 * ========================================================= */

create or replace function public.get_wallet_balances(
    p_user_id text
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_missing_currency text;
    v_result jsonb;
begin
    /*
     * Ensure every non-USD wallet has a valid exchange rate.
     */
    select lower(btrim(w.currency_code))
    into v_missing_currency
    from public.wallet w
    left join public.current_rates r
        on lower(btrim(r.code)) =
           lower(btrim(w.currency_code))
    where w.user_id = p_user_id
      and lower(btrim(w.currency_code)) <> 'usd'
      and (
          r.code is null
          or r.rate_to_usd is null
          or r.rate_to_usd <= 0
      )
    limit 1;

    if found then
        raise exception
            'MISSING_RATE_FOR_CURRENCY_%',
            upper(v_missing_currency);
    end if;

    with wallet_values as (
        select
            w.id as wallet_id,

            lower(btrim(w.currency_code))
                as currency_code,

            coalesce(w.balance, 0)::numeric
                as balance,

            case
                when lower(btrim(w.currency_code)) = 'usd'
                then coalesce(w.balance, 0)::numeric

                when lower(btrim(w.currency_code)) = 'gold'
                then
                    coalesce(w.balance, 0)::numeric *
                    r.rate_to_usd::numeric

                else
                    coalesce(w.balance, 0)::numeric /
                    r.rate_to_usd::numeric
            end as usd_value

        from public.wallet w
        left join public.current_rates r
            on lower(btrim(r.code)) =
               lower(btrim(w.currency_code))

        where w.user_id = p_user_id
    )

    select jsonb_build_object(
        'balances',
        coalesce(
            jsonb_object_agg(
                currency_code,
                jsonb_build_object(
                    'balance',
                    balance::text,

                    'usd_value',
                    usd_value::text
                )
                order by currency_code, wallet_id
            ),
            '{}'::jsonb
        )
    )
    into v_result
    from wallet_values;

    return v_result;
end;
$$;

revoke all
on function public.get_wallet_balances(text)
from public, anon;

grant usage on schema public
to authenticated;

grant execute
on function public.get_wallet_balances(text)
to authenticated;