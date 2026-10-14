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
     * Identify the caller from the Supabase JWT.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Cash transfers may be performed by:
     *
     * - customers
     * - agents
     * - vendors
     *
     * Each role performs the transfer using its
     * customer-owned wallet.
     */
    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Return trusted sender information.
     *
     * The sender ID, country code and wallet address
     * are derived from auth.uid(), not from the request.
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


/*
 * Only authenticated users may fetch their own
 * cash-transfer context.
 */
revoke execute on function
    public.fetch_my_cash_transfer_context(text)
from public, anon;

grant execute on function
    public.fetch_my_cash_transfer_context(text)
to authenticated;