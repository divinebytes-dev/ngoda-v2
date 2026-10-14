begin;

/*
 * Preserve the existing, tested accounting implementation under an
 * internal posting name. The public RPC name is recreated below with
 * the additional loyalty context required by the Edge Function.
 */
do $migration$
begin
    if to_regprocedure(
        'public.credit_agent_cash_deposit_posting(text,jsonb,public."TransactionType",text,text,text)'
    ) is null then
        if to_regprocedure(
            'public.credit_agent_cash_deposit(text,jsonb,public."TransactionType",text,text,text)'
        ) is null then
            raise exception
                'CREDIT_AGENT_CASH_DEPOSIT_FUNCTION_NOT_FOUND';
        end if;

        execute
            'alter function public.credit_agent_cash_deposit(text, jsonb, public."TransactionType", text, text, text) rename to credit_agent_cash_deposit_posting';
    end if;
end;
$migration$;


create or replace function public.credit_agent_cash_deposit(
    p_user_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    reference text,
    customer_id text,
    gross_amount text,
    gross_amount_usd text,
    financial_transaction_id text,
    receiver_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_posting record;
    v_currency_code text;
    v_amount numeric;
    v_amount_usd numeric(20, 6);
    v_rate_to_usd numeric;
    v_financial_transaction_id bigint;
begin
    /*
     * The internal function performs all validation, locking,
     * accounting, wallet posting, credit-agent posting and the
     * transaction-state update in this same database transaction.
     */
    select posting_result.*
    into v_posting
    from public.credit_agent_cash_deposit_posting(
        p_user_id,
        p_transaction,
        p_transaction_type,
        p_country_code,
        p_transaction_state_id,
        p_ip_address
    ) as posting_result;

    if not found or not coalesce(v_posting.success, false) then
        raise exception
            'CREDIT_AGENT_CASH_DEPOSIT_POSTING_RESULT_NOT_FOUND';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency_code is null then
        raise exception 'CURRENCY_REQUIRED';
    end if;

    v_amount :=
        nullif(v_posting.gross_amount::text, '')::numeric;

    if v_amount is null or v_amount <= 0 then
        raise exception 'INVALID_AMOUNT';
    end if;

    /*
     * Use the same Ngoda rate convention as the other loyalty-enabled
     * transactions: USD is already USD, gold multiplies by its USD
     * price, and other fiat divides by currency units per USD.
     */
    if v_currency_code = 'usd' then
        v_amount_usd := round(v_amount, 6);
    else
        select rate_record.rate_to_usd
        into v_rate_to_usd
        from public.current_rates rate_record
        where lower(btrim(rate_record.code)) =
              v_currency_code
        limit 1;

        if not found
           or v_rate_to_usd is null
           or v_rate_to_usd <= 0
        then
            raise exception
                'CURRENT_RATE_NOT_FOUND_%',
                upper(v_currency_code);
        end if;

        if v_currency_code = 'gold' then
            v_amount_usd :=
                round(v_amount * v_rate_to_usd, 6);
        else
            v_amount_usd :=
                round(v_amount / v_rate_to_usd, 6);
        end if;
    end if;

    if v_amount_usd <= 0 then
        raise exception
            'INVALID_CREDIT_AGENT_CASH_DEPOSIT_USD_AMOUNT';
    end if;

    /*
     * The posting function has just created this unique transaction.
     * Resolve its authoritative ID before returning to the Edge
     * Function so loyalty can link to the financial transaction.
     */
    select transaction_record.id
    into v_financial_transaction_id
    from public.financial_transaction transaction_record
    where transaction_record.reference =
          v_posting.reference
      and transaction_record.transaction_type =
          p_transaction_type
      and transaction_record.country_code =
          p_country_code
    order by transaction_record.id desc
    limit 1;

    if not found then
        raise exception
            'FINANCIAL_TRANSACTION_NOT_FOUND';
    end if;

    return query
    select
        v_posting.success::boolean,
        v_posting.reference::text,
        v_posting.customer_id::text,
        v_posting.gross_amount::text,
        v_amount_usd::text,
        v_financial_transaction_id::text,
        v_posting.receiver_notification_id::text,
        v_posting.device_tokens::text[],
        v_posting.push_title::text,
        v_posting.push_body::text,
        v_posting.push_reference::text;
end;
$function$;


revoke all on function public.credit_agent_cash_deposit_posting(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
) from public, anon, authenticated;

grant execute on function public.credit_agent_cash_deposit_posting(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
) to service_role;

revoke all on function public.credit_agent_cash_deposit(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
) from public, anon, authenticated;

grant execute on function public.credit_agent_cash_deposit(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
) to service_role;

commit;

notify pgrst, 'reload schema';
