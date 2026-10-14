CREATE OR REPLACE FUNCTION public.fetch_my_credit_agent_balances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_merchant record;
    v_account record;

    v_balances jsonb;
    v_credit_agents jsonb :=
        '[]'::jsonb;

    v_rate numeric;
    v_cash_holding_usd numeric;
    v_receivable_usd numeric;

    v_total_entries integer := 0;
begin
    /*
     * Authentication and authorization.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch merchants in the Accounts user's country
     * who have at least one non-zero credit-agent balance.
     *
     * Inactive credit-agent accounts are included because
     * outstanding balances must remain visible.
     */
    for v_merchant in
        select
            merchant_record.id as user_id,
            merchant_record.email,
            merchant_record.phone,
            merchant_record.first_name,
            merchant_record.surname,
            merchant_record.address,
            merchant_record.country_code,
            merchant_record.status

        from public.users merchant_record

        join public.user_role role_record
          on role_record.id =
             merchant_record.role_id

        where lower(
            role_record.name::text
        ) = 'merchant'

          and merchant_record.country_code = (
              select accounts_record.country_code
              from public.users accounts_record
              where accounts_record.id =
                    auth.uid()::text
              limit 1
          )

          and exists (
              select 1
              from public.credit_agent_account
                  account_record
              where account_record.merchant_id =
                    merchant_record.id

                and account_record.country_code =
                    merchant_record.country_code

                and (
                    coalesce(
                        account_record.receivable_balance,
                        0
                    ) <> 0

                    or

                    coalesce(
                        account_record.cash_holding_balance,
                        0
                    ) <> 0
                )
          )

        order by
            merchant_record.first_name,
            merchant_record.surname,
            merchant_record.email
    loop
        v_balances :=
            '{}'::jsonb;

        /*
         * Build the merchant balances by currency.
         *
         * Only currencies with a non-zero balance are
         * returned.
         */
        for v_account in
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
                  v_merchant.user_id

              and account_record.country_code =
                  v_merchant.country_code

              and (
                  coalesce(
                      account_record.receivable_balance,
                      0
                  ) <> 0

                  or

                  coalesce(
                      account_record.cash_holding_balance,
                      0
                  ) <> 0
              )

            order by
                lower(
                    btrim(
                        account_record.currency_code
                    )
                )
        loop
            /*
             * Convert balances to USD using the same
             * dashboard conversion rule.
             */
            if v_account.currency_code = 'usd' then
                v_cash_holding_usd :=
                    v_account.cash_holding_balance;

                v_receivable_usd :=
                    v_account.receivable_balance;
            else
                select rate_record.rate_to_usd
                into v_rate
                from public.current_rates rate_record
                where lower(
                    btrim(
                        rate_record.code
                    )
                ) =
                    v_account.currency_code
                limit 1;

                if not found
                   or v_rate is null
                   or v_rate = 0
                then
                    raise exception
                        'MISSING_RATE_%',
                        upper(
                            v_account.currency_code
                        );
                end if;

                v_cash_holding_usd :=
                    v_account.cash_holding_balance /
                    v_rate;

                v_receivable_usd :=
                    v_account.receivable_balance /
                    v_rate;
            end if;

            v_balances :=
                v_balances ||
                jsonb_build_object(
                    v_account.currency_code,

                    jsonb_build_object(
                        'cashOwed',
                        jsonb_build_object(
                            'balance',
                            trim_scale(
                                v_account.cash_holding_balance
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
                                v_account.receivable_balance
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
                        v_account.is_active
                    )
                );
        end loop;

        v_credit_agents :=
            v_credit_agents ||
            jsonb_build_array(
                jsonb_build_object(
                    'user_id',
                    v_merchant.user_id,

                    'email',
                    v_merchant.email,

                    'phone',
                    v_merchant.phone,

                    'first_name',
                    v_merchant.first_name,

                    'surname',
                    v_merchant.surname,

                    'address',
                    v_merchant.address,

                    'country_code',
                    v_merchant.country_code,

                    'status',
                    v_merchant.status,

                    'balances',
                    v_balances
                )
            );

        v_total_entries :=
            v_total_entries + 1;
    end loop;

    return jsonb_build_object(
        'creditAgents',
        v_credit_agents,

        'totalEntries',
        v_total_entries
    );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.fetch_my_credit_agent_balances()
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_credit_agent_balances()
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_credit_agent_balances()
TO authenticated;