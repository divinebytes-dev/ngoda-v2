/*
 * ============================================================
 * CREDIT AGENT SUBLEDGER POSTING
 * ============================================================
 */


/*
 * ============================================================
 * 1. PREVENT CREDIT AGENT ENTRY UPDATE OR DELETE
 * ============================================================
 */

create or replace function
    public.prevent_credit_agent_entry_mutation()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
    raise exception using
        errcode = '55000',
        message = 'CREDIT_AGENT_ENTRY_IS_APPEND_ONLY';
end;
$function$;


drop trigger if exists
    prevent_credit_agent_entry_update
on public.credit_agent_entry;


create trigger
    prevent_credit_agent_entry_update
before update
on public.credit_agent_entry
for each row
execute function
    public.prevent_credit_agent_entry_mutation();


drop trigger if exists
    prevent_credit_agent_entry_delete
on public.credit_agent_entry;


create trigger
    prevent_credit_agent_entry_delete
before delete
on public.credit_agent_entry
for each row
execute function
    public.prevent_credit_agent_entry_mutation();


/*
 * ============================================================
 * 2. ATOMIC CREDIT AGENT ENTRY POSTING
 * ============================================================
 */

create or replace function public.post_credit_agent_entry(
    p_credit_agent_account_id text,
    p_document_number text,
    p_transaction_type public."TransactionType",
    p_fiscal_year integer,
    p_period integer,
    p_debit_receivable numeric,
    p_credit_receivable numeric,
    p_debit_cash_holding numeric,
    p_credit_cash_holding numeric,
    p_created_by text
)
returns public.credit_agent_entry
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_account
        public.credit_agent_account%rowtype;

    v_entry
        public.credit_agent_entry%rowtype;

    v_document_number text;

    v_debit_receivable numeric;
    v_credit_receivable numeric;

    v_debit_cash_holding numeric;
    v_credit_cash_holding numeric;

    v_new_receivable_balance numeric;
    v_new_cash_holding_balance numeric;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Validate required values.
     */
    v_stage := 'validate input';

    if nullif(
        btrim(p_credit_agent_account_id),
        ''
    ) is null
    then
        raise exception
            'CREDIT_AGENT_ACCOUNT_ID_REQUIRED';
    end if;

    v_document_number :=
        nullif(
            btrim(p_document_number),
            ''
        );

    if v_document_number is null then
        raise exception
            'DOCUMENT_NUMBER_REQUIRED';
    end if;

    if p_transaction_type is null then
        raise exception
            'TRANSACTION_TYPE_REQUIRED';
    end if;

    if p_fiscal_year is null then
        raise exception
            'FISCAL_YEAR_REQUIRED';
    end if;

    if p_period is null
       or p_period < 1
       or p_period > 12
    then
        raise exception
            'INVALID_PERIOD';
    end if;

    if nullif(
        btrim(p_created_by),
        ''
    ) is null
    then
        raise exception
            'CREATED_BY_REQUIRED';
    end if;

    /*
     * Credit-agent transactions are fiat transactions.
     *
     * All values are rounded down to two decimal places.
     */
    v_debit_receivable :=
        trunc(
            coalesce(
                p_debit_receivable,
                0
            ),
            2
        );

    v_credit_receivable :=
        trunc(
            coalesce(
                p_credit_receivable,
                0
            ),
            2
        );

    v_debit_cash_holding :=
        trunc(
            coalesce(
                p_debit_cash_holding,
                0
            ),
            2
        );

    v_credit_cash_holding :=
        trunc(
            coalesce(
                p_credit_cash_holding,
                0
            ),
            2
        );

    /*
     * Negative movement values are never permitted.
     */
    if v_debit_receivable < 0
       or v_credit_receivable < 0
       or v_debit_cash_holding < 0
       or v_credit_cash_holding < 0
    then
        raise exception
            'NEGATIVE_CREDIT_AGENT_MOVEMENT_NOT_ALLOWED';
    end if;

    /*
     * A single balance cannot be debited and credited by the
     * same entry.
     */
    if v_debit_receivable > 0
       and v_credit_receivable > 0
    then
        raise exception
            'INVALID_RECEIVABLE_MOVEMENT';
    end if;

    if v_debit_cash_holding > 0
       and v_credit_cash_holding > 0
    then
        raise exception
            'INVALID_CASH_HOLDING_MOVEMENT';
    end if;

    /*
     * At least one balance must move.
     */
    if v_debit_receivable = 0
       and v_credit_receivable = 0
       and v_debit_cash_holding = 0
       and v_credit_cash_holding = 0
    then
        raise exception
            'CREDIT_AGENT_MOVEMENT_REQUIRED';
    end if;

    /*
     * Lock the account.
     *
     * This prevents concurrent withdrawals or settlements from
     * consuming the same balance.
     */
    v_stage := 'lock credit agent account';

    select account_record.*
    into v_account
    from public.credit_agent_account
        account_record
    where account_record.id =
          p_credit_agent_account_id
    for update;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_FOUND';
    end if;

    if not v_account.is_active then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_ACTIVE';
    end if;

    /*
     * Prevent the same financial document from updating the
     * credit-agent balances more than once.
     */
    v_stage := 'check duplicate document';

    perform 1
    from public.credit_agent_entry
        entry_record
    where entry_record.document_number =
          v_document_number
    limit 1;

    if found then
        raise exception
            'CREDIT_AGENT_DOCUMENT_ALREADY_POSTED';
    end if;

    /*
     * Confirm that the financial transaction exists and belongs
     * to the same country and currency as the account.
     */
    v_stage := 'validate financial document';

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.document_number =
              v_document_number

      and transaction_record.country_code =
              v_account.country_code

      and lower(
          transaction_record.currency_code
      ) =
              v_account.currency_code
    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_FINANCIAL_DOCUMENT_NOT_FOUND';
    end if;

    /*
     * Calculate resulting balances.
     */
    v_stage := 'calculate balances';

    v_new_receivable_balance :=
        v_account.receivable_balance
        + v_debit_receivable
        - v_credit_receivable;

    v_new_cash_holding_balance :=
        v_account.cash_holding_balance
        + v_debit_cash_holding
        - v_credit_cash_holding;

    /*
     * Never allow the individual merchant's balances to become
     * negative.
     */
    if v_new_receivable_balance < 0 then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_RECEIVABLE_[%]',
            v_account.receivable_balance;
    end if;

    if v_new_cash_holding_balance < 0 then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_CASH_HOLDING_[%]',
            v_account.cash_holding_balance;
    end if;

    /*
     * Write the immutable movement.
     */
    v_stage := 'create credit agent entry';

    insert into public.credit_agent_entry (
        credit_agent_account_id,
        merchant_id,
        country_code,
        currency_code,
        fiscal_year,
        period,
        document_number,
        transaction_type,
        debit_receivable,
        credit_receivable,
        debit_cash_holding,
        credit_cash_holding,
        created_by,
        created_at
    )
    values (
        v_account.id,
        v_account.merchant_id,
        v_account.country_code,
        v_account.currency_code,
        p_fiscal_year,
        p_period,
        v_document_number,
        p_transaction_type,
        v_debit_receivable,
        v_credit_receivable,
        v_debit_cash_holding,
        v_credit_cash_holding,
        p_created_by,
        now()
    )
    returning *
    into v_entry;

    /*
     * Update current balances.
     */
    v_stage := 'update credit agent account';

    update public.credit_agent_account
    set
        receivable_balance =
            v_new_receivable_balance,

        cash_holding_balance =
            v_new_cash_holding_balance,

        updated_at =
            now()
    where id =
          v_account.id;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_UPDATE_FAILED';
    end if;

    return v_entry;

exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,

            message = format(
                'POST_CREDIT_AGENT_ENTRY_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the Credit Agent Entry stage reported in the error'
            );
end;
$function$;


/*
 * ============================================================
 * 3. PRIVILEGES
 *
 * This is an internal posting function. Transaction RPCs execute
 * it; clients cannot call it directly.
 * ============================================================
 */

revoke all on function
    public.prevent_credit_agent_entry_mutation()
from public;

revoke all on function
    public.prevent_credit_agent_entry_mutation()
from anon;

revoke all on function
    public.prevent_credit_agent_entry_mutation()
from authenticated;


revoke all on function
    public.post_credit_agent_entry(
        text,
        text,
        public."TransactionType",
        integer,
        integer,
        numeric,
        numeric,
        numeric,
        numeric,
        text
    )
from public;

revoke all on function
    public.post_credit_agent_entry(
        text,
        text,
        public."TransactionType",
        integer,
        integer,
        numeric,
        numeric,
        numeric,
        numeric,
        text
    )
from anon;

revoke all on function
    public.post_credit_agent_entry(
        text,
        text,
        public."TransactionType",
        integer,
        integer,
        numeric,
        numeric,
        numeric,
        numeric,
        text
    )
from authenticated;