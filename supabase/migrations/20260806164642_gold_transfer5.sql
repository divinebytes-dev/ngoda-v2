/*
 * ============================================================
 * GOLD TOKEN SELL AUTHENTICATION AND STATE
 *
 * Version: v7
 * Roles: customer, agent, vendor
 * ============================================================
 */


/*
 * ============================================================
 * 1. AUTHENTICATED GOLD SELL CONTEXT
 * ============================================================
 */

create or replace function public.fetch_my_gold_sell_context(
    p_v text
)
returns table (
    seller_id text,
    country_code text,
    wallet_address text,
    wallet_index bigint,
    version_time bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_seller public.users%rowtype;
    v_version_time bigint;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_v is distinct from 'v7' then
        raise exception using
            errcode = '42501',
            message = 'OPERATION_NOT_ALLOWED';
    end if;

    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_seller
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'SELLER_NOT_FOUND';
    end if;

    if v_seller.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SELLER_NOT_ACTIVE';
    end if;

    if v_seller.country_code is null
       or btrim(
           v_seller.country_code
       ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_seller.wallet_address is null
       or btrim(
           v_seller.wallet_address
       ) = ''
    then
        raise exception
            'USER_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Index zero is valid.
     */
    if v_seller.wallet_index is null then
        raise exception
            'USER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    /*
     * Continue using the existing centralized
     * transaction-version function.
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
        v_seller.id,
        lower(
            btrim(
                v_seller.country_code
            )
        ),
        v_seller.wallet_address,
        v_seller.wallet_index::bigint,
        v_version_time;
end;
$function$;


/*
 * ============================================================
 * 2. CREATE GOLD SELL PROCESSING STATE
 * ============================================================
 */

create or replace function public.create_my_gold_sell_state(
    p_transaction jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_seller public.users%rowtype;

    v_reference text;
    v_version text;
    v_input_currency text;
    v_transaction_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
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

    if v_version is distinct from 'v7' then
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

    v_input_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_input_currency is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    select user_record.*
    into v_seller
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'SELLER_NOT_FOUND';
    end if;

    if v_seller.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SELLER_NOT_ACTIVE';
    end if;

    if v_seller.wallet_address is null
       or btrim(
           v_seller.wallet_address
       ) = ''
    then
        raise exception
            'SELLER_WALLET_NOT_CONFIGURED';
    end if;

    if v_seller.wallet_index is null then
        raise exception
            'SELLER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    begin
        insert into public.transaction_state (
            reference,
            status,
            transaction_type,
            country_code,
            transaction_data,
            created_by,
            user_id
        )
        values (
            v_reference,
            'processing'::public."TransactionStatus",
            'gold_token_sell'::public."TransactionType",
            lower(
                btrim(
                    v_seller.country_code
                )
            ),
            p_transaction,
            v_seller.id,
            v_seller.id
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

alter function public.fetch_my_gold_sell_context(
    text
)
owner to postgres;

alter function public.create_my_gold_sell_state(
    jsonb
)
owner to postgres;


revoke all
on function public.fetch_my_gold_sell_context(
    text
)
from public, anon, authenticated, service_role;

revoke all
on function public.create_my_gold_sell_state(
    jsonb
)
from public, anon, authenticated, service_role;


grant execute
on function public.fetch_my_gold_sell_context(
    text
)
to authenticated;

grant execute
on function public.create_my_gold_sell_state(
    jsonb
)
to authenticated;