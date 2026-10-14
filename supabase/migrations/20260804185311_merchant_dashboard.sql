create or replace function public.build_my_merchant_dashboard()
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
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) = 'merchant'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'MERCHANT_NOT_AUTHORIZED';
    end if;

    /*
     * Same reusable currency function used by agent.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Merchant defaults are different from agent:
     *
     * merchant dashboard:
     * - merchant
     * - agent
     *
     * Existing wallet owner types returned by the
     * reusable function are added dynamically.
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
        ) ||
        public.build_user_wallet_balance(
            v_user.id
        );

    /*
     * The merchant and agent daily-summary implementations
     * are identical, so the same function is used.
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    return jsonb_build_object(
        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

        'dailySummary',
        v_daily_summary
    );
end;
$function$;


revoke all
on function public.build_my_merchant_dashboard()
from public, anon;

grant execute
on function public.build_my_merchant_dashboard()
to authenticated;


revoke all
on function public.build_user_wallet_balance(text)
from public, anon, authenticated;

revoke all
on function public.build_user_daily_summary(text)
from public, anon, authenticated;

revoke all
on function public.build_country_supported_currencies(text)
from public, anon, authenticated;


