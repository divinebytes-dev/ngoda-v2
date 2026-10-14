create or replace function public.fetch_my_merchant_dashboard()
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

    v_is_credit_agent boolean := false;
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
     * Resolve the authenticated application user and enforce
     * active merchant status.
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
      ) =
              'merchant'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'MERCHANT_NOT_AUTHORIZED';
    end if;

    /*
     * A merchant is a credit agent when at least one active
     * credit-agent account exists.
     *
     * Approval is merchant-wide. The separate currency rows
     * only maintain balances in their correct denomination.
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
     * Same reusable currency function used by agent.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Merchant defaults:
     *
     * - merchant wallet
     * - agent-operation wallet
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

        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

        'dailySummary',
        v_daily_summary
    );
end;
$function$;


revoke all on function
    public.fetch_my_merchant_dashboard()
from public;

revoke all on function
    public.fetch_my_merchant_dashboard()
from anon;

grant execute on function
    public.fetch_my_merchant_dashboard()
to authenticated;