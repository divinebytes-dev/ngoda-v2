create or replace function public.build_my_customer_dashboard(
    p_token_balance text,
    p_gas_balance text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user public.users%rowtype;

    v_wallet record;
    v_rate numeric;
    v_balance numeric;
    v_usd_value numeric;

    v_balances jsonb := '{}'::jsonb;
    v_currencies jsonb := '[]'::jsonb;

    v_locked_tokens numeric := 0;
    v_total_tokens numeric := 0;
    v_available_tokens numeric := 0;

    v_principal numeric := 0;
    v_interest numeric := 0;

    v_gold_price numeric := 0;
    v_collateral_value numeric := 0;
    v_ltv numeric := 0;
    v_health text := 'SAFE';
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name) = 'customer'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'CUSTOMER_NOT_AUTHORIZED';
    end if;

    begin
        v_total_tokens :=
            coalesce(
                nullif(trim(p_token_balance), ''),
                '0'
            )::numeric;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end;

    select coalesce(c.locked_tokens, 0)
    into v_locked_tokens
    from public.collateral c
    where c.user_id = v_user.id
    limit 1;

    v_locked_tokens :=
        coalesce(v_locked_tokens, 0);

    v_available_tokens :=
        v_total_tokens -
        v_locked_tokens;

    /*
     * Gold price in USD.
     */
    select coalesce(r.rate_to_usd, 0)
    into v_gold_price
    from public.current_rates r
    where lower(r.code) = 'gold'
    limit 1;

    v_gold_price :=
        coalesce(v_gold_price, 0);

    if v_gold_price <= 0 then
        raise exception 'INVALID_GOLD_RATE';
    end if;

    /*
     * Wallet balances.
     *
     * Preserve the original rules:
     * - USD: balance is already USD.
     * - Gold: blockchain balance × gold rate.
     * - Other fiat: wallet balance ÷ rate_to_usd.
     */
    for v_wallet in
        select
            w.currency_code,
            w.balance
        from public.wallet w
        where w.user_id = v_user.id
    loop
        if lower(v_wallet.currency_code) = 'usd' then
            v_balance :=
                coalesce(v_wallet.balance, 0);

            v_usd_value :=
                v_balance;
        else
            select r.rate_to_usd
            into v_rate
            from public.current_rates r
            where lower(r.code) =
                  lower(v_wallet.currency_code)
            limit 1;

            if not found or v_rate is null or v_rate = 0 then
                raise exception
                    'MISSING_RATE_%',
                    upper(v_wallet.currency_code);
            end if;

            if lower(v_wallet.currency_code) = 'gold' then
                v_balance :=
                    v_total_tokens;

                v_usd_value :=
                    v_balance * v_rate;
            else
                v_balance :=
                    coalesce(v_wallet.balance, 0);

                v_usd_value :=
                    v_balance / v_rate;
            end if;
        end if;

        v_balances :=
            v_balances ||
            jsonb_build_object(
                lower(v_wallet.currency_code),
                jsonb_build_object(
                    'balance',
                    trim_scale(v_balance)::text,
                    'usd_value',
                    to_char(
                        round(v_usd_value, 2),
                        'FM999999999999999999999999990.00'
                    )
                )
            );
    end loop;

    /*
     * Aggregate all active loans across all fiscal years.
     */
    select
        coalesce(
            sum(le.debit_principal),
            0
        ) -
        coalesce(
            sum(le.credit_principal),
            0
        ),
        coalesce(
            sum(le.debit_interest),
            0
        ) -
        coalesce(
            sum(le.credit_interest),
            0
        )
    into
        v_principal,
        v_interest
    from public.loan l
    left join public.loan_entry le
      on le.loan_id = l.id
    where l.user_id = v_user.id
      and l.status =
          'active'::public."LoanStatus";

    v_principal := coalesce(v_principal, 0);
    v_interest := coalesce(v_interest, 0);

    v_collateral_value :=
        v_locked_tokens *
        v_gold_price;

    if v_collateral_value > 0 then
        v_ltv :=
            (
                v_principal +
                v_interest
            ) /
            v_collateral_value *
            100;
    else
        v_ltv := 0;
    end if;

    if v_ltv >= 85 then
        v_health := 'LIQUIDATION_RISK';
    elsif v_ltv >= 70 then
        v_health := 'WARNING';
    else
        v_health := 'SAFE';
    end if;

    /*
     * Supported fiat currencies for the user's country.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                sc.currency_code,
                'symbol',
                sc.symbol,
                'name',
                sc.name,
                'is_active',
                sc.is_active,
                'is_reporting',
                cc.is_reporting
            )
            order by sc.currency_code
        ),
        '[]'::jsonb
    )
    into v_currencies
    from public.country_currencies cc
    join public.supported_currency sc
      on lower(sc.currency_code) =
         lower(cc.currency_code)
    where cc.country_code =
          v_user.country_code
      and cc.is_active = true
      and sc.currency_category =
          'fiat'::public."CurrencyCategory";

    return jsonb_build_object(
        'wallet',
        jsonb_build_object(
            'wallet_address',
            v_user.wallet_address,
            'token_balance',
            trim_scale(v_total_tokens)::text,
            'gas_balance',
            coalesce(
                nullif(trim(p_gas_balance), ''),
                '0'
            ),
            'balances',
            v_balances,
            'available_tokens',
            trim_scale(v_available_tokens)::text
        ),
        'loan',
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(v_principal)::text,
            'interest_outstanding',
            trim_scale(v_interest)::text,
            'collateral_locked',
            trim_scale(v_locked_tokens)::text,
            'ltv_percent',
            to_char(
                round(v_ltv, 2),
                'FM999999999999999999999999990.00'
            ),
            'health',
            v_health,
            'gold',
            jsonb_build_object(
                'total',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_total_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),
                    'usdValue',
                    to_char(
                        round(
                            v_total_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),
                'locked',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_locked_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),
                    'usdValue',
                    to_char(
                        round(
                            v_locked_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),
                'available',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(v_available_tokens, 6),
                        'FM999999999999999999999999990.000000'
                    ),
                    'usdValue',
                    to_char(
                        round(
                            v_available_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                )
            )
        ),
        'currencies',
        v_currencies
    );
end;
$$;

revoke execute
on function public.fetch_my_customer_dashboard_context()
from public, anon;

grant execute
on function public.fetch_my_customer_dashboard_context()
to authenticated;

revoke execute
on function public.build_my_customer_dashboard(
    text,
    text
)
from public, anon;

grant execute
on function public.build_my_customer_dashboard(
    text,
    text
)
to authenticated;

notify pgrst, 'reload schema';