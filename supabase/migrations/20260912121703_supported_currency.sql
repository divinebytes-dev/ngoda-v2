create or replace function public.upsert_supported_currency(
    p_currency_code text,
    p_name text,
    p_symbol text,
    p_decimals integer,
    p_rate_url text,
    p_is_active boolean
)
returns public.supported_currency
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user public.users%rowtype;
    v_currency public.supported_currency%rowtype;
begin
    /*
     * Authentication
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Authorization
     */
    if not public.has_role(
        array[
            'admin'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch authenticated user.
     */
    select u.*
    into v_user
    from public.users u
    where u.id = auth.uid();

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'USER_NOT_FOUND';
    end if;

    /*
     * Validation
     */
    if nullif(trim(p_currency_code), '') is null then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_CODE_REQUIRED';
    end if;

    if nullif(trim(p_name), '') is null then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_NAME_REQUIRED';
    end if;

    if nullif(trim(p_symbol), '') is null then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_SYMBOL_REQUIRED';
    end if;

    if p_decimals is null then
        raise exception using
            errcode = '22023',
            message = 'DECIMALS_REQUIRED';
    end if;

    if p_decimals < 0 then
        raise exception using
            errcode = '22023',
            message = 'INVALID_DECIMALS';
    end if;

    if p_decimals > 18 then
        raise exception using
            errcode = '22023',
            message = 'INVALID_DECIMALS';
    end if;

    if nullif(trim(p_rate_url), '') is null then
        raise exception using
            errcode = '22023',
            message = 'RATE_URL_REQUIRED';
    end if;

    /*
     * Upsert currency.
     *
     * currency_category remains fiat for this admin
     * function, matching the previous implementation.
     *
     * created_by / created_at remain unchanged
     * during updates.
     */
    insert into public.supported_currency (
        currency_code,
        name,
        symbol,
        decimals,
        rate_url,
        currency_category,
        is_active,
        created_by,
        created_at
    )
    values (
        lower(trim(p_currency_code)),
        trim(p_name),
        trim(p_symbol),
        p_decimals,
        trim(p_rate_url),
        'fiat',
        p_is_active,
        v_user.id::text,
        now()
    )
    on conflict (currency_code)
    do update
    set
        name = excluded.name,
        symbol = excluded.symbol,
        decimals = excluded.decimals,
        rate_url = excluded.rate_url,
        is_active = excluded.is_active,
        updated_by = v_user.id::text,
        updated_at = now()
    returning *
    into v_currency;

    return v_currency;
end;
$function$;


