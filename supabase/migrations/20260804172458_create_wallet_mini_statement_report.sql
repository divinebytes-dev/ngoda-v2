/* =========================================================
 * WALLET MINI-STATEMENT REPORT
 * ========================================================= */

create or replace function public.get_last_wallet_transactions(
    p_user_id text,
    p_start_date timestamptz,
    p_end_date timestamptz,
    p_currency_code text default null,
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_page integer;
    v_skip integer;
    v_result jsonb;
begin
    if p_start_date is null then
        raise exception 'START_DATE_IS_REQUIRED';
    end if;

    if p_end_date is null then
        raise exception 'END_DATE_IS_REQUIRED';
    end if;

    if p_end_date < p_start_date then
        raise exception 'INVALID_DATE_RANGE';
    end if;

    if p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size < 1 or p_page_size > 100 then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    /*
     * Without a currency, always return page one
     * for every currency.
     */
    v_page :=
        case
            when p_currency_code is null
                 or btrim(p_currency_code) = ''
            then 1
            else p_page
        end;

    v_skip := (v_page - 1) * p_page_size;

    with user_wallets as (
        select
            w.id,
            lower(btrim(w.currency_code))
                as currency_code,
            coalesce(w.balance, 0)::numeric
                as balance
        from public.wallet w
        where w.user_id = p_user_id
          and (
              p_currency_code is null
              or btrim(p_currency_code) = ''
              or lower(btrim(w.currency_code)) =
                 lower(btrim(p_currency_code))
          )
    ),

    base_entries as (
        select
            e.id,
            e.wallet_id,
            e.document_number,
            e.transaction_type,
            coalesce(e.debit, 0)::numeric
                as debit,
            coalesce(e.credit, 0)::numeric
                as credit,
            (
                coalesce(e.credit, 0) -
                coalesce(e.debit, 0)
            )::numeric as net_amount,
            e.created_at,
            wallet.currency_code,
            wallet.balance as wallet_balance

        from public.wallet_entry e
        join user_wallets wallet
          on wallet.id = e.wallet_id

        where e.created_at >= p_start_date
          and e.created_at <= p_end_date
    ),

    ordered_entries as (
        select
            entry.*,

            row_number() over (
                partition by entry.currency_code
                order by
                    entry.created_at desc,
                    entry.id desc
            ) as currency_entry_number,

            entry.wallet_balance -
            coalesce(
                sum(entry.net_amount) over (
                    partition by entry.wallet_id
                    order by
                        entry.created_at desc,
                        entry.id desc
                    rows between
                        unbounded preceding
                        and 1 preceding
                ),
                0
            ) as running_balance

        from base_entries entry
    ),

    currency_totals as (
        select
            wallet.currency_code,
            sum(wallet.balance)::numeric
                as current_balance

        from user_wallets wallet
        group by wallet.currency_code
    ),

    entry_totals as (
        select
            entry.currency_code,
            count(*)::integer
                as total_entries,
            coalesce(sum(entry.debit), 0)
                as total_debit,
            coalesce(sum(entry.credit), 0)
                as total_credit

        from ordered_entries entry
        group by entry.currency_code
    ),

    currency_results as (
        select
            currency.currency_code,

            jsonb_build_object(
                'balance',
                currency.current_balance::text,

                'total_debit',
                coalesce(
                    totals.total_debit,
                    0
                )::text,

                'total_credit',
                coalesce(
                    totals.total_credit,
                    0
                )::text,

                /*
                 * Balance after reversing transactions
                 * newer than the requested page.
                 */
                'page_closing_balance',
                (
                    currency.current_balance -
                    coalesce(
                        (
                            select sum(entry.net_amount)
                            from ordered_entries entry
                            where entry.currency_code =
                                  currency.currency_code
                              and entry.currency_entry_number <=
                                  v_skip
                        ),
                        0
                    )
                )::text,

                /*
                 * Balance after reversing every transaction
                 * included on this page.
                 */
                'page_opening_balance',
                (
                    currency.current_balance -
                    coalesce(
                        (
                            select sum(entry.net_amount)
                            from ordered_entries entry
                            where entry.currency_code =
                                  currency.currency_code
                              and entry.currency_entry_number <=
                                  v_skip + p_page_size
                        ),
                        0
                    )
                )::text,

                'pagination',
                jsonb_build_object(
                    'page',
                    v_page,

                    'page_size',
                    p_page_size,

                    'total_entries',
                    coalesce(
                        totals.total_entries,
                        0
                    ),

                    'total_pages',
                    greatest(
                        1,
                        ceil(
                            coalesce(
                                totals.total_entries,
                                0
                            )::numeric /
                            p_page_size::numeric
                        )::integer
                    ),

                    'has_previous',
                    v_page > 1,

                    'has_next',
                    v_page <
                    greatest(
                        1,
                        ceil(
                            coalesce(
                                totals.total_entries,
                                0
                            )::numeric /
                            p_page_size::numeric
                        )::integer
                    )
                ),

                'transactions',
                coalesce(
                    (
                        select jsonb_agg(
                            jsonb_build_object(
                                'id',
                                entry.id::text,

                                'document_number',
                                entry.document_number,

                                'transaction_type',
                                entry.transaction_type::text,

                                'debit',
                                entry.debit::text,

                                'credit',
                                entry.credit::text,

                                'running_balance',
                                entry.running_balance::text,

                                'created_at',
                                entry.created_at
                            )
                            order by
                                entry.created_at desc,
                                entry.id desc
                        )
                        from ordered_entries entry
                        where entry.currency_code =
                              currency.currency_code
                          and entry.currency_entry_number >
                              v_skip
                          and entry.currency_entry_number <=
                              v_skip + p_page_size
                    ),
                    '[]'::jsonb
                )
            ) as statement

        from currency_totals currency

        left join entry_totals totals
          on totals.currency_code =
             currency.currency_code
    )

    select coalesce(
        jsonb_object_agg(
            currency_code,
            statement
            order by currency_code
        ),
        '{}'::jsonb
    )
    into v_result
    from currency_results;

    return v_result;
end;
$$;

revoke all
on function public.get_last_wallet_transactions(
    text,
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
)
from public, anon;

grant usage on schema public
to authenticated;

grant execute
on function public.get_last_wallet_transactions(
    text,
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
)
to authenticated;