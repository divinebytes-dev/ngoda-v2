/*
 * ============================================================
 * CREDIT AGENT ACCOUNTING FOUNDATION
 * ============================================================
 */


/*
 * ============================================================
 * 1. CREDIT AGENT ACCOUNT
 *
 * Identifies merchants approved for credit-agent operations and
 * stores their current balance per country and currency.
 * ============================================================
 */

create table if not exists public.credit_agent_account (
    id text primary key
        default pg_catalog.gen_random_uuid()::text,

    merchant_id text not null
        references public.users(id),

    country_code text not null,

    currency_code text not null,

    receivable_balance numeric(20, 2)
        not null
        default 0,

    cash_holding_balance numeric(20, 2)
        not null
        default 0,

    is_active boolean
        not null
        default true,

    approved_by text not null
        references public.users(id),

    approved_at timestamptz
        not null
        default now(),

    deactivated_by text
        references public.users(id),

    deactivated_at timestamptz,

    created_at timestamptz
        not null
        default now(),

    updated_at timestamptz
        not null
        default now(),

    constraint credit_agent_account_identity_unique
        unique (
            merchant_id,
            country_code,
            currency_code
        ),

    constraint credit_agent_receivable_non_negative_check
        check (
            receivable_balance >= 0
        ),

    constraint credit_agent_cash_holding_non_negative_check
        check (
            cash_holding_balance >= 0
        ),

    constraint credit_agent_currency_normalized_check
        check (
            currency_code =
            lower(
                btrim(currency_code)
            )
        ),

    constraint credit_agent_country_normalized_check
        check (
            country_code =
            lower(
                btrim(country_code)
            )
        ),

    constraint credit_agent_deactivation_consistency_check
        check (
            (
                is_active = true
                and deactivated_by is null
                and deactivated_at is null
            )
            or
            (
                is_active = false
                and deactivated_by is not null
                and deactivated_at is not null
            )
        )
);


/*
 * ============================================================
 * 2. CREDIT AGENT ENTRY
 *
 * Immutable subledger for all receivable and cash-holding
 * movements.
 * ============================================================
 */

create table if not exists public.credit_agent_entry (
    id text primary key
        default pg_catalog.gen_random_uuid()::text,

    credit_agent_account_id text not null
        references public.credit_agent_account(id),

    merchant_id text not null
        references public.users(id),

    country_code text not null,

    currency_code text not null,

    fiscal_year integer not null,

    period integer not null,

    document_number text not null
        references public.financial_transaction(document_number),

    transaction_type public."TransactionType"
        not null,

    debit_receivable numeric(20, 2)
        not null
        default 0,

    credit_receivable numeric(20, 2)
        not null
        default 0,

    debit_cash_holding numeric(20, 2)
        not null
        default 0,

    credit_cash_holding numeric(20, 2)
        not null
        default 0,

    receivable_balance_before numeric(20, 2)
        not null,

    receivable_balance_after numeric(20, 2)
        not null,

    cash_holding_balance_before numeric(20, 2)
        not null,

    cash_holding_balance_after numeric(20, 2)
        not null,

    created_by text not null
        references public.users(id),

    created_at timestamptz
        not null
        default now(),

    constraint credit_agent_entry_document_unique
        unique (
            document_number
        ),

    constraint credit_agent_entry_period_check
        check (
            period between 1 and 12
        ),

    constraint credit_agent_entry_amounts_non_negative_check
        check (
            debit_receivable >= 0
            and credit_receivable >= 0
            and debit_cash_holding >= 0
            and credit_cash_holding >= 0
            and receivable_balance_before >= 0
            and receivable_balance_after >= 0
            and cash_holding_balance_before >= 0
            and cash_holding_balance_after >= 0
        ),

    constraint credit_agent_entry_receivable_direction_check
        check (
            debit_receivable = 0
            or credit_receivable = 0
        ),

    constraint credit_agent_entry_cash_direction_check
        check (
            debit_cash_holding = 0
            or credit_cash_holding = 0
        ),

    constraint credit_agent_entry_has_movement_check
        check (
            debit_receivable > 0
            or credit_receivable > 0
            or debit_cash_holding > 0
            or credit_cash_holding > 0
        ),

    constraint credit_agent_entry_receivable_balance_check
        check (
            receivable_balance_after =
                receivable_balance_before
                + debit_receivable
                - credit_receivable
        ),

    constraint credit_agent_entry_cash_balance_check
        check (
            cash_holding_balance_after =
                cash_holding_balance_before
                + debit_cash_holding
                - credit_cash_holding
        ),

    constraint credit_agent_entry_currency_normalized_check
        check (
            currency_code =
            lower(
                btrim(currency_code)
            )
        ),

    constraint credit_agent_entry_country_normalized_check
        check (
            country_code =
            lower(
                btrim(country_code)
            )
        )
);


/*
 * ============================================================
 * 3. INDEXES
 * ============================================================
 */

create index if not exists
    credit_agent_account_active_lookup_idx
on public.credit_agent_account (
    merchant_id,
    country_code,
    currency_code,
    is_active
);


create index if not exists
    credit_agent_account_country_currency_idx
on public.credit_agent_account (
    country_code,
    currency_code,
    is_active
);


