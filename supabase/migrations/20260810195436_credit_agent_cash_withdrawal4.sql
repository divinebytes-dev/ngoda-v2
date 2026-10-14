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

    v_deposits jsonb :=
        '{}'::jsonb;

    v_withdrawals jsonb :=
        '{}'::jsonb;

    v_payments jsonb :=
        '{}'::jsonb;

    v_deposit_counts jsonb :=
        '{}'::jsonb;

    v_withdrawal_counts jsonb :=
        '{}'::jsonb;

    v_payment_counts jsonb :=
        '{}'::jsonb;

    v_start_of_day timestamptz;
    v_start_of_next_day timestamptz;
begin
    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception
            'USER_ID_IS_REQUIRED';
    end if;

    v_start_of_day :=
        date_trunc(
            'day',
            current_timestamp
        );

    v_start_of_next_day :=
        v_start_of_day +
        interval '1 day';

    /*
     * First classify related transaction types into the
     * same dashboard category.
     *
     * This prevents normal and credit-agent transactions
     * in the same currency from overwriting each other.
     */
    for v_row in
        with classified_entries as (
            select
                case
                    when wallet_entry_record.transaction_type in (
                        'cash_deposit'::public."TransactionType",
                        'credit_agent_cash_deposit'::public."TransactionType"
                    )
                    then 'deposit'

                    when wallet_entry_record.transaction_type in (
                        'cash_withdrawal'::public."TransactionType",
                        'credit_agent_cash_withdrawal'::public."TransactionType"
                    )
                    then 'withdrawal'

                    when wallet_entry_record.transaction_type =
                         'merchant_payment'::public."TransactionType"
                    then 'payment'
                end as summary_type,

                lower(
                    btrim(
                        wallet_entry_record.currency_code
                    )
                ) as currency_code,

                wallet_entry_record.document_number,

                coalesce(
                    wallet_entry_record.debit,
                    0
                )::numeric as debit,

                coalesce(
                    wallet_entry_record.credit,
                    0
                )::numeric as credit

            from public.wallet_entry
                wallet_entry_record

            join public.wallet
                wallet_record
              on wallet_record.id =
                 wallet_entry_record.wallet_id

            where wallet_record.user_id =
                  p_user_id

              and wallet_entry_record.transaction_type in (
                  'cash_deposit'::public."TransactionType",
                  'credit_agent_cash_deposit'::public."TransactionType",
                  'cash_withdrawal'::public."TransactionType",
                  'credit_agent_cash_withdrawal'::public."TransactionType",
                  'merchant_payment'::public."TransactionType"
              )

              and wallet_entry_record.created_at >=
                  v_start_of_day

              and wallet_entry_record.created_at <
                  v_start_of_next_day
        )

        select
            classified_entry.summary_type,

            classified_entry.currency_code,

            coalesce(
                sum(
                    case
                        when classified_entry.summary_type =
                             'deposit'
                        then classified_entry.debit

                        when classified_entry.summary_type in (
                            'withdrawal',
                            'payment'
                        )
                        then classified_entry.credit

                        else 0
                    end
                ),
                0
            )::numeric as amount,

            count(
                distinct classified_entry.document_number
            )::integer as transaction_count

        from classified_entries
            classified_entry

        where classified_entry.summary_type
              is not null

        group by
            classified_entry.summary_type,
            classified_entry.currency_code

        order by
            classified_entry.summary_type,
            classified_entry.currency_code
    loop
        v_currency_code :=
            v_row.currency_code;

        v_amount :=
            coalesce(
                v_row.amount,
                0
            );

        /*
         * Ignore zero-value groups.
         */
        if v_amount = 0 then
            continue;
        end if;

        /*
         * Convert the transaction total to its USD
         * equivalent using the existing conversion rule.
         */
        if v_currency_code = 'usd' then
            v_usd_value :=
                v_amount;
        else
            v_rate :=
                null;

            select current_rate_record.rate_to_usd
            into v_rate
            from public.current_rates
                current_rate_record
            where lower(
                btrim(
                    current_rate_record.code
                )
            ) =
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
             * Preserve the existing daily-summary
             * conversion rule.
             */
            v_usd_value :=
                v_amount /
                v_rate;
        end if;

        v_summary_amount :=
            jsonb_build_object(
                'balance',
                trim_scale(
                    v_amount
                )::text,

                'usd_value',
                to_char(
                    round(
                        v_usd_value,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                )
            );

        case v_row.summary_type
            when 'deposit'
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

            when 'withdrawal'
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

            when 'payment'
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