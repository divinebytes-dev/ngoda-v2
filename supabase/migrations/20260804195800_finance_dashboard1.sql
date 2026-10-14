create or replace function public.build_my_finance_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_row record;

    v_currency_code text;
    v_balance numeric;
    v_rate numeric;
    v_usd_value numeric;

    v_balance_result jsonb;

    v_bank jsonb := '{}'::jsonb;
    v_treasury jsonb := '{}'::jsonb;
    v_customer jsonb := '{}'::jsonb;

    v_agent_asset jsonb := '{}'::jsonb;
    v_agent_float jsonb := '{}'::jsonb;

    v_credit_agent_float jsonb :=
        '{}'::jsonb;

    v_credit_agent_cash jsonb :=
        '{}'::jsonb;

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
     * enforce active finance status.
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
          'finance'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'FINANCE_NOT_AUTHORIZED';
    end if;

    /*
     * Preserve the original behaviour:
     * aggregate across every fiscal year.
     */
    for v_row in
        select
            fe.gl_account_code,

            lower(btrim(fe.currency_code))
                as currency_code,

            abs(
                coalesce(
                    sum(fe.debit),
                    0
                ) -
                coalesce(
                    sum(fe.credit),
                    0
                )
            )::numeric as balance

        from public.financial_entry fe

        where fe.country_code =
              v_user.country_code

          and fe.gl_account_code in (
              '1001000',
              '1002000',
              '2002000',
              '1003000',
              '2001000',
              '1007000',
              '1008000'
          )

        group by
            fe.gl_account_code,
            lower(btrim(fe.currency_code))

        order by
            fe.gl_account_code,
            lower(btrim(fe.currency_code))
    loop
        v_currency_code :=
            v_row.currency_code;

        v_balance :=
            coalesce(v_row.balance, 0);

        /*
         * Convert to USD using the original rules.
         */
        if v_currency_code = 'usd' then
            v_usd_value :=
                v_balance;
        else
            select cr.rate_to_usd
            into v_rate
            from public.current_rates cr
            where lower(btrim(cr.code)) =
                  v_currency_code
            limit 1;

            if not found
               or v_rate is null
               or v_rate = 0
            then
                raise exception
                    'MISSING_RATE_FOR_CURRENCY_%',
                    upper(v_currency_code);
            end if;

            if v_currency_code = 'gold' then
                v_usd_value :=
                    v_balance * v_rate;
            else
                v_usd_value :=
                    v_balance / v_rate;
            end if;
        end if;

        v_balance_result :=
            jsonb_build_object(
                'balance',
                trim_scale(v_balance)::text,

                'usd_value',
                trim_scale(v_usd_value)::text
            );

        case v_row.gl_account_code
            when '1001000' then
                v_bank :=
                    v_bank ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            when '1002000' then
                v_treasury :=
                    v_treasury ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            when '2002000' then
                v_customer :=
                    v_customer ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            when '1003000' then
                v_agent_asset :=
                    v_agent_asset ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            when '2001000' then
                v_agent_float :=
                    v_agent_float ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            /*
             * Corrected mappings.
             */
            when '1007000' then
                v_credit_agent_float :=
                    v_credit_agent_float ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );

            when '1008000' then
                v_credit_agent_cash :=
                    v_credit_agent_cash ||
                    jsonb_build_object(
                        v_currency_code,
                        v_balance_result
                    );
        end case;
    end loop;

    /*
     * Reuse the existing supported-currency function.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    return jsonb_build_object(
        'bank',
        v_bank,

        'treasury',
        v_treasury,

        'customer',
        v_customer,

        'agentAsset',
        v_agent_asset,

        'agentFloat',
        v_agent_float,

        'creditAgentFloat',
        v_credit_agent_float,

        'creditAgentCash',
        v_credit_agent_cash,

        'currencies',
        v_currencies
    );
end;
$function$;

revoke all
on function public.build_my_finance_dashboard()
from public, anon;

grant execute
on function public.build_my_finance_dashboard()
to authenticated;