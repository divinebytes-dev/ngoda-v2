BEGIN;

-- 1. Add blockchain_code if it does not exist.
ALTER TABLE public.wallet_entry
ADD COLUMN IF NOT EXISTS blockchain_code text;

-- 2. Temporarily disable the update prevention trigger.
ALTER TABLE public.wallet_entry
DISABLE TRIGGER wallet_entry_no_update;

-- 3. Assign Gnosis to all existing GOLD entries.
UPDATE public.wallet_entry
SET blockchain_code = 'gnosis'
WHERE lower(btrim(currency_code)) = 'gold'
  AND blockchain_code IS DISTINCT FROM 'gnosis';

-- 4. Ensure fiat entries remain blockchain-independent.
UPDATE public.wallet_entry
SET blockchain_code = NULL
WHERE lower(btrim(currency_code)) <> 'gold'
  AND blockchain_code IS NOT NULL;

-- 5. Re-enable the update prevention trigger.
ALTER TABLE public.wallet_entry
ENABLE TRIGGER wallet_entry_no_update;

-- 6. Create the reporting index.
CREATE INDEX IF NOT EXISTS wallet_entry_blockchain_period_idx
ON public.wallet_entry (
    wallet_id,
    blockchain_code,
    fiscal_year,
    period,
    created_at,
    id
);

COMMIT;


CREATE OR REPLACE FUNCTION public.fetch_wallet(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_blockchain_code text DEFAULT NULL
)
RETURNS public.wallet
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
    v_wallet public.wallet%rowtype;
    v_currency_code text;
    v_blockchain_code text;
