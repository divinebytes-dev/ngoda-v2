CREATE OR REPLACE FUNCTION public.build_my_agent_dashboard(
    p_token_balance text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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

    /*
     * Additional pooled collateral currently required
     * across all active loans.
     *
     * Calculated by the shared collateral function.
     */
    v_required_collateral numeric := 0;

    /* Loyalty values used by transfer-fee eligibility. */
    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    /* Current active loan access configuration. */
    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_min_max_active_loans numeric;
    v_max_max_active_loans numeric;
    v_max_active_loans integer;
    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;

begin
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;


    /*
     * ==========================================================
     * RESOLVE AND AUTHORIZE ACTIVE AGENT
     * ==========================================================
     */
    select
        user_record.*
    into
        v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(
          role_record.name::text
      ) = 'agent'
    limit 1;


    if not found then
        raise exception using
            errcode = '42501',
            message = 'AGENT_NOT_AUTHORIZED';
    end if;


    /*
     * ==========================================================
     * PARSE BLOCKCHAIN GOLD TOKEN BALANCE
     * ==========================================================
     */
    begin
        v_total_tokens :=
            coalesce(
                nullif(
                    btrim(
                        p_token_balance
                    ),
                    ''
                ),
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


    /*
     * ==========================================================
     * SUPPORTED CURRENCIES
     * ==========================================================
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );


    /*
     * ==========================================================
     * WALLET BALANCES
     * ==========================================================
     */
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


    /*
     * ==========================================================
     * DAILY SUMMARY
     * ==========================================================
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );


    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     *
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
    where account_record.user_id =
          v_user.id
    limit 1;


    v_available_points :=
        greatest(
            coalesce(
                v_available_points,
                0
            ),
            0
        );


    v_tier_points :=
        greatest(
            coalesce(
                v_tier_points,
                0
            ),
            0
        );


    v_lifetime_earned_points :=
        greatest(
            coalesce(
                v_lifetime_earned_points,
                0
            ),
            0
        );


    v_loyalty_level :=
        coalesce(
            nullif(
                btrim(
                    v_loyalty_level
                ),
                ''
            ),
            'bronze'
        );


    v_loyalty_account_active :=
        coalesce(
            v_loyalty_account_active,
            false
        );


    /*
     * ==========================================================
     * CURRENT POOLED COLLATERAL
     * ==========================================================
     */
    select
        coalesce(
            collateral_record.locked_tokens,
            0
        )
    into
        v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id =
          v_user.id
    limit 1;


    v_locked_tokens :=
        greatest(
            coalesce(
                v_locked_tokens,
                0
            ),
            0
        );


    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_locked_tokens,
            0
        );


    /*
     * ==========================================================
     * CURRENT GOLD PRICE
     * ==========================================================
     */
    select
        coalesce(
            rate_record.rate_to_usd,
            0
        )
    into
        v_gold_price
    from public.current_rates rate_record
    where lower(
        btrim(
            rate_record.code
        )
    ) = 'gold'
    limit 1;


    v_gold_price :=
        coalesce(
            v_gold_price,
            0
        );


    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * REQUIRED COLLATERAL
     * ==========================================================
     *
     * Shared business calculation.
     *
     * The helper:
     *
     * - calculates current exposure for every active loan;
     * - applies each loan's max_ltv_percent;
     * - uses the current Gold price;
     * - calculates the total required collateral pool;
     * - subtracts collateral.locked_tokens;
     * - returns the additional Gold currently required.
     */
    v_required_collateral :=
        public.calculate_required_collateral(
            v_user.id
        );


    /*
     * ==========================================================
     * MAXIMUM ACTIVE LOANS CONFIGURATION
     * ==========================================================
     *
     * fiscal_year and period are historical attributes and
     * must not select the live borrowing limit.
     *
     * max_active_loans is stored as a configuration type;
     * its value is held in loan_config.rate.
     */
    select
        count(*),
        min(config_record.rate),
        max(config_record.rate)
    into
        v_active_loan_config_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    from public.loan_config config_record
    where config_record.country_code =
          v_user.country_code
      and lower(
          btrim(
              config_record.config_type::text
          )
      ) = 'max_active_loans'
      and config_record.is_active = true;


    if v_active_loan_config_rows = 0
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


    if v_min_max_active_loans <= 0
       or trunc(
           v_min_max_active_loans
       ) <> v_min_max_active_loans
    then
        raise exception
            'INVALID_MAX_ACTIVE_LOANS';
    end if;


    v_max_active_loans :=
        v_min_max_active_loans::integer;


    /*
     * ==========================================================
     * ACTIVE LOAN BALANCES
     * ==========================================================
     *
     * Aggregate all active agent loans across all fiscal
     * years and count each loan once.
     */
    select
        count(
            distinct loan_record.id
        )::bigint,

        coalesce(
            sum(
                loan_entry_record.debit_principal
            ),
            0
        ) -
        coalesce(
            sum(
                loan_entry_record.credit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.debit_interest
            ),
            0
        ) -
        coalesce(
            sum(
                loan_entry_record.credit_interest
            ),
            0
        )
    into
        v_active_loans,
        v_principal,
        v_interest
    from public.loan loan_record
    left join public.loan_entry loan_entry_record
      on loan_entry_record.loan_id =
         loan_record.id
    where loan_record.user_id =
          v_user.id
      and loan_record.status =
          'active'::public."LoanStatus";


    v_active_loans :=
        greatest(
            coalesce(
                v_active_loans,
                0
            ),
            0
        );


    v_principal :=
        greatest(
            coalesce(
                v_principal,
                0
            ),
            0
        );


    v_interest :=
        greatest(
            coalesce(
                v_interest,
                0
            ),
            0
        );


    /*
     * ==========================================================
     * SVA ACCESS
     * ==========================================================
     */
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


    /*
     * ==========================================================
     * CURRENT COLLATERAL VALUE AND LTV
     * ==========================================================
     */
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
        v_health :=
            'LIQUIDATION_RISK';

    elsif v_ltv >= 70 then
        v_health :=
            'WARNING';

    else
        v_health :=
            'SAFE';
    end if;


    /*
     * ==========================================================
     * LOAN SUMMARY
     * ==========================================================
     */
    v_loan_summary :=
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(
                v_principal
            )::text,

            'interest_outstanding',
            trim_scale(
                v_interest
            )::text,

            'collateral_locked',
            trim_scale(
                v_locked_tokens
            )::text,

            'required_collateral',
            to_char(
                v_required_collateral,
                'FM999999999999999999999999990.000000'
            ),

            'ltv_percent',
            to_char(
                round(
                    v_ltv,
                    2
                ),
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
                        round(
                            v_total_tokens,
                            6
                        ),
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
                        round(
                            v_locked_tokens,
                            6
                        ),
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
                        round(
                            v_available_tokens,
                            6
                        ),
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


    /*
     * ==========================================================
     * RETURN DASHBOARD
     * ==========================================================
     */
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

CREATE OR REPLACE FUNCTION public.build_my_customer_dashboard(
    p_token_balance text,
    p_gas_balance text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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

    /*
     * Additional pooled collateral currently required
     * across all active loans.
     *
     * Calculated by the shared collateral function.
     */
    v_required_collateral numeric := 0;

    /* Loyalty values used by transfer-fee eligibility. */
    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    /* Current active loan access configuration. */
    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_min_max_active_loans numeric;
    v_max_max_active_loans numeric;
    v_max_active_loans integer;
    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;

begin
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;


    /*
     * ==========================================================
     * RESOLVE AND AUTHORIZE ACTIVE CUSTOMER
     * ==========================================================
     */
    select
        user_record.*
    into
        v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(
          role_record.name
      ) = 'customer'
    limit 1;


    if not found then
        raise exception using
            errcode = '42501',
            message = 'CUSTOMER_NOT_AUTHORIZED';
    end if;


    /*
     * ==========================================================
     * PARSE BLOCKCHAIN GOLD BALANCE
     * ==========================================================
     */
    begin
        v_total_tokens :=
            coalesce(
                nullif(
                    trim(
                        p_token_balance
                    ),
                    ''
                ),
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


    /*
     * ==========================================================
     * CURRENT POOLED COLLATERAL
     * ==========================================================
     */
    select
        coalesce(
            collateral_record.locked_tokens,
            0
        )
    into
        v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id =
          v_user.id
    limit 1;


    v_locked_tokens :=
        greatest(
            coalesce(
                v_locked_tokens,
                0
            ),
            0
        );


    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_locked_tokens,
            0
        );


    /*
     * ==========================================================
     * GOLD PRICE
     * ==========================================================
     */
    select
        coalesce(
            rate_record.rate_to_usd,
            0
        )
    into
        v_gold_price
    from public.current_rates rate_record
    where lower(
        rate_record.code
    ) = 'gold'
    limit 1;


    v_gold_price :=
        coalesce(
            v_gold_price,
            0
        );


    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * REQUIRED COLLATERAL
     * ==========================================================
     *
     * Use the common pooled-collateral calculation rather
     * than duplicating the formula in the dashboard.
     */
    v_required_collateral :=
        public.calculate_required_collateral(
            v_user.id
        );


    /*
     * ==========================================================
     * WALLET BALANCES
     * ==========================================================
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
        where wallet_record.user_id =
              v_user.id
    loop
        if lower(
            v_wallet.currency_code
        ) = 'usd'
        then
            v_balance :=
                coalesce(
                    v_wallet.balance,
                    0
                );

            v_usd_value :=
                v_balance;

        else
            select
                rate_record.rate_to_usd
            into
                v_rate
            from public.current_rates rate_record
            where lower(
                rate_record.code
            ) =
            lower(
                v_wallet.currency_code
            )
            limit 1;


            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_%',
                    upper(
                        v_wallet.currency_code
                    );
            end if;


            if lower(
                v_wallet.currency_code
            ) = 'gold'
            then
                v_balance :=
                    v_total_tokens;

                v_usd_value :=
                    v_balance *
                    v_rate;

            else
                v_balance :=
                    coalesce(
                        v_wallet.balance,
                        0
                    );

                v_usd_value :=
                    v_balance /
                    v_rate;
            end if;
        end if;


        v_balances :=
            v_balances ||
            jsonb_build_object(
                lower(
                    v_wallet.currency_code
                ),
                jsonb_build_object(
                    'balance',
                    trim_scale(
                        v_balance
                    )::text,

                    'usd_value',
                    to_char(
                        round(
                            v_usd_value,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                )
            );
    end loop;


    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     *
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
    where account_record.user_id =
          v_user.id
    limit 1;


    v_available_points :=
        greatest(
            coalesce(
                v_available_points,
                0
            ),
            0
        );


    v_tier_points :=
        greatest(
            coalesce(
                v_tier_points,
                0
            ),
            0
        );


    v_lifetime_earned_points :=
        greatest(
            coalesce(
                v_lifetime_earned_points,
                0
            ),
            0
        );


    v_loyalty_level :=
        coalesce(
            nullif(
                btrim(
                    v_loyalty_level
                ),
                ''
            ),
            'bronze'
        );


    v_loyalty_account_active :=
        coalesce(
            v_loyalty_account_active,
            false
        );


    /*
     * ==========================================================
     * MAXIMUM ACTIVE LOANS CONFIGURATION
     * ==========================================================
     *
     * fiscal_year and period are historical attributes and
     * must not select the live borrowing limit.
     *
     * max_active_loans is stored as a configuration type;
     * its value is held in loan_config.rate.
     */
    select
        count(*),
        min(config_record.rate),
        max(config_record.rate)
    into
        v_active_loan_config_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    from public.loan_config config_record
    where config_record.country_code =
          v_user.country_code
      and lower(
          btrim(
              config_record.config_type::text
          )
      ) = 'max_active_loans'
      and config_record.is_active = true;


    if v_active_loan_config_rows = 0
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


    if v_min_max_active_loans <= 0
       or trunc(
           v_min_max_active_loans
       ) <> v_min_max_active_loans
    then
        raise exception
            'INVALID_MAX_ACTIVE_LOANS';
    end if;


    v_max_active_loans :=
        v_min_max_active_loans::integer;


    /*
     * ==========================================================
     * ACTIVE LOAN BALANCES
     * ==========================================================
     *
     * Aggregate all active loans across all fiscal years and
     * count each active facility once, regardless of how many
     * loan_entry rows it contains.
     */
    select
        count(
            distinct loan_record.id
        )::bigint,

        coalesce(
            sum(
                entry_record.debit_principal
            ),
            0
        ) -
        coalesce(
            sum(
                entry_record.credit_principal
            ),
            0
        ),

        coalesce(
            sum(
                entry_record.debit_interest
            ),
            0
        ) -
        coalesce(
            sum(
                entry_record.credit_interest
            ),
            0
        )
    into
        v_active_loans,
        v_principal,
        v_interest
    from public.loan loan_record
    left join public.loan_entry entry_record
      on entry_record.loan_id =
         loan_record.id
    where loan_record.user_id =
          v_user.id
      and loan_record.status =
          'active'::public."LoanStatus";


    v_active_loans :=
        greatest(
            coalesce(
                v_active_loans,
                0
            ),
            0
        );


    v_principal :=
        greatest(
            coalesce(
                v_principal,
                0
            ),
            0
        );


    v_interest :=
        greatest(
            coalesce(
                v_interest,
                0
            ),
            0
        );


    /*
     * ==========================================================
     * SVA ACCESS
     * ==========================================================
     */
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


    /*
     * ==========================================================
     * CURRENT COLLATERAL VALUE AND LTV
     * ==========================================================
     */
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
        v_health :=
            'LIQUIDATION_RISK';

    elsif v_ltv >= 70 then
        v_health :=
            'WARNING';

    else
        v_health :=
            'SAFE';
    end if;


    /*
     * ==========================================================
     * SUPPORTED FIAT CURRENCIES
     * ==========================================================
     */
    select
        coalesce(
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
                order by
                    supported_record.currency_code
            ),
            '[]'::jsonb
        )
    into
        v_currencies
    from public.country_currencies country_currency_record
    join public.supported_currency supported_record
      on lower(
          supported_record.currency_code
      ) =
         lower(
             country_currency_record.currency_code
         )
    where country_currency_record.country_code =
          v_user.country_code
      and country_currency_record.is_active = true
      and supported_record.currency_category =
          'fiat'::public."CurrencyCategory";


    /*
     * ==========================================================
     * RETURN DASHBOARD
     * ==========================================================
     */
    return jsonb_build_object(
        'wallet',
        jsonb_build_object(
            'wallet_address',
            v_user.wallet_address,

            'token_balance',
            trim_scale(
                v_total_tokens
            )::text,

            'gas_balance',
            coalesce(
                nullif(
                    trim(
                        p_gas_balance
                    ),
                    ''
                ),
                '0'
            ),

            'balances',
            v_balances,

            'available_tokens',
            trim_scale(
                v_available_tokens
            )::text
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
            trim_scale(
                v_principal
            )::text,

            'interest_outstanding',
            trim_scale(
                v_interest
            )::text,

            'collateral_locked',
            trim_scale(
                v_locked_tokens
            )::text,

            'required_collateral',
            to_char(
                v_required_collateral,
                'FM999999999999999999999999990.000000'
            ),

            'ltv_percent',
            to_char(
                round(
                    v_ltv,
                    2
                ),
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
                        round(
                            v_total_tokens,
                            6
                        ),
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
                        round(
                            v_locked_tokens,
                            6
                        ),
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
                        round(
                            v_available_tokens,
                            6
                        ),
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

CREATE OR REPLACE FUNCTION public.build_my_vendor_dashboard(
    p_token_balance text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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

    /*
     * Additional pooled collateral currently required
     * across all active loans.
     *
     * Calculated by the shared collateral function.
     */
    v_required_collateral numeric := 0;

    /* Loyalty values used by transfer-fee eligibility. */
    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_loyalty_level text := 'bronze';
    v_loyalty_account_active boolean := false;

    /* Current active loan access configuration. */
    v_active_loans bigint := 0;
    v_active_loan_config_rows bigint := 0;
    v_min_max_active_loans numeric;
    v_max_max_active_loans numeric;
    v_max_active_loans integer;
    v_sva_access_utilisation numeric := 0;
    v_can_access_sva boolean := false;

begin
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;


    /*
     * ==========================================================
     * RESOLVE AND AUTHORIZE ACTIVE VENDOR
     * ==========================================================
     */
    select
        user_record.*
    into
        v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(
          role_record.name::text
      ) = 'vendor'
    limit 1;


    if not found then
        raise exception using
            errcode = '42501',
            message = 'VENDOR_NOT_AUTHORIZED';
    end if;


    /*
     * ==========================================================
     * PARSE BLOCKCHAIN GOLD TOKEN BALANCE
     * ==========================================================
     */
    begin
        v_total_tokens :=
            coalesce(
                nullif(
                    btrim(
                        p_token_balance
                    ),
                    ''
                ),
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


    /*
     * ==========================================================
     * SUPPORTED CURRENCIES
     * ==========================================================
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );


    /*
     * ==========================================================
     * WALLET CONTAINERS
     * ==========================================================
     *
     * Preserve the existing agent, merchant and customer
     * wallet containers.
     */
    v_wallet :=
        jsonb_build_object(
            'agent',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),
            'merchant',
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


    /*
     * ==========================================================
     * DAILY SUMMARY
     * ==========================================================
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );


    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     *
     * Spendable points determine whether the vendor may
     * select points for a quoted customer-wallet transfer.
     *
     * A vendor without a loyalty account has zero points.
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
    where account_record.user_id =
          v_user.id
    limit 1;


    v_available_points :=
        greatest(
            coalesce(
                v_available_points,
                0
            ),
            0
        );


    v_tier_points :=
        greatest(
            coalesce(
                v_tier_points,
                0
            ),
            0
        );


    v_lifetime_earned_points :=
        greatest(
            coalesce(
                v_lifetime_earned_points,
                0
            ),
            0
        );


    v_loyalty_level :=
        coalesce(
            nullif(
                btrim(
                    v_loyalty_level
                ),
                ''
            ),
            'bronze'
        );


    v_loyalty_account_active :=
        coalesce(
            v_loyalty_account_active,
            false
        );


    /*
     * ==========================================================
     * CURRENT POOLED COLLATERAL
     * ==========================================================
     */
    select
        coalesce(
            collateral_record.locked_tokens,
            0
        )
    into
        v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id =
          v_user.id
    limit 1;


    v_locked_tokens :=
        greatest(
            coalesce(
                v_locked_tokens,
                0
            ),
            0
        );


    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_locked_tokens,
            0
        );


    /*
     * ==========================================================
     * CURRENT GOLD PRICE
     * ==========================================================
     */
    select
        coalesce(
            rate_record.rate_to_usd,
            0
        )
    into
        v_gold_price
    from public.current_rates rate_record
    where lower(
        btrim(
            rate_record.code
        )
    ) = 'gold'
    limit 1;


    v_gold_price :=
        coalesce(
            v_gold_price,
            0
        );


    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * REQUIRED COLLATERAL
     * ==========================================================
     *
     * Shared pooled-collateral calculation.
     *
     * The helper calculates the current collateral shortage
     * across all active loans using:
     *
     * - current principal outstanding;
     * - current interest outstanding;
     * - each loan's max_ltv_percent;
     * - current Gold price;
     * - actual collateral.locked_tokens.
     */
    v_required_collateral :=
        public.calculate_required_collateral(
            v_user.id
        );


    /*
     * ==========================================================
     * MAXIMUM ACTIVE LOANS CONFIGURATION
     * ==========================================================
     *
     * fiscal_year and period are historical attributes and
     * must not select the live borrowing limit.
     *
     * max_active_loans is stored as a configuration type;
     * its value is held in loan_config.rate.
     */
    select
        count(*),
        min(config_record.rate),
        max(config_record.rate)
    into
        v_active_loan_config_rows,
        v_min_max_active_loans,
        v_max_max_active_loans
    from public.loan_config config_record
    where config_record.country_code =
          v_user.country_code
      and lower(
          btrim(
              config_record.config_type::text
          )
      ) = 'max_active_loans'
      and config_record.is_active = true;


    if v_active_loan_config_rows = 0
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


    if v_min_max_active_loans <= 0
       or trunc(
           v_min_max_active_loans
       ) <> v_min_max_active_loans
    then
        raise exception
            'INVALID_MAX_ACTIVE_LOANS';
    end if;


    v_max_active_loans :=
        v_min_max_active_loans::integer;


    /*
     * ==========================================================
     * ACTIVE LOAN BALANCES
     * ==========================================================
     *
     * Aggregate all active vendor loans across all fiscal
     * years and count each loan once.
     */
    select
        count(
            distinct loan_record.id
        )::bigint,

        coalesce(
            sum(
                loan_entry_record.debit_principal
            ),
            0
        ) -
        coalesce(
            sum(
                loan_entry_record.credit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.debit_interest
            ),
            0
        ) -
        coalesce(
            sum(
                loan_entry_record.credit_interest
            ),
            0
        )
    into
        v_active_loans,
        v_principal,
        v_interest
    from public.loan loan_record
    left join public.loan_entry loan_entry_record
      on loan_entry_record.loan_id =
         loan_record.id
    where loan_record.user_id =
          v_user.id
      and loan_record.status =
          'active'::public."LoanStatus";


    v_active_loans :=
        greatest(
            coalesce(
                v_active_loans,
                0
            ),
            0
        );


    v_principal :=
        greatest(
            coalesce(
                v_principal,
                0
            ),
            0
        );


    v_interest :=
        greatest(
            coalesce(
                v_interest,
                0
            ),
            0
        );


    /*
     * ==========================================================
     * SVA ACCESS
     * ==========================================================
     */
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


    /*
     * ==========================================================
     * COLLATERAL VALUE AND LTV
     * ==========================================================
     */
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
        v_health :=
            'LIQUIDATION_RISK';

    elsif v_ltv >= 70 then
        v_health :=
            'WARNING';

    else
        v_health :=
            'SAFE';
    end if;


    /*
     * ==========================================================
     * LOAN SUMMARY
     * ==========================================================
     *
     * Uses the same shared Flutter LoanSummary shape as the
     * agent dashboard.
     */
    v_loan_summary :=
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(
                v_principal
            )::text,

            'interest_outstanding',
            trim_scale(
                v_interest
            )::text,

            'collateral_locked',
            trim_scale(
                v_locked_tokens
            )::text,

            'required_collateral',
            to_char(
                v_required_collateral,
                'FM999999999999999999999999990.000000'
            ),

            'ltv_percent',
            to_char(
                round(
                    v_ltv,
                    2
                ),
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
                        round(
                            v_total_tokens,
                            6
                        ),
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
                        round(
                            v_locked_tokens,
                            6
                        ),
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
                        round(
                            v_available_tokens,
                            6
                        ),
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


    /*
     * ==========================================================
     * RETURN DASHBOARD
     * ==========================================================
     */
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