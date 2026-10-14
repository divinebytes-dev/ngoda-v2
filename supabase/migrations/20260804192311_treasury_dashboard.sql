create or replace function public.fetch_my_treasury_dashboard_context()
returns table (
    user_id text,
    country_code text
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    return query
    select
        u.id,
        u.country_code
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) =
          'treasury'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'TREASURY_NOT_AUTHORIZED';
    end if;
end;
$function$;

create or replace function public.build_my_treasury_dashboard(
    p_token_supply text,
    p_gas_balance text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_fiscal_year integer;

    v_token_supply numeric := 0;
    v_gas_balance numeric := 0;

    v_gold_reserve numeric := 0;
    v_reserve_ratio numeric := 0;

    v_wallet record;
    v_balance numeric;
    v_rate numeric;
    v_usd_value numeric;

    v_wallet_balances jsonb :=
        '[]'::jsonb;

    v_currencies jsonb :=
        '[]'::jsonb;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Resolve the authenticated application user and
     * enforce the treasury role.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) =
          'treasury'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'TREASURY_NOT_AUTHORIZED';
    end if;

    /*
     * Parse blockchain token supply.
     */
    begin
        v_token_supply :=
            coalesce(
                nullif(
                    btrim(p_token_supply),
                    ''
                ),
                '0'
            )::numeric;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_TOKEN_SUPPLY';
    end;

    /*
     * Parse relayer gas balance.
     */
    begin
        v_gas_balance :=
            coalesce(
                nullif(
                    btrim(p_gas_balance),
                    ''
                ),
                '0'
            )::numeric;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_GAS_BALANCE';
    end;

    if v_token_supply < 0 then
        raise exception
            'INVALID_TOKEN_SUPPLY';
    end if;

    if v_gas_balance < 0 then
        raise exception
            'INVALID_GAS_BALANCE';
    end if;

    /*
     * Preserve the original reserve-transparency logic:
     * use the current Zimbabwe fiscal year.
     */
    select fp.fiscal_year
    into v_fiscal_year
    from public.fiscal_period_config fp
    where fp.country_code = 'zw'
      and fp.opening_date <= current_date
      and fp.closing_date >= current_date
    order by
        fp.fiscal_year desc,
        fp.period desc
    limit 1;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Physical gold:
     *
     * balance() in the original code returned:
     * credit - debit
     */
    select
        coalesce(
            sum(ae.credit),
            0
        ) -
        coalesce(
            sum(ae.debit),
            0
        )
    into v_gold_reserve
    from public.asset_entry ae
    where ae.fiscal_year =
          v_fiscal_year;

    v_gold_reserve :=
        coalesce(v_gold_reserve, 0);

    /*
     * Preserve the original treasury reserve ratio.
     * This is a ratio, not a percentage.
     */
    if v_token_supply > 0 then
        v_reserve_ratio :=
            v_gold_reserve /
            v_token_supply;
    else
        v_reserve_ratio := 0;
    end if;

    /*
     * Treasury wallets for the authenticated
     * treasury user's country.
     */
    for v_wallet in
        select
            lower(btrim(w.currency_code))
                as currency_code,

            coalesce(w.balance, 0)::numeric
                as balance

        from public.wallet w

        where w.owner_type =
              'treasury'::public."WalletOwnerType"

          and w.country_code =
              v_user.country_code

        order by
            lower(btrim(w.currency_code))
    loop
        v_balance :=
            v_wallet.balance;

        if v_wallet.currency_code = 'usd' then
            v_usd_value :=
                v_balance;
        else
            select cr.rate_to_usd
            into v_rate
            from public.current_rates cr
            where lower(btrim(cr.code)) =
                  v_wallet.currency_code
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_FOR_CURRENCY_%',
                    upper(
                        v_wallet.currency_code
                    );
            end if;

            if v_wallet.currency_code = 'gold' then
                v_usd_value :=
                    v_balance * v_rate;
            else
                v_usd_value :=
                    v_balance / v_rate;
            end if;
        end if;

        v_wallet_balances :=
            v_wallet_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'currency_code',
                    v_wallet.currency_code,

                    'balance',
                    trim_scale(v_balance)::text,

                    'usd_value',
                    trim_scale(v_usd_value)::text
                )
            );
    end loop;

    /*
     * Use the supported-currency function already
     * created in the database.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    return jsonb_build_object(
        'gold_reserve',
        v_gold_reserve,

        'token_supply',
        v_token_supply,

        'gas_balance',
        v_gas_balance,

        'reserve_ratio',
        v_reserve_ratio,

        'treasury_wallet_balances',
        v_wallet_balances,

        'currencies',
        v_currencies
    );
end;
$function$;

revoke all
on function public.fetch_my_treasury_dashboard_context()
from public, anon;

grant execute
on function public.fetch_my_treasury_dashboard_context()
to authenticated;

revoke all
on function public.build_my_treasury_dashboard(
    text,
    text
)
from public, anon;

grant execute
on function public.build_my_treasury_dashboard(
    text,
    text
)
to authenticated;