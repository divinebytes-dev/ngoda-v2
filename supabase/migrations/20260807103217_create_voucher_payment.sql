/*
 * ============================================================
 * VOUCHER PAYMENT PREPARATION
 * ============================================================
 */


/*
 * ============================================================
 * 1. FETCH AUTHENTICATED VOUCHER-PAYMENT CONTEXT
 * ============================================================
 */

create or replace function public.fetch_my_voucher_payment_context(
    p_v text,
    p_voucher_owner_id text
)
returns table (
    merchant_id text,
    country_code text,
    merchant_wallet_address text,
    voucher_owner_wallet_address text,
    version_time numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_merchant public.users%rowtype;
    v_voucher_owner public.users%rowtype;
    v_version_time numeric;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Merchants and vendors can accept voucher payments.
     * A vendor may operate a merchant-owned wallet.
     */
    if not public.has_role(
        array[
            'merchant',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_merchant
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception 'MERCHANT_NOT_FOUND';
    end if;

    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception 'MERCHANT_NOT_ACTIVE';
    end if;

    if v_merchant.country_code is null
       or btrim(v_merchant.country_code) = ''
    then
        raise exception
            'MERCHANT_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_merchant.wallet_address is null
       or btrim(v_merchant.wallet_address) = ''
    then
        raise exception
            'MERCHANT_WALLET_NOT_CONFIGURED';
    end if;

    if p_voucher_owner_id is null
       or btrim(p_voucher_owner_id) = ''
    then
        raise exception
            'VOUCHER_OWNER_ID_MISSING';
    end if;

    select user_record.*
    into v_voucher_owner
    from public.users user_record
    where user_record.id =
          btrim(p_voucher_owner_id)
    limit 1;

    if not found then
        raise exception
            'VOUCHER_OWNER_NOT_FOUND';
    end if;

    if v_voucher_owner.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'VOUCHER_OWNER_NOT_ACTIVE';
    end if;

    if v_voucher_owner.wallet_address is null
       or btrim(v_voucher_owner.wallet_address) = ''
    then
        raise exception
            'VOUCHER_OWNER_WALLET_NOT_CONFIGURED';
    end if;

    if v_voucher_owner.country_code is distinct from
       v_merchant.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_voucher_owner.id =
       v_merchant.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_version_time :=
        public.get_transaction_v(p_v);

    if v_version_time is null then
        raise exception
            'TRANSACTION_VERSION_NOT_FOUND';
    end if;

    return query
    select
        v_merchant.id,
        v_merchant.country_code,
        v_merchant.wallet_address,
        v_voucher_owner.wallet_address,
        v_version_time;
end;
$function$;


/*
 * ============================================================
 * 2. CREATE PROCESSING TRANSACTION STATE
 * ============================================================
 */

create or replace function public.create_my_voucher_payment_state(
    p_transaction jsonb,
    p_voucher jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_transaction_reference text;
    v_transaction_currency text;
    v_transaction_voucher_reference text;

    v_voucher_reference text;
    v_voucher_currency text;
    v_voucher_owner_id text;

    v_transaction_amount numeric;
    v_voucher_amount numeric;

    v_transaction_state_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'merchant',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_voucher is null then
        raise exception
            'VOUCHER_DATA_MISSING';
    end if;

    if p_transaction ->> 'v' is distinct from
       'v0'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if p_voucher ->> 'v' is distinct from
       'v0'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;

    v_transaction_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_transaction_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_transaction_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_transaction_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    v_transaction_voucher_reference :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_transaction_voucher_reference is null then
        raise exception
            'VOUCHER_REFERENCE_MISSING';
    end if;

    v_voucher_reference :=
        nullif(
            btrim(p_voucher ->> 'r'),
            ''
        );

    if v_voucher_reference is null then
        raise exception
            'VOUCHER_REFERENCE_MISSING';
    end if;

    v_voucher_currency :=
        lower(
            nullif(
                btrim(p_voucher ->> 'c'),
                ''
            )
        );

    if v_voucher_currency is null then
        raise exception
            'VOUCHER_CURRENCY_MISSING';
    end if;

    v_voucher_owner_id :=
        nullif(
            btrim(p_voucher ->> 's'),
            ''
        );

    if v_voucher_owner_id is null then
        raise exception
            'VOUCHER_OWNER_ID_MISSING';
    end if;

    if v_transaction_currency is distinct from
       v_voucher_currency
    then
        raise exception
            'CURRENCY_MISMATCH';
    end if;

    /*
     * The merchant transaction points to the voucher reference
     * through transaction.s.
     */
    if v_transaction_voucher_reference is distinct from
       v_voucher_reference
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    begin
        v_transaction_amount :=
            (p_transaction ->> 'a')::numeric /
            100;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_AMOUNT';
    end;

    begin
        v_voucher_amount :=
            (p_voucher ->> 'a')::numeric /
            100;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_VOUCHER_AMOUNT';
    end;

    if v_transaction_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    if v_voucher_amount <= 0 then
        raise exception
            'INVALID_VOUCHER_AMOUNT';
    end if;

    if v_transaction_amount >
       v_voucher_amount
    then
        raise exception
            'VOUCHER_BALANCE_NOT_ENOUGH';
    end if;

    begin
        insert into public.transaction_state (
            reference,
            status,
            transaction_type,
            country_code,
            transaction_data,
            sender_approval,
            created_by,
            user_id
        )
        values (
            v_transaction_reference,
            'processing'::public."TransactionStatus",
            'merchant_payment'::public."TransactionType",
            v_user.country_code,
            p_transaction,
            p_voucher,
            v_user.id,
            v_voucher_owner_id
        )
        returning id::text
        into v_transaction_state_id;

    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'TRANSACTION_REPLAY';
    end;

    return v_transaction_state_id;
end;
$function$;


/*
 * ============================================================
 * 3. FETCH USED VOUCHER BALANCE
 * ============================================================
 */

create or replace function public.fetch_voucher_used_amount(
    p_voucher_reference text
)
returns numeric
language sql
stable
security definer
set search_path to ''
as $function$
    select coalesce(
        sum(voucher_usage_record.debit),
        0
    )::numeric
    from public.voucher_usage voucher_usage_record
    where voucher_usage_record.voucher_reference =
          p_voucher_reference
      and voucher_usage_record.status =
          'success'::public."TransactionStatus";
$function$;


/*
 * ============================================================
 * 4. PRIVILEGES
 * ============================================================
 */

revoke all on function
    public.fetch_my_voucher_payment_context(
        text,
        text
    )
from public;

revoke all on function
    public.create_my_voucher_payment_state(
        jsonb,
        jsonb
    )
from public;

revoke all on function
    public.fetch_voucher_used_amount(
        text
    )
from public;

grant execute on function
    public.fetch_my_voucher_payment_context(
        text,
        text
    )
to authenticated;

grant execute on function
    public.create_my_voucher_payment_state(
        jsonb,
        jsonb
    )
to authenticated;

/*
 * Internal posting helper. The application should not call it
 * directly.
 */
revoke execute on function
    public.fetch_voucher_used_amount(
        text
    )
from anon, authenticated;