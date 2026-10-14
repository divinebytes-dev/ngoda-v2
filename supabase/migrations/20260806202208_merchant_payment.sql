/*
 * ============================================================
 * MERCHANT PAYMENT AUTHENTICATION AND STATE
 *
 * Version: v4
 *
 * Allowed payer roles:
 *   - customer
 *   - vendor
 *   - agent
 *
 * The payer uses a customer wallet.
 * The receiver must have the merchant role.
 * ============================================================
 */


/*
 * ============================================================
 * 1. AUTHENTICATED MERCHANT PAYMENT CONTEXT
 * ============================================================
 */

create or replace function public.fetch_my_merchant_payment_context(
    p_v text,
    p_merchant_id text
)
returns table (
    payer_id text,
    merchant_id text,
    country_code text,
    payer_wallet_address text,
    merchant_wallet_address text,
    version_time bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_payer public.users%rowtype;
    v_merchant public.users%rowtype;
    v_version_time bigint;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_v is distinct from 'v4' then
        raise exception using
            errcode = '42501',
            message = 'OPERATION_NOT_ALLOWED';
    end if;

    if p_merchant_id is null
       or btrim(
           p_merchant_id
       ) = ''
    then
        raise exception
            'MERCHANT_ID_IS_REQUIRED';
    end if;

    /*
     * Validate the authenticated payer role.
     */
    if not public.has_role(
        array[
            'customer',
            'vendor',
            'agent'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select payer_record.*
    into v_payer
    from public.users payer_record
    where payer_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'PAYER_NOT_FOUND';
    end if;

    select merchant_record.*
    into v_merchant
    from public.users merchant_record
    where merchant_record.id =
          p_merchant_id
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    if v_payer.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'PAYER_NOT_ACTIVE';
    end if;

    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;

    if v_payer.id =
       v_merchant.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_payer.country_code is distinct from
       v_merchant.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Validate the receiver's merchant role.
     */
    if not exists (
        select 1
        from public.user_role role_record
        where role_record.id =
              v_merchant.role_id
          and lower(
              role_record.name::text
          ) = 'merchant'
    ) then
        raise exception
            'INVALID_MERCHANT_ROLE';
    end if;

    if v_payer.country_code is null
       or btrim(
           v_payer.country_code
       ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_payer.wallet_address is null
       or btrim(
           v_payer.wallet_address
       ) = ''
    then
        raise exception
            'PAYER_WALLET_NOT_CONFIGURED';
    end if;

    if v_merchant.wallet_address is null
       or btrim(
           v_merchant.wallet_address
       ) = ''
    then
        raise exception
            'MERCHANT_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Continue using the existing transaction-version
     * function.
     */
    select public.get_transaction_v(
        p_v
    )::bigint
    into v_version_time;

    if v_version_time is null
       or v_version_time <= 0
    then
        raise exception
            'INVALID_TRANSACTION_VERSION';
    end if;

    return query
    select
        v_payer.id,
        v_merchant.id,

        lower(
            btrim(
                v_payer.country_code
            )
        ),

        v_payer.wallet_address,
        v_merchant.wallet_address,
        v_version_time;
end;
$function$;


/*
 * ============================================================
 * 2. CREATE MERCHANT PAYMENT PROCESSING STATE
 * ============================================================
 */

create or replace function public.create_my_merchant_payment_state(
    p_transaction jsonb,
    p_approval jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_payer public.users%rowtype;
    v_merchant public.users%rowtype;

    v_reference text;
    v_merchant_id text;
    v_currency text;
    v_version text;

    v_transaction_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_approval is null then
        raise exception
            'SENDER_APPROVAL_MISSING';
    end if;

    if not public.has_role(
        array[
            'customer',
            'vendor',
            'agent'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    if v_version is distinct from 'v4' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    v_merchant_id :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    if v_merchant_id is null then
        raise exception
            'MERCHANT_ID_IS_REQUIRED';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    /*
     * Validate approval fields before storing the state.
     */
    if p_transaction ->> 'a'
       is distinct from
       p_approval ->> 'a'
    then
        raise exception
            'AMOUNT_MISMATCH';
    end if;

    if lower(
        p_transaction ->> 'c'
    ) is distinct from lower(
        p_approval ->> 'c'
    ) then
        raise exception
            'CURRENCY_MISMATCH';
    end if;

    if p_transaction ->> 'r'
       is distinct from
       p_approval ->> 'r'
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    select payer_record.*
    into v_payer
    from public.users payer_record
    where payer_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'PAYER_NOT_FOUND';
    end if;

    select merchant_record.*
    into v_merchant
    from public.users merchant_record
    where merchant_record.id =
          v_merchant_id
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    if v_payer.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'PAYER_NOT_ACTIVE';
    end if;

    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;

    if v_payer.id =
       v_merchant.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_payer.country_code is distinct from
       v_merchant.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if not exists (
        select 1
        from public.user_role role_record
        where role_record.id =
              v_merchant.role_id
          and lower(
              role_record.name::text
          ) = 'merchant'
    ) then
        raise exception
            'INVALID_MERCHANT_ROLE';
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
            v_reference,
            'processing'::public."TransactionStatus",
            'merchant_payment'::public."TransactionType",

            lower(
                btrim(
                    v_payer.country_code
                )
            ),

            p_transaction,
            p_approval,
            v_payer.id,
            v_merchant.id
        )
        returning id::text
        into v_transaction_id;

    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'TRANSACTION_REPLAY';
    end;

    if v_transaction_id is null then
        raise exception
            'TRANSACTION_STATE_CREATE_FAILED';
    end if;

    return v_transaction_id;
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.fetch_my_merchant_payment_context(
    text,
    text
)
owner to postgres;

alter function public.create_my_merchant_payment_state(
    jsonb,
    jsonb
)
owner to postgres;


revoke all
on function public.fetch_my_merchant_payment_context(
    text,
    text
)
from public, anon, authenticated, service_role;

revoke all
on function public.create_my_merchant_payment_state(
    jsonb,
    jsonb
)
from public, anon, authenticated, service_role;


grant execute
on function public.fetch_my_merchant_payment_context(
    text,
    text
)
to authenticated;

grant execute
on function public.create_my_merchant_payment_state(
    jsonb,
    jsonb
)
to authenticated;