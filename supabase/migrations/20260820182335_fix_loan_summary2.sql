CREATE OR REPLACE FUNCTION public.fetch_my_vendor_dashboard_context()
RETURNS TABLE(
    wallet_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
     * Return the authenticated active vendor's
     * blockchain wallet address.
     */
    return query
    select
        user_record.wallet_address
    from public.users
        user_record
    join public.user_role
        role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
              auth.uid()::text

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'vendor'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'VENDOR_NOT_AUTHORIZED';
    end if;
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_my_vendor_dashboard_context()
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_vendor_dashboard_context()
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_vendor_dashboard_context()
TO authenticated;

NOTIFY pgrst, 'reload schema';