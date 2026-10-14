create or replace function public.build_user_wallet_balance(
    p_user_id text
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
    v_row record;

    v_owner_type text;
    v_currency_code text;

    v_balance numeric;
    v_rate numeric;
    v_usd_value numeric;

    v_wallet jsonb := '{}'::jsonb;
begin
    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception 'USER_ID_IS_REQUIRED';
    end if;

    for v_row in
        select
            lower(w.owner_type::text)
                as owner_type,

            lower(btrim(w.currency_code))
                as currency_code,

            coalesce(w.balance, 0)::numeric
                as balance

        from public.wallet w
        where w.user_id = p_user_id

        order by
            w.owner_type,
            w.currency_code
    loop
        v_owner_type :=
            v_row.owner_type;

        v_currency_code :=
            v_row.currency_code;

        v_balance :=
            v_row.balance;

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
                    'MISSING_RATE_%',
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

        /*
         * Create the wallet-owner container when it
         * does not already exist.
         */
        if not v_wallet ? v_owner_type then
            v_wallet :=
                jsonb_set(
                    v_wallet,
                    array[v_owner_type],
                    jsonb_build_object(
                        'balances',
                        '{}'::jsonb
                    ),
                    true
                );
        end if;

        /*
         * Add the currency balance.
         */
        v_wallet :=
            jsonb_set(
                v_wallet,
                array[
                    v_owner_type,
                    'balances',
                    v_currency_code
                ],
                jsonb_build_object(
                    'balance',
                    trim_scale(v_balance)::text,

                    'usd_value',
                    to_char(
                        round(v_usd_value, 2),
                        'FM999999999999999999999999990.00'
                    )
                ),
                true
            );
    end loop;

    return v_wallet;
end;
$function$;

create or replace function public.build_country_supported_currencies(
    p_country_code text
)
returns jsonb
language sql
stable
set search_path to ''
as $function$
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
    from public.country_currencies cc
    join public.supported_currency sc
      on lower(sc.currency_code) =
         lower(cc.currency_code)
    where cc.country_code =
          p_country_code
      and cc.is_active = true
      and sc.is_active = true;
$function$;

create or replace function public.build_user_daily_summary(
    p_user_id text
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
    v_row record;

    v_currency_code text;
    v_amount numeric;
    v_rate numeric;
    v_usd_value numeric;

    v_summary_amount jsonb;

    v_deposits jsonb := '{}'::jsonb;
    v_withdrawals jsonb := '{}'::jsonb;
    v_payments jsonb := '{}'::jsonb;

    v_deposit_counts jsonb := '{}'::jsonb;
    v_withdrawal_counts jsonb := '{}'::jsonb;
    v_payment_counts jsonb := '{}'::jsonb;

    v_start_of_day timestamptz;
    v_start_of_next_day timestamptz;
begin
    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception 'USER_ID_IS_REQUIRED';
    end if;

    v_start_of_day :=
        date_trunc(
            'day',
            current_timestamp
        );

    v_start_of_next_day :=
        v_start_of_day +
        interval '1 day';

    for v_row in
        select
            we.transaction_type,

            lower(btrim(we.currency_code))
                as currency_code,

            coalesce(
                sum(we.debit),
                0
            )::numeric as total_debit,

            coalesce(
                sum(we.credit),
                0
            )::numeric as total_credit,

            count(
                distinct we.document_number
            )::integer as transaction_count

        from public.wallet_entry we

        where we.created_by =
              p_user_id

          and we.transaction_type in (
              'cash_deposit'::public."TransactionType",
              'cash_withdrawal'::public."TransactionType",
              'merchant_payment'::public."TransactionType"
          )

          and we.created_at >=
              v_start_of_day

          and we.created_at <
              v_start_of_next_day

        group by
            we.transaction_type,
            lower(btrim(we.currency_code))

        order by
            we.transaction_type,
            lower(btrim(we.currency_code))
    loop
        v_currency_code :=
            v_row.currency_code;

        case v_row.transaction_type
            when 'cash_deposit'::public."TransactionType"
            then
                v_amount :=
                    v_row.total_debit;

            when 'cash_withdrawal'::public."TransactionType"
            then
                v_amount :=
                    v_row.total_credit;

            when 'merchant_payment'::public."TransactionType"
            then
                v_amount :=
                    v_row.total_credit;

            else
                continue;
        end case;

        if v_currency_code = 'usd' then
            v_usd_value :=
                v_amount;
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
                    'MISSING_RATE_%',
                    upper(v_currency_code);
            end if;

            /*
             * Preserve the original daily-summary
             * conversion rule.
             */
            v_usd_value :=
                v_amount / v_rate;
        end if;

        v_summary_amount :=
            jsonb_build_object(
                'balance',
                trim_scale(v_amount)::text,

                'usd_value',
                to_char(
                    round(v_usd_value, 2),
                    'FM999999999999999999999999990.00'
                )
            );

        case v_row.transaction_type
            when 'cash_deposit'::public."TransactionType"
            then
                v_deposits :=
                    v_deposits ||
                    jsonb_build_object(
                        v_currency_code,
                        v_summary_amount
                    );

                v_deposit_counts :=
                    v_deposit_counts ||
                    jsonb_build_object(
                        v_currency_code,
                        v_row.transaction_count
                    );

            when 'cash_withdrawal'::public."TransactionType"
            then
                v_withdrawals :=
                    v_withdrawals ||
                    jsonb_build_object(
                        v_currency_code,
                        v_summary_amount
                    );

                v_withdrawal_counts :=
                    v_withdrawal_counts ||
                    jsonb_build_object(
                        v_currency_code,
                        v_row.transaction_count
                    );

            when 'merchant_payment'::public."TransactionType"
            then
                v_payments :=
                    v_payments ||
                    jsonb_build_object(
                        v_currency_code,
                        v_summary_amount
                    );

                v_payment_counts :=
                    v_payment_counts ||
                    jsonb_build_object(
                        v_currency_code,
                        v_row.transaction_count
                    );

            else
                continue;
        end case;
    end loop;

    return jsonb_build_object(
        'deposits',
        v_deposits,

        'withdrawals',
        v_withdrawals,

        'payments',
        v_payments,

        'deposit_count',
        v_deposit_counts,

        'withdrawal_count',
        v_withdrawal_counts,

        'payment_count',
        v_payment_counts
    );
end;
$function$;


create or replace function public.build_my_agent_dashboard()
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
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Resolve the authenticated application user and
     * validate the agent role.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) = 'agent'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'AGENT_NOT_AUTHORIZED';
    end if;

    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Preserve the original empty agent/customer
     * wallet containers.
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
        ) ||
        public.build_user_wallet_balance(
            v_user.id
        );

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
on function public.build_user_wallet_balance(text)
from public, anon, authenticated;

revoke all
on function public.build_country_supported_currencies(text)
from public, anon, authenticated;

revoke all
on function public.build_user_daily_summary(text)
from public, anon, authenticated;


revoke all
on function public.build_my_agent_dashboard()
from public, anon;

grant execute
on function public.build_my_agent_dashboard()
to authenticated;



