/* =========================================================
 * USER HAS ROLE
 * ========================================================= */

create or replace function public.user_has_role(
    p_user_id text,
    p_allowed_roles public."Role"[]
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
    select
        p_user_id is not null
        and cardinality(p_allowed_roles) > 0
        and exists (
            select 1
            from public.users user_record
            join public.user_role role_record
              on role_record.id =
                 user_record.role_id
            where user_record.id =
                  p_user_id
              and user_record.status =
                  'active'::public."UserStatus"
              and lower(
                  role_record.name::text
              ) in (
                  select lower(
                      allowed_role::text
                  )
                  from unnest(
                      p_allowed_roles
                  ) as allowed_role
              )
        );
$function$;


/*
 * This supporting function is only used internally
 * by postgres-owned security-definer functions.
 */
revoke execute on function public.user_has_role(
    text,
    public."Role"[]
)
from public, anon, authenticated, service_role;


/* =========================================================
 * AUTHENTICATED USER HAS ROLE
 * ========================================================= */

create or replace function public.has_role(
    p_allowed_roles public."Role"[]
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
    select
        auth.uid() is not null
        and public.user_has_role(
            auth.uid()::text,
            p_allowed_roles
        );
$function$;


revoke execute on function public.has_role(
    public."Role"[]
)
from public, anon;

grant execute on function public.has_role(
    public."Role"[]
)
to authenticated;

/* =========================================================
 * FETCH MY CASH-DEPOSIT CONTEXT
 * ========================================================= */

create or replace function public.fetch_my_cash_deposit_context(
    p_v text,
    p_provider_id text
)
returns table (
    user_id text,
    country_code text,
    user_wallet_address text,
    provider_id text,
    provider_country_code text,
    provider_wallet_address text,
    version_time integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    /*
     * Validate authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Customer-wallet transactions may be initiated by
     * customers, agents and vendors.
     */
    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_provider_id is null
       or btrim(p_provider_id) = ''
    then
        raise exception
            'PROVIDER_ID_MISSING';
    end if;

    if auth.uid()::text =
       btrim(p_provider_id)
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * The cash provider must have either an agent
     * or merchant or vendor role.
     */
    if not public.user_has_role(
        btrim(p_provider_id),
        array[
            'agent'::public."Role",
            'merchant'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'PROVIDER_NOT_AUTHORIZED';
    end if;

    /*
     * Return trusted information for both participants.
     */
    return query
    select
        user_record.id,
        user_record.country_code,
        user_record.wallet_address,

        provider_record.id,
        provider_record.country_code,
        provider_record.wallet_address,

        public.get_transaction_v(p_v)
    from public.users user_record
    join public.users provider_record
      on provider_record.id =
         btrim(p_provider_id)
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and provider_record.status =
          'active'::public."UserStatus"
      and user_record.country_code =
          provider_record.country_code
    limit 1;

    if not found then
        raise exception
            'CASH_DEPOSIT_CONTEXT_NOT_FOUND';
    end if;
end;
$function$;


revoke execute on function
    public.fetch_my_cash_deposit_context(
        text,
        text
    )
from public, anon;

grant execute on function
    public.fetch_my_cash_deposit_context(
        text,
        text
    )
to authenticated;


/* =========================================================
 * CREATE MY CASH-DEPOSIT TRANSACTION STATE
 * ========================================================= */

create or replace function public.create_my_cash_deposit_state(
    p_transaction jsonb,
    p_sender_approval jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
    v_country_code text;
    v_provider_id text;
    v_reference text;
    v_transaction_state_id text;
begin
    /*
     * Validate authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Validate initiating role.
     */
    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_transaction is null
       or jsonb_typeof(p_transaction) <>
          'object'
    then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_sender_approval is null
       or jsonb_typeof(p_sender_approval) <>
          'object'
    then
        raise exception
            'SENDER_APPROVAL_MISSING';
    end if;

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_provider_id :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_provider_id is null then
        raise exception
            'PROVIDER_ID_MISSING';
    end if;

    v_user_id :=
        auth.uid()::text;

    if v_user_id = v_provider_id then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Validate the provider role.
     */
    if not public.user_has_role(
        v_provider_id,
        array[
            'agent'::public."Role",
            'merchant'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'PROVIDER_NOT_AUTHORIZED';
    end if;

    /*
     * Read the initiating user's country and ensure that
     * the provider belongs to the same country.
     */
    select user_record.country_code
    into v_country_code
    from public.users user_record
    join public.users provider_record
      on provider_record.id =
         v_provider_id
    where user_record.id =
          v_user_id
      and user_record.status =
          'active'::public."UserStatus"
      and provider_record.status =
          'active'::public."UserStatus"
      and provider_record.country_code =
          user_record.country_code
    limit 1;

    if not found then
        raise exception
            'CASH_DEPOSIT_PARTICIPANTS_NOT_VALID';
    end if;

    /*
     * Reference is unique and provides replay protection.
     */
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
        'cash_deposit'::public."TransactionType",
        v_country_code,
        p_transaction,
        p_sender_approval,
        v_user_id,
        v_provider_id
    )
    returning id::text
    into v_transaction_state_id;

    return v_transaction_state_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$function$;


revoke execute on function
    public.create_my_cash_deposit_state(
        jsonb,
        jsonb
    )
from public, anon;

grant execute on function
    public.create_my_cash_deposit_state(
        jsonb,
        jsonb
    )
to authenticated;


/* =========================================================
 * FUNCTION OWNERS
 * ========================================================= */

alter function public.user_has_role(
    text,
    public."Role"[]
)
owner to postgres;

alter function public.has_role(
    public."Role"[]
)
owner to postgres;

alter function public.fetch_my_cash_deposit_context(
    text,
    text
)
owner to postgres;

alter function public.create_my_cash_deposit_state(
    jsonb,
    jsonb
)
owner to postgres;


/* =========================================================
 * RELOAD POSTGREST
 * ========================================================= */

notify pgrst, 'reload schema';