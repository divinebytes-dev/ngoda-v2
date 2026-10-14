/* =========================================================
 * FETCH ACTIVE USER BY ID
 * ========================================================= */
create or replace function public.fetch_user_by_id(
    p_user_id text
)
returns setof public.users
language plpgsql
stable
as $$
declare
    v_user public.users%rowtype;
begin
    select u.*
    into v_user
    from public.users u
    where u.id = p_user_id
    limit 1;

    if not found then
        raise exception 'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception 'USER_NOT_ACTIVE';
    end if;

    return next v_user;
    return;
end;
$$;

/* =========================================================
 * FETCH ACTIVE USER BY EMAIL
 * ========================================================= */
create or replace function public.fetch_user_by_email_or_phone(
    p_email_or_phone text
)
returns public.users
language plpgsql
stable
as $$
declare
    v_value text;
    v_user public.users%rowtype;
begin
    v_value := lower(btrim(p_email_or_phone));

    select u.*
    into v_user
    from public.users u
    where u.email = v_value
       or u.phone = v_value
    limit 1;

    if not found then
        raise exception 'USER_NOT_FOUND';
    end if;

    if v_user.status <> 'active'::public."UserStatus" then
        raise exception 'USER_NOT_ACTIVE';
    end if;

    return v_user;
end;
$$;

/* =========================================================
 * FETCH COUNTRY TREASURY
 * ========================================================= */
create or replace function public.fetch_country_treasury(
    p_country_code text
)
returns public.users
language plpgsql
stable
as $$
declare
    v_treasury public.users%rowtype;
begin
    select u.*
    into v_treasury
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.country_code = p_country_code
      and r.name = 'treasury'
    limit 1;

    if not found then
        raise exception 'TREASURY_NOT_FOUND';
    end if;

    return v_treasury;
end;
$$;