begin
    v_currency_code :=
        nullif(lower(btrim(p_currency_code)), '');

    v_blockchain_code :=
        nullif(lower(btrim(p_blockchain_code)), '');

    if p_user_id is null or btrim(p_user_id) = '' then
        raise exception 'USER_ID_IS_REQUIRED';
    end if;

    if v_currency_code is null then
        raise exception 'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception 'WALLET_OWNER_IS_REQUIRED';
    end if;

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception 'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    select w.*
    into v_wallet
    from public.wallet w
    where w.user_id = p_user_id
      and w.owner_type = p_wallet_owner
      and lower(btrim(w.currency_code)) = v_currency_code
      and (
          v_currency_code <> 'gold'
          or lower(btrim(w.blockchain_code)) = v_blockchain_code
      )
    limit 1;

    if not found then
        raise exception 'USER_WALLET_NOT_FOUND';
    end if;

    return v_wallet;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fetch_opening_wallet_snapshot(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer,
    p_blockchain_code text DEFAULT NULL
)
RETURNS TABLE(
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
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
    v_snapshot public.wallet_balance_snapshot%rowtype;
    v_currency_code text;
    v_blockchain_code text;
begin
    v_currency_code :=
        nullif(lower(btrim(p_currency_code)), '');

    v_blockchain_code :=
        nullif(lower(btrim(p_blockchain_code)), '');

    if v_currency_code is null then
        raise exception 'CURRENCY_IS_REQUIRED';
    end if;

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception 'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    /*
     * Snapshot for the requested period.
     */
    select s.*
    into v_snapshot
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and lower(btrim(s.currency_code)) = v_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period
      and (
          v_currency_code <> 'gold'
          or lower(btrim(s.blockchain_code)) = v_blockchain_code
      )
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
     * Most recent snapshot in the same fiscal year.
     */
    select s.*
    into v_snapshot
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and lower(btrim(s.currency_code)) = v_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
      and (
          v_currency_code <> 'gold'
          or lower(btrim(s.blockchain_code)) = v_blockchain_code
      )
    order by s.period desc
    limit 1;

    /*
     * Most recent snapshot in a previous fiscal year.
     */
    if not found then
        select s.*
        into v_snapshot
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and lower(btrim(s.currency_code)) = v_currency_code
          and s.wallet_owner = p_wallet_owner
          and s.fiscal_year < p_fiscal_year
          and (
              v_currency_code <> 'gold'
              or lower(btrim(s.blockchain_code)) = v_blockchain_code
          )
        order by s.fiscal_year desc, s.period desc
        limit 1;
    end if;

    if found then
        return query
        select
            p_user_id,
            v_currency_code,
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
        v_currency_code,
        p_wallet_owner,
        p_fiscal_year,
        p_period,
        0::numeric,
        0::numeric,
        0::numeric,
        0::numeric;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_wallet_period_entries(
    p_user_id text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer,
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50,
    p_blockchain_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
    v_wallet public.wallet%rowtype;

    v_currency_code text;
    v_blockchain_code text;

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
    /*
     * Normalize parameters.
     */
    v_currency_code :=
        nullif(lower(btrim(p_currency_code)), '');

    v_blockchain_code :=
        nullif(lower(btrim(p_blockchain_code)), '');

    if p_user_id is null or btrim(p_user_id) = '' then
        raise exception 'USER_ID_IS_REQUIRED';
    end if;

    if v_currency_code is null then
        raise exception 'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception 'WALLET_OWNER_IS_REQUIRED';
    end if;

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception 'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    if p_fiscal_year is null then
        raise exception 'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception 'PERIOD_IS_REQUIRED';
    end if;

    if p_period < 1 or p_period > 12 then
        raise exception 'INVALID_PERIOD';
    end if;

    if p_page is null or p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    v_skip := (p_page - 1) * p_page_size;

    /*
     * Resolve the exact wallet.
     */
    v_wallet := public.fetch_wallet(
        p_user_id,
        v_currency_code,
        p_wallet_owner,
        v_blockchain_code
    );

    /*
     * Fetch opening and closing balances
     * for the same blockchain.
     */
    select
        snapshot.opening_balance,
        snapshot.closing_balance
    into
        v_opening_balance,
        v_closing_balance
    from public.fetch_opening_wallet_snapshot(
        p_user_id,
        v_currency_code,
        v_wallet.owner_type,
        p_fiscal_year,
        p_period,
        v_blockchain_code
    ) snapshot;

    v_opening_balance :=
        coalesce(v_opening_balance, 0);

    v_closing_balance :=
        coalesce(v_closing_balance, 0);

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
      and lower(btrim(e.currency_code)) = v_currency_code
      and e.fiscal_year = p_fiscal_year
      and e.period = p_period
      and (
          v_currency_code <> 'gold'
          or lower(btrim(e.blockchain_code)) =
              v_blockchain_code
      );

    /*
     * Balance immediately before the requested page.
     */
    select
        v_opening_balance +
        coalesce(
            sum(previous.credit - previous.debit),
            0
        )
    into v_page_opening
    from (
        select
            coalesce(e.debit, 0) as debit,
            coalesce(e.credit, 0) as credit
        from public.wallet_entry e
        where e.wallet_id = v_wallet.id
          and lower(btrim(e.currency_code)) = v_currency_code
          and e.fiscal_year = p_fiscal_year
          and e.period = p_period
          and (
              v_currency_code <> 'gold'
              or lower(btrim(e.blockchain_code)) =
                  v_blockchain_code
          )
        order by
            e.created_at asc,
            e.id asc
        limit v_skip
    ) previous;

    /*
     * Ordered entries with cumulative movements.
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
          and lower(btrim(e.currency_code)) = v_currency_code
          and e.fiscal_year = p_fiscal_year
          and e.period = p_period
          and (
              v_currency_code <> 'gold'
              or lower(btrim(e.blockchain_code)) =
                  v_blockchain_code
          )
    ),

    paged_entries as (
        select *
        from ordered_entries
        where entry_number > v_skip
          and entry_number <= v_skip + p_page_size
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
                    order by entry.entry_number desc
                )
            )[1],
            v_page_opening
        )

    into
        v_entries,
        v_page_closing

    from paged_entries entry;

    /*
     * Reconciliation.
     */
    v_calculated_closing :=
        v_opening_balance +
        v_total_credit -
        v_total_debit;

    v_difference :=
        v_calculated_closing -
        v_closing_balance;

    v_balanced :=
        abs(v_difference) <= 0.000001;

    /*
     * Pagination.
     */
    v_total_pages :=
        case
            when v_total_entries = 0 then 1
            else ceil(
                v_total_entries::numeric /
                p_page_size::numeric
            )::integer
        end;

    /*
     * Return the existing response structure
     * with blockchain_code added.
     */
    return jsonb_build_object(
        'currency_code',
        v_currency_code,

        'blockchain_code',
        case
            when v_currency_code = 'gold'
            then v_blockchain_code
            else null
        end,

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
$function$;


CREATE OR REPLACE FUNCTION public.get_my_wallet_period_entries(
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_fiscal_year integer,
    p_period integer,
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50,
    p_blockchain_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user_id text;
    v_currency_code text;
    v_blockchain_code text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    v_currency_code :=
        nullif(lower(btrim(p_currency_code)), '');

    v_blockchain_code :=
        nullif(lower(btrim(p_blockchain_code)), '');

    if v_currency_code is null then
        raise exception 'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception 'WALLET_OWNER_IS_REQUIRED';
    end if;

    if p_fiscal_year is null then
        raise exception 'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception 'PERIOD_IS_REQUIRED';
    end if;

    if p_period < 1 or p_period > 12 then
        raise exception 'INVALID_PERIOD';
    end if;

    if p_page is null or p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception 'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    /*
     * Resolve active user with an authorized role.
     */
    select u.id
    into v_user_id
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) in (
          'treasury',
          'agent',
          'customer',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'WALLET_PERIOD_ENTRIES_NOT_AUTHORIZED';
    end if;

    return public.get_wallet_period_entries(
        p_user_id => v_user_id,
        p_currency_code => v_currency_code,
        p_wallet_owner => p_wallet_owner,
        p_fiscal_year => p_fiscal_year,
        p_period => p_period,
        p_page => p_page,
        p_page_size => p_page_size,
        p_blockchain_code => v_blockchain_code
    );
end;
$function$;

