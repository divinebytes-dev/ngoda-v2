/* =========================================================
 * MULTI-WALLET BALANCES REPORT
 * ========================================================= */

create or replace function public.get_multi_wallet_balances(
    p_user_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
    v_missing_currency text;
    v_result jsonb;
begin
    /*
     * Validate that every non-USD wallet has an active rate.
     */
    select lower(btrim(w.currency_code))
    into v_missing_currency
    from public.wallet w
    left join public.current_rates r
        on lower(btrim(r.code)) =
           lower(btrim(w.currency_code))
    where w.user_id = p_user_id
      and w.owner_type in (
          'merchant'::public."WalletOwnerType",
          'customer'::public."WalletOwnerType",
          'agent'::public."WalletOwnerType"
      )
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
            w.owner_type,
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
          and w.owner_type in (
              'merchant'::public."WalletOwnerType",
              'customer'::public."WalletOwnerType",
              'agent'::public."WalletOwnerType"
          )
    ),

    owner_summaries as (
        select
            owner_type,

            jsonb_agg(
                jsonb_build_object(
                    'currency_code',
                    currency_code,

                    'balance',
                    balance::text,

                    'usd_value',
                    usd_value::text
                )
                order by currency_code
            ) as wallet_balances,

            coalesce(
                sum(usd_value),
                0
            ) as total_usd_value

        from wallet_values
        group by owner_type
    )

    select jsonb_build_object(
        'merchantWallet',
        jsonb_build_object(
            'wallet_balances',
            coalesce(
                (
                    select s.wallet_balances
                    from owner_summaries s
                    where s.owner_type =
                        'merchant'::public."WalletOwnerType"
                ),
                '[]'::jsonb
            ),

            'total_usd_value',
            coalesce(
                (
                    select s.total_usd_value
                    from owner_summaries s
                    where s.owner_type =
                        'merchant'::public."WalletOwnerType"
                ),
                0
            )::text
        ),

        'customerWallet',
        jsonb_build_object(
            'wallet_balances',
            coalesce(
                (
                    select s.wallet_balances
                    from owner_summaries s
                    where s.owner_type =
                        'customer'::public."WalletOwnerType"
                ),
                '[]'::jsonb
            ),

            'total_usd_value',
            coalesce(
                (
                    select s.total_usd_value
                    from owner_summaries s
                    where s.owner_type =
                        'customer'::public."WalletOwnerType"
                ),
                0
            )::text
        ),

        'agentWallet',
        jsonb_build_object(
            'wallet_balances',
            coalesce(
                (
                    select s.wallet_balances
                    from owner_summaries s
                    where s.owner_type =
                        'agent'::public."WalletOwnerType"
                ),
                '[]'::jsonb
            ),

            'total_usd_value',
            coalesce(
                (
                    select s.total_usd_value
                    from owner_summaries s
                    where s.owner_type =
                        'agent'::public."WalletOwnerType"
                ),
                0
            )::text
        )
    )
    into v_result;

    return v_result;
end;
$$;

alter function public.get_multi_wallet_balances(text)
owner to postgres;

revoke all
on function public.get_multi_wallet_balances(text)
from public, anon, authenticated;

grant usage on schema public
to service_role;

grant execute
on function public.get_multi_wallet_balances(text)
to service_role;