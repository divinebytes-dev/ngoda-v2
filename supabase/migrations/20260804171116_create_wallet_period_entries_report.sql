/* =========================================================
 * FETCH USER WALLET
 * ========================================================= */

create or replace function public.fetch_wallet(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType"
)
returns public.wallet
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_wallet public.wallet%rowtype;
begin
    select w.*
    into v_wallet
    from public.wallet w
    where w.user_id = p_user_id
      and w.owner_type = p_wallet_owner
      and lower(btrim(w.currency_code)) =
          lower(btrim(p_currency_code))
    limit 1;

    if not found then
        raise exception 'USER_WALLET_NOT_FOUND';
    end if;

    return v_wallet;
end;
$$;


/* =========================================================
 * FETCH OPENING WALLET SNAPSHOT
 * ========================================================= */

create or replace function public.fetch_opening_wallet_snapshot(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer
)
returns table (
    user_id text,
    currency_code text,
    wallet_owner public."WalletOwnerType",
    fiscal_year integer,
    period integer,
    opening_balance numeric,
    debit numeric,
    credit numeric,
    closing_balance numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
    v_snapshot
        public.wallet_balance_snapshot%rowtype;
begin
    /*
     * Requested period snapshot.
     */
    select s.*
    into v_snapshot
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and lower(btrim(s.currency_code)) =
          lower(btrim(p_currency_code))
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period
    limit 1;

    if found then
        return query
        select
            v_snapshot.user_id,
            v_snapshot.currency_code,
            v_snapshot.wallet_owner,
            v_snapshot.fiscal_year,
            v_snapshot.period,
            coalesce(v_snapshot.opening_balance, 0),
            coalesce(v_snapshot.debit, 0),
            coalesce(v_snapshot.credit, 0),
            coalesce(v_snapshot.closing_balance, 0);

        return;
    end if;

    /*
     * Latest previous period in the same fiscal year.
     */
    select s.*
    into v_snapshot
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and lower(btrim(s.currency_code)) =
          lower(btrim(p_currency_code))
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
    order by s.period desc
    limit 1;

    /*
     * Latest snapshot from a previous fiscal year.
     */
    if not found then
        select s.*
        into v_snapshot
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and lower(btrim(s.currency_code)) =
              lower(btrim(p_currency_code))
          and s.wallet_owner = p_wallet_owner
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    if found then
        /*
         * Carry the previous closing balance forward.
         */
        return query
        select
            p_user_id,
            lower(btrim(p_currency_code)),
            p_wallet_owner,
            p_fiscal_year,
            p_period,
            coalesce(v_snapshot.closing_balance, 0),
            0::numeric,
            0::numeric,
            coalesce(v_snapshot.closing_balance, 0);

        return;
    end if;

    /*
     * No current or previous snapshot.
     */
    return query
    select
        p_user_id,
        lower(btrim(p_currency_code)),
        p_wallet_owner,
        p_fiscal_year,
        p_period,
        0::numeric,
        0::numeric,
        0::numeric,
        0::numeric;
end;
$$;


/* =========================================================
 * WALLET PERIOD ENTRIES REPORT
 * ========================================================= */

create or replace function public.get_wallet_period_entries(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer,
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
    v_wallet public.wallet%rowtype;

    v_opening_balance numeric := 0;
    v_closing_balance numeric := 0;

    v_total_entries integer := 0;
    v_total_debit numeric := 0;
    v_total_credit numeric := 0;

    v_calculated_closing numeric := 0;
    v_difference numeric := 0;
    v_balanced boolean := false;

    v_skip integer;
    v_total_pages integer;

    v_page_opening numeric := 0;
    v_page_closing numeric := 0;

    v_entries jsonb := '[]'::jsonb;
begin
    if p_fiscal_year is null then
        raise exception 'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception 'PERIOD_IS_REQUIRED';
    end if;

    if p_period < 1 or p_period > 12 then
        raise exception 'INVALID_PERIOD';
    end if;

    if p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size < 1 or p_page_size > 100 then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    v_skip := (p_page - 1) * p_page_size;

    v_wallet := public.fetch_wallet(
        p_user_id,
        p_currency_code,
        p_wallet_owner
    );

    select
        snapshot.opening_balance,
        snapshot.closing_balance
    into
        v_opening_balance,
        v_closing_balance
    from public.fetch_opening_wallet_snapshot(
        p_user_id,
        p_currency_code,
        v_wallet.owner_type,
        p_fiscal_year,
        p_period
    ) snapshot;

    /*
     * Period totals.
     */
    select
        count(*)::integer,
        coalesce(sum(coalesce(e.debit, 0)), 0),
        coalesce(sum(coalesce(e.credit, 0)), 0)
    into
        v_total_entries,
        v_total_debit,
        v_total_credit
    from public.wallet_entry e
    where e.wallet_id = v_wallet.id
      and lower(btrim(e.currency_code)) =
          lower(btrim(p_currency_code))
      and e.fiscal_year = p_fiscal_year
      and e.period = p_period;

    /*
     * Calculate the balance immediately before this page.
     */
    select
        v_opening_balance +
        coalesce(
            sum(
                previous.credit -
                previous.debit
            ),
            0
        )
    into v_page_opening
    from (
        select
            coalesce(e.debit, 0) as debit,
            coalesce(e.credit, 0) as credit
        from public.wallet_entry e
        where e.wallet_id = v_wallet.id
          and lower(btrim(e.currency_code)) =
              lower(btrim(p_currency_code))
          and e.fiscal_year = p_fiscal_year
          and e.period = p_period
        order by
            e.created_at asc,
            e.id asc
        limit v_skip
    ) previous;

    /*
     * Build the requested page and calculate each running balance.
     */
    with ordered_entries as (
        select
            e.id,
            e.document_number,
            e.transaction_type,
            coalesce(e.debit, 0) as debit,
            coalesce(e.credit, 0) as credit,
            e.created_at,

            row_number() over (
                order by
                    e.created_at asc,
                    e.id asc
            ) as entry_number,

            sum(
                coalesce(e.credit, 0) -
                coalesce(e.debit, 0)
            ) over (
                order by
                    e.created_at asc,
                    e.id asc
                rows between
                    unbounded preceding
                    and current row
            ) as running_movement

        from public.wallet_entry e
        where e.wallet_id = v_wallet.id
          and lower(btrim(e.currency_code)) =
              lower(btrim(p_currency_code))
          and e.fiscal_year = p_fiscal_year
          and e.period = p_period
    ),

    paged_entries as (
        select *
        from ordered_entries
        where entry_number > v_skip
          and entry_number <=
              v_skip + p_page_size
    )

    select
        coalesce(
            jsonb_agg(
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
                    (
                        v_opening_balance +
                        entry.running_movement
                    )::text,

                    'created_at',
                    entry.created_at
                )
                order by entry.entry_number
            ),
            '[]'::jsonb
        ),

        coalesce(
            (
                array_agg(
                    v_opening_balance +
                    entry.running_movement
                    order by
                        entry.entry_number desc
                )
            )[1],
            v_page_opening
        )

    into
        v_entries,
        v_page_closing

    from paged_entries entry;

    v_calculated_closing :=
        v_opening_balance +
        v_total_credit -
        v_total_debit;

    v_difference :=
        v_calculated_closing -
        v_closing_balance;

    v_balanced :=
        abs(v_difference) <= 0.000001;

    v_total_pages :=
        case
            when v_total_entries = 0 then 1
            else ceil(
                v_total_entries::numeric /
                p_page_size::numeric
            )::integer
        end;

    return jsonb_build_object(
        'currency_code',
        lower(btrim(p_currency_code)),

        'fiscal_year',
        p_fiscal_year,

        'gl_account_code',
        '',

        'description',
        '',

        'period',
        p_period,

        'difference',
        v_difference::text,

        'balanced',
        v_balanced,

        'opening_balance',
        v_opening_balance::text,

        'total_debit',
        v_total_debit::text,

        'total_credit',
        v_total_credit::text,

        'calculated_closing_balance',
        v_calculated_closing::text,

        'closing_balance',
        v_closing_balance::text,

        'page_opening_balance',
        v_page_opening::text,

        'page_closing_balance',
        v_page_closing::text,

        'pagination',
        jsonb_build_object(
            'page',
            p_page,

            'page_size',
            p_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            p_page > 1,

            'has_next',
            p_page < v_total_pages
        ),

        'entries',
        v_entries
    );
end;
$$;


/* =========================================================
 * PERMISSIONS
 * ========================================================= */

revoke all
on function public.fetch_wallet(
    text,
    text,
    public."WalletOwnerType"
)
from public, anon;

revoke all
on function public.fetch_opening_wallet_snapshot(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer
)
from public, anon;

revoke all
on function public.get_wallet_period_entries(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
)
from public, anon;

grant usage on schema public
to authenticated;

grant execute
on function public.fetch_wallet(
    text,
    text,
    public."WalletOwnerType"
)
to authenticated;

grant execute
on function public.fetch_opening_wallet_snapshot(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer
)
to authenticated;

grant execute
on function public.get_wallet_period_entries(
    text,
    text,
    public."WalletOwnerType",
    integer,
    integer,
    integer,
    integer
)
to authenticated;