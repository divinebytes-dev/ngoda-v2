-- Complete function replacement AFTER the KYC/index correction.
-- No index, configuration, amount or historical ledger changes.
BEGIN;
CREATE OR REPLACE FUNCTION public.enforce_transaction_limit(p_user_id text, p_fiscal_year integer, p_period integer, p_transaction_type "TransactionType", p_currency_code text, p_amount numeric, p_country_code text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_limit public.transaction_limit%rowtype;
    v_kyc_status public."KycStatus";

    v_today_start
        timestamp with time zone;

    v_total_today numeric := 0;
    v_month_start timestamp with time zone;
    v_next_month_start timestamp with time zone;
    v_total_month numeric := 0;
begin
    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception
            'USER_ID_IS_REQUIRED';
    end if;

    if p_currency_code is null
       or btrim(p_currency_code) = ''
    then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_country_code is null
       or btrim(p_country_code) = ''
    then
        raise exception
            'COUNTRY_IS_REQUIRED';
    end if;

    if p_amount is null
       or p_amount::text IN ('NaN','Infinity','-Infinity')
       or p_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    if p_fiscal_year is null then
        raise exception
            'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception
            'PERIOD_IS_REQUIRED';
    end if;

    -- Only current KYC determines the limit. Historical verification
    -- cannot upgrade a newer pending/rejected submission.
    select k.kyc_status into v_kyc_status
    from public.user_kyc k
    where k.user_id=p_user_id and k.is_current=true;
    v_kyc_status := coalesce(v_kyc_status,'pending'::public."KycStatus");

    /*
     * Fetch the active configuration for transaction type, country,
     * currency AND current KYC status.
     */
    select transaction_limit_record.*
    into v_limit
    from public.transaction_limit
        transaction_limit_record
    where transaction_limit_record.transaction_type =
          p_transaction_type
      and lower(
          transaction_limit_record.country_code
      ) = lower(
          btrim(p_country_code)
      )
      and lower(
          transaction_limit_record.currency_code
      ) = lower(
          btrim(p_currency_code)
      )
      and transaction_limit_record.is_active = true
      and transaction_limit_record.kyc_status = v_kyc_status;

    if not found then
        -- Preserve the existing no-limits behavior only when there are no
        -- active limits at all for this transaction/country/currency.
        -- A missing KYC tier must not bypass configured limits.
        if exists (
            select 1 from public.transaction_limit t
            where t.transaction_type=p_transaction_type
              and lower(t.country_code)=lower(btrim(p_country_code))
              and lower(t.currency_code)=lower(btrim(p_currency_code))
              and t.is_active=true
        ) then
            raise exception 'TRANSACTION_LIMIT_NOT_CONFIGURED_FOR_KYC_STATUS'
                using detail=format('kyc_status=%s',v_kyc_status::text);
        end if;
        return;
    end if;

    /*
     * Minimum transaction amount.
     */
    if v_limit.min_amount is not null
       and p_amount < v_limit.min_amount
    then
        raise exception
            'AMOUNT_BELOW_MINIMUM_TRANSACTION_AMOUNT';
    end if;

    /*
     * Maximum amount per transaction.
     */
    if v_limit.max_amount is not null
       and p_amount > v_limit.max_amount
    then
        raise exception
            'AMOUNT_EXCEEDS_MAXIMUM_TRANSACTION_AMOUNT';
    end if;

    /*
     * Daily cumulative limit.
     */
    if v_limit.daily_limit is not null then
        v_today_start :=
            date_trunc(
                'day',
                now() at time zone 'UTC'
            ) at time zone 'UTC';

        select coalesce(
            sum(
                coalesce(
                    wallet_entry_record.debit,
                    0
                )
            ),
            0
        )
        into v_total_today
        from public.wallet_entry
            wallet_entry_record
        join public.wallet
            wallet_record
          on wallet_record.id =
             wallet_entry_record.wallet_id
        where wallet_record.user_id =
              p_user_id
          and lower(
              wallet_record.currency_code
          ) = lower(
              btrim(p_currency_code)
          )
          and lower(
              wallet_record.country_code
          ) = lower(
              btrim(p_country_code)
          )
          and wallet_entry_record.transaction_type =
              p_transaction_type
          and wallet_entry_record.created_at >=
              v_today_start;

        if (
            v_total_today +
            p_amount
        ) > v_limit.daily_limit
        then
            raise exception
                'DAILY_TRANSACTION_LIMIT_EXCEEDED';
        end if;
    end if;

    /*
     * Monthly cumulative limit: UTC calendar month, with the same
     * transaction/country/currency/user debit scope as the daily check.
     * All matching wallets/chains contribute to one monthly total.
     */
    if v_limit.monthly_limit is not null then
        v_month_start := date_trunc('month',now() at time zone 'UTC')
            at time zone 'UTC';
        v_next_month_start :=
            (date_trunc('month',now() at time zone 'UTC') + interval '1 month')
            at time zone 'UTC';

        select coalesce(sum(coalesce(e.debit,0)),0)
        into v_total_month
        from public.wallet_entry e
        join public.wallet w on w.id=e.wallet_id
        where w.user_id=p_user_id
          and lower(w.currency_code)=lower(btrim(p_currency_code))
          and lower(w.country_code)=lower(btrim(p_country_code))
          and e.transaction_type=p_transaction_type
          and e.created_at>=v_month_start
          and e.created_at<v_next_month_start;

        if v_total_month+p_amount>v_limit.monthly_limit then
            raise exception 'MONTHLY_TRANSACTION_LIMIT_EXCEEDED';
        end if;
    end if;
end;
$function$;

REVOKE ALL ON FUNCTION public.enforce_transaction_limit(text,integer,integer,public."TransactionType",text,numeric,text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_transaction_limit(text,integer,integer,public."TransactionType",text,numeric,text)
TO service_role;
COMMIT;
