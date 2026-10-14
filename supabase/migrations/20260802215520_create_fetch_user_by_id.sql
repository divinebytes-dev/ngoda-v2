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