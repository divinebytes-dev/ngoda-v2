create or replace function public.upsert_country_currency(
    p_country_code text,
    p_currency_code text,
    p_is_active boolean
)
returns public.country_currencies
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user public.users%rowtype;
    v_country_currency public.country_currencies%rowtype;
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
    if nullif(trim(p_country_code), '') is null then
        raise exception using
            errcode = '22023',
            message = 'COUNTRY_CODE_REQUIRED';
    end if;

    if nullif(trim(p_currency_code), '') is null then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_CODE_REQUIRED';
    end if;

    /*
     * Make sure operational country exists.
     */
    if not exists (
        select 1
        from public.operational_country oc
        where oc.country_code = lower(trim(p_country_code))
    ) then
        raise exception using
            errcode = '22023',
            message = 'COUNTRY_NOT_FOUND';
    end if;

    /*
     * Make sure supported currency exists.
     */
    if not exists (
        select 1
        from public.supported_currency sc
        where sc.currency_code = lower(trim(p_currency_code))
    ) then
        raise exception using
            errcode = '22023',
            message = 'CURRENCY_NOT_FOUND';
    end if;

    /*
     * Upsert country/currency relationship.
     */
    insert into public.country_currencies (
        country_code,
        currency_code,
        is_active,
        created_by,
        created_at
    )
    values (
        lower(trim(p_country_code)),
        lower(trim(p_currency_code)),
        p_is_active,
        v_user.id::text,
        now()
    )
    on conflict (
        country_code,
        currency_code
    )
    do update
    set
        is_active = excluded.is_active,
        updated_by = v_user.id::text,
        updated_at = now()
    returning *
    into v_country_currency;

    return v_country_currency;
end;
$function$;