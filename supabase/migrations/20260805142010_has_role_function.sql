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
        and exists (
            select 1
            from public.users user_record
            join public.user_role role_record
              on role_record.id =
                 user_record.role_id
            where user_record.id =
                  auth.uid()::text
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


revoke execute on function public.has_role(
    public."Role"[]
)
from public, anon;

grant execute on function public.has_role(
    public."Role"[]
)
to authenticated;


create or replace function public.fetch_my_cash_transfer_context(
    p_v text
)
returns table (
    sender_id text,
    country_code text,
    wallet_address text,
    version_time integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    /*
     * Confirm that the request contains a valid
     * authenticated Supabase user.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Cash transfers may be performed by users whose
     * main role is customer, agent or vendor.
     *
     * Each role performs the transaction through its
     * customer-owned wallet.
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

    /*
     * Return trusted sender information derived from
     * auth.uid(). Nothing here comes from the client
     * request body.
     */
    return query
    select
        user_record.id,
        user_record.country_code,
        user_record.wallet_address,
        public.get_transaction_v(p_v)
    from public.users user_record
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;
end;
$function$;


revoke execute on function
    public.fetch_my_cash_transfer_context(text)
from public, anon;

grant execute on function
    public.fetch_my_cash_transfer_context(text)
to authenticated;