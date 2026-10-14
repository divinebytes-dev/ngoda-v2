begin;


create or replace function public.build_my_agent_dashboard(
    p_token_balance text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_currencies jsonb;
    v_wallet jsonb;
    v_daily_summary jsonb;
    v_loan_summary jsonb;

    v_total_tokens numeric := 0;
    v_locked_tokens numeric := 0;
    v_available_tokens numeric := 0;

    v_principal numeric := 0;
    v_interest numeric := 0;

    v_gold_price numeric := 0;
    v_collateral_value numeric := 0;
    v_ltv numeric := 0;
    v_health text := 'SAFE';

    /* Loyalty values used by transfer-fee eligibility. */
    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    /* Current active loan access configuration. */
    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_configured_loan_limit_rows bigint := 0;
    v_min_max_active_loans integer;
    v_max_max_active_loans integer;
    v_max_active_loans integer;
    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;
begin
    /* Authentication. */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /* Resolve and authorize the active agent. */
    select user_record.*
    into v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id = user_record.role_id
    where user_record.id = auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(role_record.name::text) = 'agent'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'AGENT_NOT_AUTHORIZED';
    end if;

    /* Parse the blockchain Gold-token balance. */
    begin
        v_total_tokens :=
            coalesce(
                nullif(btrim(p_token_balance), ''),
                '0'
            )::numeric;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end;

    if v_total_tokens < 0 then
        raise exception
            'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end if;

    /* Preserve the existing supported currencies. */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /* Preserve the agent and customer wallet containers. */
    v_wallet :=
        jsonb_build_object(
            'agent',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),
            'customer',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            )
        )
        ||
        public.build_user_wallet_balance(
            v_user.id
        );

    /* Preserve the existing daily summary. */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    /*
     * Spendable points determine whether the agent may
     * select points for a quoted customer-wallet transfer.
     *
     * An agent without a loyalty account has zero points.
     */
    select
        account_record.available_points,
        account_record.tier_points,
        account_record.lifetime_earned_points,
        account_record.level_code,
        account_record.is_active
    into
        v_available_points,
        v_tier_points,
        v_lifetime_earned_points,
        v_loyalty_level,
        v_loyalty_account_active
    from public.loyalty_account account_record
    where account_record.user_id = v_user.id
    limit 1;

    v_available_points :=
        greatest(coalesce(v_available_points, 0), 0);

    v_tier_points :=
        greatest(coalesce(v_tier_points, 0), 0);

    v_lifetime_earned_points :=
        greatest(
            coalesce(v_lifetime_earned_points, 0),
            0
        );

    v_loyalty_level :=
        coalesce(
            nullif(btrim(v_loyalty_level), ''),
            'bronze'
        );

    v_loyalty_account_active :=
        coalesce(v_loyalty_account_active, false);

    /* Fetch the agent's locked Gold collateral. */
    select coalesce(
        collateral_record.locked_tokens,
        0
    )
    into v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id = v_user.id
    limit 1;

    v_locked_tokens :=
        coalesce(v_locked_tokens, 0);

    v_available_tokens :=
        v_total_tokens -
        v_locked_tokens;

    /* Current Gold price in USD. */
    select coalesce(
        rate_record.rate_to_usd,
        0
    )
    into v_gold_price
    from public.current_rates rate_record
    where lower(btrim(rate_record.code)) = 'gold'
    limit 1;

    v_gold_price :=
        coalesce(v_gold_price, 0);

    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;

    /*
     * fiscal_year and period are historical attributes and
     * must not select the live borrowing limit.
     *
     * max_active_loans is a facility-wide limit, so every
     * active row for the user's country must contain the
     * same positive value.
     */
    select
        count(*),
        count(*) filter (
            where config_record.max_active_loans is not null
        ),
        min(config_record.max_active_loans),
        max(config_record.max_active_loans)
    into
        v_active_loan_config_rows,
        v_configured_loan_limit_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    from public.loan_config config_record
    where config_record.country_code =
          v_user.country_code
      and config_record.is_active = true;

    if v_active_loan_config_rows = 0
       or v_configured_loan_limit_rows <>
          v_active_loan_config_rows
       or v_min_max_active_loans is null
    then
        raise exception
            'MAX_ACTIVE_LOANS_NOT_CONFIGURED';
    end if;

    if v_min_max_active_loans is distinct from
       v_max_max_active_loans
    then
        raise exception
            'MAX_ACTIVE_LOANS_CONFIGURATION_AMBIGUOUS';
    end if;

    v_max_active_loans :=
        v_min_max_active_loans;

    if v_max_active_loans <= 0 then
        raise exception
            'INVALID_MAX_ACTIVE_LOANS';
    end if;

    /*
     * Aggregate all active agent loans across all fiscal
     * years and count each loan once.
     */
    select
        count(distinct loan_record.id)::bigint,
        coalesce(
            sum(loan_entry_record.debit_principal),
            0
        ) -
        coalesce(
            sum(loan_entry_record.credit_principal),
            0
        ),
        coalesce(
            sum(loan_entry_record.debit_interest),
            0
        ) -
        coalesce(
            sum(loan_entry_record.credit_interest),
            0
        )
    into
        v_active_loans,
        v_principal,
        v_interest
    from public.loan loan_record
    left join public.loan_entry loan_entry_record
      on loan_entry_record.loan_id = loan_record.id
    where loan_record.user_id = v_user.id
      and loan_record.status =
          'active'::public."LoanStatus";

    v_active_loans :=
        greatest(coalesce(v_active_loans, 0), 0);

    v_principal :=
        coalesce(v_principal, 0);

    v_interest :=
        coalesce(v_interest, 0);

    v_sva_access_utilisation :=
        round(
            (
                v_active_loans::numeric /
                v_max_active_loans::numeric
            ) * 100,
            2
        );

    v_can_access_sva :=
        v_sva_access_utilisation < 100;

    /* Calculate collateral value and LTV. */
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

    /* Build LoanSummary using the shared Flutter model. */
    v_loan_summary :=
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
            'sva_access',
            jsonb_build_object(
                'active_loans',
                v_active_loans,
                'max_active_loans',
                v_max_active_loans,
                'utilisation_percent',
                to_char(
                    v_sva_access_utilisation,
                    'FM999999999999999999999999990.00'
                ),
                'can_access',
                v_can_access_sva
            ),
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
        );

    /* Preserve every existing field and add loyalty. */
    return jsonb_build_object(
        'currencies',
        v_currencies,
        'wallet',
        v_wallet,
        'dailySummary',
        v_daily_summary,
        'loyalty',
        jsonb_build_object(
            'available_points',
            v_available_points,
            'tier_points',
            v_tier_points,
            'lifetime_earned_points',
            v_lifetime_earned_points,
            'level_code',
            v_loyalty_level,
            'is_active',
            v_loyalty_account_active
        ),
        'loanSummary',
        v_loan_summary
    );
