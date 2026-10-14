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
    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0
    then
        return;
    end if;

    v_delta :=
        coalesce(p_debit, 0) -
        coalesce(p_credit, 0);

    /*
     * First: fetch the exact current snapshot.
     * This matches Prisma findUnique().
     */
    select s.closing_balance
    into v_opening
    from public.gl_balance_snapshot s
    where s.country_code = p_country_code
      and s.gl_account_code = p_gl_account_code
      and s.currency_code = p_currency_code
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period;

    /*
     * Second: if the exact snapshot does not exist, fetch the
     * latest earlier period in the same fiscal year.
     */
    if not found then
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
    end if;

    /*
     * Third: if no snapshot exists in the current fiscal year,
     * fetch the latest snapshot from an earlier fiscal year.
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
        created_at,
        updated_at
    )
    values (
        p_country_code,
        p_gl_account_code,
        p_currency_code,
        p_fiscal_year,
        p_period,
        v_opening,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        v_opening + v_delta,
        now(),
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
            current_snapshot.debit +
            excluded.debit,

        credit =
            current_snapshot.credit +
            excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.debit -
            excluded.credit,

        updated_at = now();
end;
$$;

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
    v_candidate_mapping public.transaction_gl_mapping%rowtype;
    v_selected_mapping public.transaction_gl_mapping%rowtype;
    v_mapping_found boolean;
begin
    if p_components is null then
        raise exception 'POSTING_COMPONENTS_REQUIRED';
    end if;

    if p_mappings is null then
        raise exception 'GL_MAPPINGS_REQUIRED';
    end if;

    foreach v_component in array p_components
    loop
        v_mapping_found := false;

        /*
         * The last matching mapping wins, matching JavaScript Map.
         */
        foreach v_candidate_mapping in array p_mappings
        loop
            if v_candidate_mapping.component_type =
               v_component.component_type
            then
                v_selected_mapping :=
                    v_candidate_mapping;

                v_mapping_found := true;
            end if;
        end loop;

        if not v_mapping_found then
            raise exception
                'MISSING_GL_MAPPING_%',
                v_component.component_type;
        end if;

        perform public.apply_gl_snapshot_update(
            v_selected_mapping.debit_gl,
            coalesce(v_component.debit_amount, 0),
            0,
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );

        perform public.apply_gl_snapshot_update(
            v_selected_mapping.credit_gl,
            0,
            coalesce(v_component.credit_amount, 0),
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );
    end loop;
end;
$$;

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
    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0
    then
        return;
    end if;

    v_delta :=
        coalesce(p_credit, 0) -
        coalesce(p_debit, 0);

    /*
     * First: exact current snapshot.
     */
    select s.closing_balance
    into v_opening
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and s.currency_code = p_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period;

    /*
     * Second: earlier period in the same fiscal year.
     */
    if not found then
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
    end if;

    /*
     * Third: latest earlier fiscal year.
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
        created_at,
        updated_at
    )
    values (
        p_user_id,
        p_country_code,
        p_currency_code,
        p_wallet_owner,
        p_fiscal_year,
        p_period,
        v_opening,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        v_opening + v_delta,
        now(),
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
            current_snapshot.debit +
            excluded.debit,

        credit =
            current_snapshot.credit +
            excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.credit -
            excluded.debit,

        updated_at = now();
end;
$$;


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
    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0
    then
        return;
    end if;

    v_delta :=
        coalesce(p_debit, 0) -
        coalesce(p_credit, 0);

    /*
     * First: exact current snapshot.
     */
    select s.closing_balance
    into v_opening
    from public.collateral_balance_snapshot s
    where s.user_id = p_user_id
      and s.country_code = p_country_code
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period;

    /*
     * Second: earlier period in the same fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.collateral_balance_snapshot s
        where s.user_id = p_user_id
          and s.country_code = p_country_code
          and s.fiscal_year = p_fiscal_year
          and s.period < p_period
        order by s.period desc
        limit 1;
    end if;

    /*
     * Third: latest earlier fiscal year.
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
        created_at,
        updated_at
    )
    values (
        p_user_id,
        p_country_code,
        p_fiscal_year,
        p_period,
        v_opening,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        v_opening + v_delta,
        now(),
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
            current_snapshot.debit +
            excluded.debit,

        credit =
            current_snapshot.credit +
            excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.debit -
            excluded.credit,

        updated_at = now();
end;
$$;

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
    if coalesce(p_debit_principal, 0) = 0
       and coalesce(p_credit_principal, 0) = 0
       and coalesce(p_debit_interest, 0) = 0
       and coalesce(p_credit_interest, 0) = 0
    then
        return;
    end if;

    v_principal_delta :=
        coalesce(p_debit_principal, 0) -
        coalesce(p_credit_principal, 0);

    v_interest_delta :=
        coalesce(p_debit_interest, 0) -
        coalesce(p_credit_interest, 0);

    /*
     * First: exact current snapshot.
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
      and s.period = p_period;

    /*
     * Second: earlier period in the same fiscal year.
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
          and s.fiscal_year = p_fiscal_year
          and s.period < p_period
        order by s.period desc
        limit 1;
    end if;

    /*
     * Third: latest earlier fiscal year.
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
        created_at,
        updated_at
    )
    values (
        p_loan_id,
        p_user_id,
        p_country_code,
        p_fiscal_year,
        p_period,
        v_opening_principal,
        coalesce(p_debit_principal, 0),
        coalesce(p_credit_principal, 0),
        v_opening_interest,
        coalesce(p_debit_interest, 0),
        coalesce(p_credit_interest, 0),
        v_opening_principal +
            v_principal_delta,
        v_opening_interest +
            v_interest_delta,
        now(),
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
            excluded.credit_interest,

        updated_at = now();
end;
$$;
