/* =========================================================
 * FETCH AGENT COMMISSION RATE
 * ========================================================= */

create or replace function public.fetch_agent_commission_rate(
    p_transaction_type public."TransactionType",
    p_currency_code text,
    p_country_code text
)
returns numeric
language sql
stable
security definer
set search_path to ''
as $function$
    select coalesce(
        (
            select commission_config.rate
            from public.agent_fee_splitting_config
                commission_config
            where commission_config.is_active = true
              and lower(
                  commission_config.currency_code
              ) = lower(
                  btrim(p_currency_code)
              )
              and commission_config.transaction_type =
                  p_transaction_type
              and lower(
                  commission_config.country_code
              ) = lower(
                  btrim(p_country_code)
              )
            limit 1
        ),
        0
    );
$function$;


/* =========================================================
 * FETCH GOVERNMENT TAX RATE
 * ========================================================= */

create or replace function public.fetch_government_tax_rate(
    p_transaction_type public."TransactionType",
    p_currency_code text,
    p_country_code text
)
returns numeric
language sql
stable
security definer
set search_path to ''
as $function$
    select coalesce(
        (
            select tax_config.rate
            from public.government_tax_config
                tax_config
            where tax_config.is_active = true
              and lower(
                  tax_config.currency_code
              ) = lower(
                  btrim(p_currency_code)
              )
              and tax_config.transaction_type =
                  p_transaction_type
              and lower(
                  tax_config.country_code
              ) = lower(
                  btrim(p_country_code)
              )
            limit 1
        ),
        0
    );
$function$;


/* =========================================================
 * ENFORCE TRANSACTION LIMIT
 * ========================================================= */

create or replace function public.enforce_transaction_limit(
    p_user_id text,
    p_fiscal_year integer,
    p_period integer,
    p_transaction_type public."TransactionType",
    p_currency_code text,
    p_amount numeric,
    p_country_code text
)
returns void
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_limit public.transaction_limit%rowtype;

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

    /*
     * Fetch the active limit configuration for the
     * exact transaction type, country and currency.
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
    limit 1;

    /*
     * No active configuration means that no limits
     * are configured for this transaction.
     */
    if not found then
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


/* =========================================================
 * FUNCTION OWNER
 * ========================================================= */

alter function public.enforce_transaction_limit(
    text,
    integer,
    integer,
    public."TransactionType",
    text,
    numeric,
    text
)
owner to postgres;


/* =========================================================
 * EXECUTION PERMISSIONS
 * ========================================================= */

revoke execute on function
    public.enforce_transaction_limit(
        text,
        integer,
        integer,
        public."TransactionType",
        text,
        numeric,
        text
    )
from public, anon, authenticated, service_role;




/* =========================================================
 * FUNCTION OWNERS
 * ========================================================= */

alter function public.fetch_agent_commission_rate(
    public."TransactionType",
    text,
    text
)
owner to postgres;

alter function public.fetch_government_tax_rate(
    public."TransactionType",
    text,
    text
)
owner to postgres;

alter function public.enforce_transaction_limit(
    text,
    integer,
    integer,
    public."TransactionType",
    text,
    numeric,
    text
)
owner to postgres;


/* =========================================================
 * EXECUTION PERMISSIONS
 *
 * These functions are called internally by protected
 * postgres-owned transaction functions.
 * ========================================================= */

revoke execute on function
    public.fetch_agent_commission_rate(
        public."TransactionType",
        text,
        text
    )
from public, anon, authenticated, service_role;

revoke execute on function
    public.fetch_government_tax_rate(
        public."TransactionType",
        text,
        text
    )
from public, anon, authenticated, service_role;


/* =========================================================
 * RELOAD POSTGREST
 * ========================================================= */

notify pgrst, 'reload schema';