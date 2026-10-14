CREATE OR REPLACE FUNCTION public.build_user_daily_summary(p_user_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
              'credit_agent_cash_deposit'::public."TransactionType",
              'cash_withdrawal'::public."TransactionType",
              'credit_agent_cash_withdrawal'::public."TransactionType",
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

            when 'credit_agent_cash_deposit'::public."TransactionType"
            then
                v_amount :=
                    v_row.total_debit;

            when 'cash_withdrawal'::public."TransactionType"
            then
                v_amount :=
                    v_row.total_credit;

            when 'credit_agent_cash_withdrawal'::public."TransactionType"
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

            when 'credit_agent_cash_deposit'::public."TransactionType"
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

            when 'credit_agent_cash_withdrawal'::public."TransactionType"
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
$function$
