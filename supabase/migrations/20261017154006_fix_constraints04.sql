-- KYC-specific active transaction limits, with pending fallback.
-- Full replacement: index and function change together in one transaction.
BEGIN;
LOCK TABLE public.transaction_limit IN ACCESS EXCLUSIVE MODE;
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.transaction_limit WHERE is_active=true
    GROUP BY transaction_type,country_code,currency_code,kyc_status HAVING count(*)>1
  ) THEN RAISE EXCEPTION 'DUPLICATE_ACTIVE_KYC_TRANSACTION_LIMITS'; END IF;
  IF EXISTS (SELECT 1 FROM public.user_kyc WHERE is_current=true
    GROUP BY user_id HAVING count(*)>1)
  THEN RAISE EXCEPTION 'MULTIPLE_CURRENT_KYC_RECORDS'; END IF;
END;
$preflight$;

CREATE UNIQUE INDEX IF NOT EXISTS transaction_limit_active_kyc_scope_unique
ON public.transaction_limit(transaction_type,country_code,currency_code,kyc_status)
WHERE is_active=true;

-- Remove only the previous active scope and original scope+status identity.
-- No CASCADE: unexpected FK dependencies abort the migration.
DROP INDEX IF EXISTS public.transaction_limit_active_scope_unique;
DO $old_keys$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT x.indexrelid,i.relname,n.nspname,k.conname
    FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
    JOIN pg_namespace n ON n.oid=i.relnamespace
    LEFT JOIN pg_constraint k ON k.conindid=x.indexrelid AND k.contype='u'
    WHERE x.indrelid='public.transaction_limit'::regclass
      AND x.indisunique AND NOT x.indisprimary AND x.indexprs IS NULL
      AND x.indpred IS NULL AND x.indnkeyatts=4
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
        FROM unnest(x.indkey::smallint[]) WITH ORDINALITY keys(attnum,n)
        JOIN pg_attribute a ON a.attrelid=x.indrelid AND a.attnum=keys.attnum
        WHERE keys.n<=x.indnkeyatts)
        = ARRAY['country_code','currency_code','is_active','transaction_type']::text[]
  LOOP
    IF r.conname IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.transaction_limit DROP CONSTRAINT %I',r.conname);
    ELSE EXECUTE format('DROP INDEX %I.%I',r.nspname,r.relname); END IF;
  END LOOP;
END;
$old_keys$;

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
end;
$function$;

REVOKE ALL ON FUNCTION public.enforce_transaction_limit(text,integer,integer,public."TransactionType",text,numeric,text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_transaction_limit(text,integer,integer,public."TransactionType",text,numeric,text)
TO service_role;
COMMIT;
