CREATE OR REPLACE FUNCTION public.build_my_merchant_dashboard()
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

    v_is_credit_agent boolean :=
        false;

    v_credit_agent_balances jsonb :=
        '{}'::jsonb;

    v_credit_account record;

    v_rate numeric;
    v_cash_holding_usd numeric;
    v_receivable_usd numeric;
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
     * enforce active merchant status.
     */
    select user_record.*
    into v_user
    from public.users
        user_record
    join public.user_role
        role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
          auth.uid()::text

      and user_record.status =
          'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
          'merchant'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'MERCHANT_NOT_AUTHORIZED';
    end if;

    /*
     * Credit-agent status is merchant-wide.
     */
    select exists (
        select 1
        from public.credit_agent_account
            account_record
        where account_record.merchant_id =
              v_user.id

          and account_record.country_code =
              v_user.country_code

          and account_record.is_active =
              true
    )
    into v_is_credit_agent;

    /*
     * Build credit-agent balances by currency.
     *
     * Inactive accounts are included because deactivating
     * a credit agent must not hide an outstanding balance.
     */
    for v_credit_account in
        select
            lower(
                btrim(
                    account_record.currency_code
                )
            ) as currency_code,

            coalesce(
                account_record.cash_holding_balance,
                0
            )::numeric as cash_holding_balance,

            coalesce(
                account_record.receivable_balance,
                0
            )::numeric as receivable_balance,

            account_record.is_active

        from public.credit_agent_account
            account_record

        where account_record.merchant_id =
              v_user.id

          and account_record.country_code =
              v_user.country_code

        order by
            lower(
                btrim(
                    account_record.currency_code
                )
            )
    loop
        /*
         * Apply the same USD conversion used by the
         * existing daily-summary function.
         */
        if v_credit_account.currency_code = 'usd' then
            v_rate :=
                1;

            v_cash_holding_usd :=
                v_credit_account.cash_holding_balance;

            v_receivable_usd :=
                v_credit_account.receivable_balance;
        else
            select rate_record.rate_to_usd
            into v_rate
            from public.current_rates
                rate_record
            where lower(
                btrim(
                    rate_record.code
                )
            ) =
                v_credit_account.currency_code
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_%',
                    upper(
                        v_credit_account.currency_code
                    );
            end if;

            v_cash_holding_usd :=
                v_credit_account.cash_holding_balance /
                v_rate;

            v_receivable_usd :=
                v_credit_account.receivable_balance /
                v_rate;
        end if;

        v_credit_agent_balances :=
            v_credit_agent_balances ||
            jsonb_build_object(
                v_credit_account.currency_code,

                jsonb_build_object(
                    'cashOwed',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_credit_account.cash_holding_balance
                        )::text,

                        'usd_value',
                        to_char(
                            round(
                                v_cash_holding_usd,
                                2
                            ),
                            'FM999999999999999999999999990.00'
                        )
                    ),

                    'receivableBalance',
                    jsonb_build_object(
                        'balance',
                        trim_scale(
                            v_credit_account.receivable_balance
                        )::text,

                        'usd_value',
                        to_char(
                            round(
                                v_receivable_usd,
                                2
                            ),
                            'FM999999999999999999999999990.00'
                        )
                    ),

                    'isActive',
                    v_credit_account.is_active
                )
            );
    end loop;

    /*
     * Existing supported currencies.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Existing merchant wallets.
     */
    v_wallet :=
        jsonb_build_object(
            'merchant',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),

            'agent',
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
     * Existing daily summary.
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    /*
     * The original dashboard fields remain unchanged.
     * Credit-agent information is added separately.
     */
    return jsonb_build_object(
        'isCreditAgent',
        v_is_credit_agent,

        'creditAgent',
        jsonb_build_object(
            'balances',
            v_credit_agent_balances
        ),

        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

        'dailySummary',
        v_daily_summary
    );
end;
$function$;