create index if not exists
    credit_agent_entry_account_created_idx
on public.credit_agent_entry (
    credit_agent_account_id,
    created_at desc
);


create index if not exists
    credit_agent_entry_merchant_currency_idx
on public.credit_agent_entry (
    merchant_id,
    country_code,
    currency_code,
    created_at desc
);


create index if not exists
    credit_agent_entry_fiscal_period_idx
on public.credit_agent_entry (
    country_code,
    currency_code,
    fiscal_year,
    period
);


create index if not exists
    credit_agent_entry_transaction_type_idx
on public.credit_agent_entry (
    transaction_type,
    created_at desc
);


/*
 * ============================================================
 * 4. PREVENT UPDATE OR DELETE OF SUBLEDGER ENTRIES
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
 * 5. ATOMIC CREDIT-AGENT BALANCE POSTING
 *
 * This function:
 *
 * - locks the merchant account;
 * - prevents duplicate documents;
 * - prevents negative receivable;
 * - prevents negative cash holding;
 * - writes the immutable entry;
 * - updates the current balances.
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

    v_debit_receivable numeric;
    v_credit_receivable numeric;
    v_debit_cash_holding numeric;
    v_credit_cash_holding numeric;

    v_receivable_after numeric;
    v_cash_holding_after numeric;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Validate identifiers.
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

    if nullif(
        btrim(p_document_number),
        ''
    ) is null
    then
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
     * Fiat credit-agent balances use two decimal places.
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

    if v_debit_receivable < 0
       or v_credit_receivable < 0
       or v_debit_cash_holding < 0
       or v_credit_cash_holding < 0
    then
        raise exception
            'NEGATIVE_CREDIT_AGENT_MOVEMENT_NOT_ALLOWED';
    end if;

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

    if v_debit_receivable = 0
       and v_credit_receivable = 0
       and v_debit_cash_holding = 0
       and v_credit_cash_holding = 0
    then
        raise exception
            'CREDIT_AGENT_MOVEMENT_REQUIRED';
    end if;

    /*
     * Lock the merchant account.
     *
     * Concurrent withdrawals or settlements must wait for this
     * transaction before calculating their balances.
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
     * Prevent the same accounting document from being posted
     * more than once.
     */
    v_stage := 'check duplicate document';

    perform 1
    from public.credit_agent_entry
        entry_record
    where entry_record.document_number =
          btrim(p_document_number)
    limit 1;

    if found then
        raise exception
            'CREDIT_AGENT_DOCUMENT_ALREADY_POSTED';
    end if;

    /*
     * Calculate new balances.
     */
    v_stage := 'calculate balances';

    v_receivable_after :=
        v_account.receivable_balance
        + v_debit_receivable
        - v_credit_receivable;

    v_cash_holding_after :=
        v_account.cash_holding_balance
        + v_debit_cash_holding
        - v_credit_cash_holding;

    /*
     * Never allow an individual merchant balance to become
     * negative.
     */
    if v_receivable_after < 0 then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_RECEIVABLE_[%]',
            v_account.receivable_balance;
    end if;

    if v_cash_holding_after < 0 then
        raise exception
            'INSUFFICIENT_CREDIT_AGENT_CASH_HOLDING_[%]',
            v_account.cash_holding_balance;
    end if;

    /*
     * The financial document must already exist in the same
     * database transaction.
     */
    v_stage := 'validate financial document';

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.document_number =
          btrim(p_document_number)

      and transaction_record.country_code =
          v_account.country_code

      and lower(
          transaction_record.currency_code
      ) =
          v_account.currency_code
    limit 1;

    if not found then
        raise exception
            'FINANCIAL_DOCUMENT_NOT_FOUND';
    end if;

    /*
     * Write immutable entry.
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
        receivable_balance_before,
        receivable_balance_after,
        cash_holding_balance_before,
        cash_holding_balance_after,
        created_by
    )
    values (
        v_account.id,
        v_account.merchant_id,
        v_account.country_code,
        v_account.currency_code,
        p_fiscal_year,
        p_period,
        btrim(p_document_number),
        p_transaction_type,
        v_debit_receivable,
        v_credit_receivable,
        v_debit_cash_holding,
        v_credit_cash_holding,
        v_account.receivable_balance,
        v_receivable_after,
        v_account.cash_holding_balance,
        v_cash_holding_after,
        p_created_by
    )
    returning *
    into v_entry;

    /*
     * Update current account balances.
     */
    v_stage := 'update credit agent account';

    update public.credit_agent_account
    set
        receivable_balance =
            v_receivable_after,

        cash_holding_balance =
            v_cash_holding_after,

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
 * 6. ROW-LEVEL SECURITY AND PRIVILEGES
 *
 * Credit-agent balances are accessed only through controlled
 * SECURITY DEFINER functions.
 * ============================================================
 */

alter table public.credit_agent_account
    enable row level security;

alter table public.credit_agent_entry
    enable row level security;


revoke all on table
    public.credit_agent_account
from public;

revoke all on table
    public.credit_agent_account
from anon;

revoke all on table
    public.credit_agent_account
from authenticated;


revoke all on table
    public.credit_agent_entry
from public;

revoke all on table
    public.credit_agent_entry
from anon;

revoke all on table
    public.credit_agent_entry
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