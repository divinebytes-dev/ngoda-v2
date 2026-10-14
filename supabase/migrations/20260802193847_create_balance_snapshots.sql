/* =========================================================
 * APPLY GL SNAPSHOT UPDATE
 * ========================================================= */

create or replace function public.apply_gl_snapshot_update(
    p_gl_account_code text,
    p_debit numeric,
    p_credit numeric,
    p_currency_code text,
    p_country_code text,
    p_fiscal_year integer,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_opening numeric := 0;
    v_delta numeric;
begin
    if p_debit = 0 and p_credit = 0 then
        return;
    end if;

    v_delta := p_debit - p_credit;

    /*
     * Find the latest snapshot in the same fiscal year.
     */
    select s.closing_balance
    into v_opening
    from public.gl_balance_snapshot s
    where s.country_code = p_country_code
      and s.gl_account_code = p_gl_account_code
      and s.currency_code = p_currency_code
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
    order by s.period desc
    limit 1;

    /*
     * If none exists, find the latest previous fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.gl_balance_snapshot s
        where s.country_code = p_country_code
          and s.gl_account_code = p_gl_account_code
          and s.currency_code = p_currency_code
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    v_opening := coalesce(v_opening, 0);

    insert into public.gl_balance_snapshot as current_snapshot (
        country_code,
        gl_account_code,
        currency_code,
        fiscal_year,
        period,
        opening_balance,
        debit,
        credit,
        closing_balance,
        created_at
    )
    values (
        p_country_code,
        p_gl_account_code,
        p_currency_code,
        p_fiscal_year,
        p_period,
        v_opening,
        p_debit,
        p_credit,
        v_opening + v_delta,
        now()
    )
    on conflict (
        country_code,
        gl_account_code,
        currency_code,
        fiscal_year,
        period
    )
    do update
    set
        debit =
            current_snapshot.debit + excluded.debit,

        credit =
            current_snapshot.credit + excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.debit -
            excluded.credit;
end;
$$;


/* =========================================================
 * UPDATE GL BALANCE SNAPSHOT
 * ========================================================= */

create or replace function public.update_gl_balance_snapshot(
    p_components public.posting_component[],
    p_mappings public.transaction_gl_mapping[],
    p_currency_code text,
    p_fiscal_year integer,
    p_country_code text,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_component public.posting_component;
    v_mapping public.transaction_gl_mapping%rowtype;
begin
    foreach v_component in array p_components
    loop
        /*
         * JavaScript Map keeps the last mapping for a component.
         */
        select m.mapping
        into v_mapping
        from unnest(p_mappings)
            with ordinality as m(mapping, position)
        where (m.mapping).component_type =
              v_component.component_type
        order by m.position desc
        limit 1;

        if not found then
            raise exception
                'MISSING_GL_MAPPING_%',
                v_component.component_type;
        end if;

        perform public.apply_gl_snapshot_update(
            v_mapping.debit_gl,
            v_component.debit_amount,
            0,
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );

        perform public.apply_gl_snapshot_update(
            v_mapping.credit_gl,
            0,
            v_component.credit_amount,
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );
    end loop;
end;
$$;


/* =========================================================
 * APPLY WALLET SNAPSHOT UPDATE
 * ========================================================= */

create or replace function public.apply_wallet_snapshot_update(
    p_user_id text,
    p_country_code text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_debit numeric,
    p_credit numeric,
    p_fiscal_year integer,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_opening numeric := 0;
    v_delta numeric;
begin
    if p_debit = 0 and p_credit = 0 then
        return;
    end if;

    v_delta := p_credit - p_debit;

    /*
     * Find the latest snapshot in the same fiscal year.
     */
    select s.closing_balance
    into v_opening
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and s.currency_code = p_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
    order by s.period desc
    limit 1;

    /*
     * If none exists, find the latest previous fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and s.currency_code = p_currency_code
          and s.wallet_owner = p_wallet_owner
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    v_opening := coalesce(v_opening, 0);

    insert into public.wallet_balance_snapshot as current_snapshot (
        user_id,
        country_code,
        currency_code,
        wallet_owner,
        fiscal_year,
        period,
        opening_balance,
        debit,
        credit,
        closing_balance,
        created_at
    )
    values (
        p_user_id,
        p_country_code,
        p_currency_code,
        p_wallet_owner,
        p_fiscal_year,
        p_period,
        v_opening,
        p_debit,
        p_credit,
        v_opening + v_delta,
        now()
    )
    on conflict (
        user_id,
        currency_code,
        wallet_owner,
        fiscal_year,
        period
    )
    do update
    set
        debit =
            current_snapshot.debit + excluded.debit,

        credit =
            current_snapshot.credit + excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.credit -
            excluded.debit;
end;
$$;


/* =========================================================
 * UPDATE WALLET BALANCE SNAPSHOT
 * ========================================================= */

create or replace function public.update_wallet_balance_snapshot(
    p_transaction_type public."TransactionType",
    p_sender_id text,
    p_receiver_id text,
    p_treasury_id text,
    p_currency_code text,
    p_sender_wallet_owner public."WalletOwnerType",
    p_receiver_wallet_owner public."WalletOwnerType",
    p_sender_amount numeric,
    p_receiver_amount numeric,
    p_fiscal_year integer,
    p_period integer,
    p_country_code text,
    p_fee_amount numeric default 0
)
returns void
language plpgsql
volatile
as $$
begin
    if p_sender_amount = 0
       and p_receiver_amount = 0
       and coalesce(p_fee_amount, 0) = 0
    then
        return;
    end if;

    /*
     * Treasury funding only credits the receiver.
     */
    if p_transaction_type =
       'treasury_funding'::public."TransactionType"
    then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id,
            p_country_code,
            p_currency_code,
            p_receiver_wallet_owner,
            0,
            p_receiver_amount,
            p_fiscal_year,
            p_period
        );

        return;
    end if;

    /*
     * Treasury funding reversal debits the receiver.
     */
    if p_transaction_type =
       'treasury_funding_reversal'::public."TransactionType"
    then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id,
            p_country_code,
            p_currency_code,
            p_receiver_wallet_owner,
            p_receiver_amount,
            0,
            p_fiscal_year,
            p_period
        );

        return;
    end if;

    if p_sender_id is null then
        raise exception
            'SENDER_REQUIRED_FOR_WALLET_SNAPSHOT';
    end if;

    if p_sender_amount > 0 then
        perform public.apply_wallet_snapshot_update(
            p_sender_id,
            p_country_code,
            p_currency_code,
            p_sender_wallet_owner,
            p_sender_amount,
            0,
            p_fiscal_year,
            p_period
        );
    end if;

    if p_receiver_amount > 0 then
        if p_transaction_type <>
           'government_tax_clearing'::public."TransactionType"
        then
            perform public.apply_wallet_snapshot_update(
                p_receiver_id,
                p_country_code,
                p_currency_code,
                p_receiver_wallet_owner,
                0,
                p_receiver_amount,
                p_fiscal_year,
                p_period
            );
        end if;
    end if;

    if coalesce(p_fee_amount, 0) > 0
       and p_treasury_id is not null
    then
        perform public.apply_wallet_snapshot_update(
            p_treasury_id,
            p_country_code,
            p_currency_code,
            'treasury'::public."WalletOwnerType",
            0,
            p_fee_amount,
            p_fiscal_year,
            p_period
        );
    end if;
end;
$$;


/* =========================================================
 * UPDATE COLLATERAL SNAPSHOT
 * ========================================================= */

create or replace function public.update_collateral_snapshot(
    p_user_id text,
    p_country_code text,
    p_debit numeric,
    p_credit numeric,
    p_fiscal_year integer,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_opening numeric := 0;
    v_delta numeric;
begin
    if p_debit = 0 and p_credit = 0 then
        return;
    end if;

    v_delta := p_debit - p_credit;

    /*
     * Find the latest snapshot in the same fiscal year.
     */
    select s.closing_balance
    into v_opening
    from public.collateral_balance_snapshot s
    where s.user_id = p_user_id
      and s.country_code = p_country_code
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
    order by s.period desc
    limit 1;

    /*
     * If none exists, find the latest previous fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.collateral_balance_snapshot s
        where s.user_id = p_user_id
          and s.country_code = p_country_code
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    v_opening := coalesce(v_opening, 0);

    insert into public.collateral_balance_snapshot as current_snapshot (
        user_id,
        country_code,
        fiscal_year,
        period,
        opening_balance,
        debit,
        credit,
        closing_balance,
        created_at
    )
    values (
        p_user_id,
        p_country_code,
        p_fiscal_year,
        p_period,
        v_opening,
        p_debit,
        p_credit,
        v_opening + v_delta,
        now()
    )
    on conflict (
        user_id,
        country_code,
        fiscal_year,
        period
    )
    do update
    set
        debit =
            current_snapshot.debit + excluded.debit,

        credit =
            current_snapshot.credit + excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.debit -
            excluded.credit;
end;
$$;


/* =========================================================
 * UPDATE LOAN SNAPSHOT
 * ========================================================= */

create or replace function public.update_loan_snapshot(
    p_loan_id text,
    p_user_id text,
    p_country_code text,
    p_debit_principal numeric,
    p_credit_principal numeric,
    p_debit_interest numeric,
    p_credit_interest numeric,
    p_fiscal_year integer,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_opening_principal numeric := 0;
    v_opening_interest numeric := 0;
    v_principal_delta numeric;
    v_interest_delta numeric;
begin
    if p_debit_principal = 0
       and p_credit_principal = 0
       and p_debit_interest = 0
       and p_credit_interest = 0
    then
        return;
    end if;

    v_principal_delta :=
        p_debit_principal - p_credit_principal;

    v_interest_delta :=
        p_debit_interest - p_credit_interest;

    /*
     * Find the latest snapshot in the same fiscal year.
     */
    select
        s.closing_principal,
        s.closing_interest
    into
        v_opening_principal,
        v_opening_interest
    from public.loan_balance_snapshot s
    where s.loan_id = p_loan_id
      and s.fiscal_year = p_fiscal_year
      and s.period < p_period
    order by s.period desc
    limit 1;

    /*
     * If none exists, find the latest previous fiscal year.
     */
    if not found then
        select
            s.closing_principal,
            s.closing_interest
        into
            v_opening_principal,
            v_opening_interest
        from public.loan_balance_snapshot s
        where s.loan_id = p_loan_id
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    v_opening_principal :=
        coalesce(v_opening_principal, 0);

    v_opening_interest :=
        coalesce(v_opening_interest, 0);

    insert into public.loan_balance_snapshot as current_snapshot (
        loan_id,
        user_id,
        country_code,
        fiscal_year,
        period,
        opening_principal,
        debit_principal,
        credit_principal,
        opening_interest,
        debit_interest,
        credit_interest,
        closing_principal,
        closing_interest,
        created_at
    )
    values (
        p_loan_id,
        p_user_id,
        p_country_code,
        p_fiscal_year,
        p_period,
        v_opening_principal,
        p_debit_principal,
        p_credit_principal,
        v_opening_interest,
        p_debit_interest,
        p_credit_interest,
        v_opening_principal + v_principal_delta,
        v_opening_interest + v_interest_delta,
        now()
    )
    on conflict (
        loan_id,
        fiscal_year,
        period
    )
    do update
    set
        debit_principal =
            current_snapshot.debit_principal +
            excluded.debit_principal,

        credit_principal =
            current_snapshot.credit_principal +
            excluded.credit_principal,

        debit_interest =
            current_snapshot.debit_interest +
            excluded.debit_interest,

        credit_interest =
            current_snapshot.credit_interest +
            excluded.credit_interest,

        closing_principal =
            current_snapshot.closing_principal +
            excluded.debit_principal -
            excluded.credit_principal,

        closing_interest =
            current_snapshot.closing_interest +
            excluded.debit_interest -
            excluded.credit_interest;
end;
$$;