DROP FUNCTION IF EXISTS public.fetch_my_gold_buy_context(text);

CREATE OR REPLACE FUNCTION public.fetch_my_gold_buy_context(
    p_v text,
    p_blockchain_code text
)
RETURNS TABLE(
    user_id text,
    country_code text,
    wallet_address text,
    version_time integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_v is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

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

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    if not exists (
        select 1
        from public.supported_blockchain b
        where b.code = v_blockchain_code
          and b.is_active = true
    ) then
        raise exception
            'BLOCKCHAIN_NOT_SUPPORTED';
    end if;

    return query
    select
        u.id,
        u.country_code,
        u.wallet_address,
        public.get_transaction_v(p_v)
    from public.users u
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'GOLD_BUY_CONTEXT_NOT_FOUND';
    end if;
end;
$function$;



DROP FUNCTION IF EXISTS public.create_my_gold_buy_state(jsonb);

CREATE OR REPLACE FUNCTION public.create_my_gold_buy_state(
    p_transaction jsonb,
    p_blockchain_code text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user_id text;
    v_country_code text;
    v_reference text;
    v_version text;
    v_blockchain_code text;
    v_transaction_state_id text;
    v_transaction_data jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

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
       or jsonb_typeof(p_transaction) <> 'object'
    then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    v_version :=
        nullif(btrim(p_transaction ->> 'v'), '');

    if v_version is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(btrim(p_transaction ->> 'r'), '');

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    if not exists (
        select 1
        from public.supported_blockchain b
        where b.code = v_blockchain_code
          and b.is_active = true
    ) then
        raise exception
            'BLOCKCHAIN_NOT_SUPPORTED';
    end if;

    v_user_id := auth.uid()::text;

    select u.country_code
    into v_country_code
    from public.users u
    where u.id = v_user_id
      and u.status = 'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Preserve the signed transaction fields.
     * Add the selected blockchain as separate metadata.
     */
    v_transaction_data :=
        p_transaction ||
        jsonb_build_object(
            'blockchain_code',
            v_blockchain_code
        );

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
        'gold_token_buy'::public."TransactionType",
        v_country_code,
        v_transaction_data,
        v_user_id,
        v_user_id
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