end;
$function$;


notify pgrst, 'reload schema';

commit;




begin;


create or replace function public.build_my_customer_dashboard(
    p_token_balance text,
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

    /* Loyalty values used by transfer-fee eligibility. */
    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    /* Current active loan access configuration. */
    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_configured_loan_limit_rows bigint := 0;
    v_min_max_active_loans integer;
    v_max_max_active_loans integer;
    v_max_active_loans integer;
    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id = user_record.role_id
    where user_record.id = auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(role_record.name) = 'customer'
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

    select coalesce(collateral_record.locked_tokens, 0)
    into v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id = v_user.id
    limit 1;

    v_locked_tokens :=
        coalesce(v_locked_tokens, 0);

    v_available_tokens :=
        v_total_tokens -
        v_locked_tokens;

    /* Gold price in USD. */
    select coalesce(rate_record.rate_to_usd, 0)
    into v_gold_price
    from public.current_rates rate_record
    where lower(rate_record.code) = 'gold'
    limit 1;

    v_gold_price :=
        coalesce(v_gold_price, 0);

    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;

    /*
     * Wallet balances.
     *
     * - USD: balance is already USD.
     * - Gold: blockchain balance multiplied by Gold rate.
     * - Other fiat: wallet balance divided by rate_to_usd.
     */
    for v_wallet in
        select
            wallet_record.currency_code,
            wallet_record.balance
        from public.wallet wallet_record
        where wallet_record.user_id = v_user.id
    loop
        if lower(v_wallet.currency_code) = 'usd' then
            v_balance :=
                coalesce(v_wallet.balance, 0);

            v_usd_value :=
                v_balance;
        else
            select rate_record.rate_to_usd
            into v_rate
            from public.current_rates rate_record
            where lower(rate_record.code) =
                  lower(v_wallet.currency_code)
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
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
     * Spendable points determine whether the user may
     * select points for a quoted transfer fee.
     *
     * A user without a loyalty account has zero points.
     */
    select
        account_record.available_points,
        account_record.tier_points,
        account_record.lifetime_earned_points,
        account_record.level_code,
        account_record.is_active
    into
        v_available_points,
        v_tier_points,
        v_lifetime_earned_points,
        v_loyalty_level,
        v_loyalty_account_active
    from public.loyalty_account account_record
    where account_record.user_id = v_user.id
    limit 1;

    v_available_points :=
        greatest(coalesce(v_available_points, 0), 0);

    v_tier_points :=
        greatest(coalesce(v_tier_points, 0), 0);

    v_lifetime_earned_points :=
        greatest(
            coalesce(v_lifetime_earned_points, 0),
            0
        );

    v_loyalty_level :=
        coalesce(
            nullif(btrim(v_loyalty_level), ''),
            'bronze'
        );

    v_loyalty_account_active :=
        coalesce(v_loyalty_account_active, false);

    /*
     * fiscal_year and period are historical attributes and
     * must not select the live borrowing limit.
     *
     * max_active_loans is a facility-wide limit, so every
     * active row for the user's country must contain the
     * same positive value.
     */
    select
        count(*),
        count(*) filter (
            where config_record.max_active_loans is not null
        ),
        min(config_record.max_active_loans),
        max(config_record.max_active_loans)
    into
        v_active_loan_config_rows,
        v_configured_loan_limit_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    from public.loan_config config_record
    where config_record.country_code =
          v_user.country_code
      and config_record.is_active = true;

    if v_active_loan_config_rows = 0
       or v_configured_loan_limit_rows <>
          v_active_loan_config_rows
       or v_min_max_active_loans is null
    then
        raise exception
            'MAX_ACTIVE_LOANS_NOT_CONFIGURED';
    end if;

    if v_min_max_active_loans is distinct from
       v_max_max_active_loans
    then
        raise exception
            'MAX_ACTIVE_LOANS_CONFIGURATION_AMBIGUOUS';
    end if;

    v_max_active_loans :=
        v_min_max_active_loans;

    if v_max_active_loans <= 0 then
        raise exception
            'INVALID_MAX_ACTIVE_LOANS';
    end if;

    /*
     * Aggregate all active loans across all fiscal years and
     * count each active facility once, regardless of how many
     * loan_entry rows it contains.
     */
    select
        count(distinct loan_record.id)::bigint,
        coalesce(
            sum(entry_record.debit_principal),
            0
        ) -
        coalesce(
            sum(entry_record.credit_principal),
            0
        ),
        coalesce(
            sum(entry_record.debit_interest),
            0
        ) -
        coalesce(
            sum(entry_record.credit_interest),
            0
        )
    into
        v_active_loans,
        v_principal,
        v_interest
    from public.loan loan_record
    left join public.loan_entry entry_record
      on entry_record.loan_id = loan_record.id
    where loan_record.user_id = v_user.id
      and loan_record.status =
          'active'::public."LoanStatus";

    v_active_loans :=
        greatest(coalesce(v_active_loans, 0), 0);

    v_principal :=
        coalesce(v_principal, 0);

    v_interest :=
        coalesce(v_interest, 0);

    v_sva_access_utilisation :=
        round(
            (
                v_active_loans::numeric /
                v_max_active_loans::numeric
            ) * 100,
            2
        );

    v_can_access_sva :=
        v_sva_access_utilisation < 100;

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

    /* Supported fiat currencies for the user's country. */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                supported_record.currency_code,
                'symbol',
                supported_record.symbol,
                'name',
                supported_record.name,
                'is_active',
                supported_record.is_active,
                'is_reporting',
                country_currency_record.is_reporting
            )
            order by supported_record.currency_code
        ),
        '[]'::jsonb
    )
    into v_currencies
    from public.country_currencies country_currency_record
    join public.supported_currency supported_record
      on lower(supported_record.currency_code) =
         lower(country_currency_record.currency_code)
    where country_currency_record.country_code =
          v_user.country_code
      and country_currency_record.is_active = true
      and supported_record.currency_category =
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

        'loyalty',
        jsonb_build_object(
            'available_points',
            v_available_points,
            'tier_points',
            v_tier_points,
            'lifetime_earned_points',
            v_lifetime_earned_points,
            'level_code',
            v_loyalty_level,
            'is_active',
            v_loyalty_account_active
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

            'sva_access',
            jsonb_build_object(
                'active_loans',
                v_active_loans,
                'max_active_loans',
                v_max_active_loans,
                'utilisation_percent',
                to_char(
                    v_sva_access_utilisation,
                    'FM999999999999999999999999990.00'
                ),
                'can_access',
                v_can_access_sva
            ),

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
$function$;


notify pgrst, 'reload schema';

commit;


