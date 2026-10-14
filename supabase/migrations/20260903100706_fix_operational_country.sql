create or replace function public.upsert_operational_country(
    p_country_code text,
    p_name text,
    p_calling_code text,
    p_is_active boolean
)
returns public.operational_country
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user public.users%rowtype;
    v_country public.operational_country%rowtype;
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

    if nullif(trim(p_name), '') is null then
        raise exception using
            errcode = '22023',
            message = 'COUNTRY_NAME_REQUIRED';
    end if;

    if nullif(trim(p_calling_code), '') is null then
        raise exception using
            errcode = '22023',
            message = 'CALLING_CODE_REQUIRED';
    end if;

    /*
     * Upsert by country_code.
     *
     * created_by / created_at remain unchanged when
     * an existing country is updated.
     */
    insert into public.operational_country (
        country_code,
        name,
        calling_code,
        is_active,
        created_by,
        created_at
    )
    values (
        lower(trim(p_country_code)),
        trim(p_name),
        trim(p_calling_code),
        p_is_active,
        v_user.id::text,
        now()
    )
    on conflict (country_code)
    do update
    set
        name = excluded.name,
        calling_code = excluded.calling_code,
        is_active = excluded.is_active,
        updated_by = v_user.id::text,
        updated_at = now()
    returning *
    into v_country;

    return v_country;
end;
$function$;