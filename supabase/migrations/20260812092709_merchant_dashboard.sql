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

    v_is_credit_agent boolean := false;

    v_credit_agent_balances jsonb :=
        '{}'::jsonb;
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
      ) = 'merchant'
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
     * Return credit-agent balances by currency.
     *
     * cashOwed:
     * Company cash currently held by the merchant.
     *
     * receivableBalance:
     * Outstanding credit float owed by the merchant.
     *
     * Inactive accounts are intentionally included when
     * they still exist because deactivation must not hide
     * an outstanding balance.
     */
    select coalesce(
        jsonb_object_agg(
            balance_record.currency_code,
            jsonb_build_object(
                'cashOwed',
                trim_scale(
                    balance_record.cash_holding_balance
                )::text,

                'cashHoldingBalance',
                trim_scale(
                    balance_record.cash_holding_balance
                )::text,

                'receivableBalance',
                trim_scale(
                    balance_record.receivable_balance
                )::text,

                'isActive',
                balance_record.is_active
            )
            order by
                balance_record.currency_code
        ),
        '{}'::jsonb
    )
    into v_credit_agent_balances
    from (
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
    ) balance_record;

    /*
     * Supported country currencies.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Merchant wallet defaults:
     *
     * - merchant
     * - agent
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
     * Merchant and agent daily summaries share the same
     * implementation.
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

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