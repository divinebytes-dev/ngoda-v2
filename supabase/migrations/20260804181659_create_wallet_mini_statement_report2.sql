create or replace function public.get_my_last_wallet_transactions(
    p_start_date timestamptz,
    p_end_date timestamptz,
    p_currency_code text default null,
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Fetch the authenticated application user and
     * validate status and required role.
     */
    select u.id
    into v_user_id
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'admin',
          'agent',
          'vendor',
          'finance',
          'treasury',
          'customer',
          'merchant',
          'accounts'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Run the existing internal report using the
     * authenticated application user ID.
     */
    return public.get_last_wallet_transactions(
        v_user_id,
        p_start_date,
        p_end_date,
        p_currency_code,
        p_page,
        p_page_size
    );
end;
$function$;