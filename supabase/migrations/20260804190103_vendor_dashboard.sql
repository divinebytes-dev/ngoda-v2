create or replace function public.build_my_vendor_dashboard()
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
     * enforce active vendor status.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) = 'vendor'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'VENDOR_NOT_AUTHORIZED';
    end if;

    /*
     * Reuse the same supported-currency function.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Preserve the exact vendor wallet containers:
     *
     * - agent
     * - merchant
     * - customer
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
        ) ||
        public.build_user_wallet_balance(
            v_user.id
        );

    /*
     * The vendor daily summary is identical to the
     * agent and merchant daily summaries.
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
on function public.build_my_vendor_dashboard()
from public, anon;

grant execute
on function public.build_my_vendor_dashboard()
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

