create or replace function public.fetch_transaction_type_wallet_owner(
    p_transaction_type public."TransactionType"
)
returns public.transaction_type_wallet_owner
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_wallet_owner
        public.transaction_type_wallet_owner%rowtype;
begin
    if p_transaction_type is null then
        raise exception
            'TRANSACTION_TYPE_REQUIRED';
    end if;

    /*
     * Preserve Prisma findFirst behaviour.
     */
    select wallet_owner_record.*
    into v_wallet_owner
    from public.transaction_type_wallet_owner
        wallet_owner_record
    where wallet_owner_record.transaction_type =
          p_transaction_type
    limit 1;

    if not found then
        raise exception
            '%',
            upper(
                p_transaction_type::text ||
                '_WALLET_OWNER_NOT_FOUND'
            );
    end if;

    return v_wallet_owner;
end;
$function$;


revoke all on function
    public.fetch_transaction_type_wallet_owner(
        public."TransactionType"
    )
from public;

revoke all on function
    public.fetch_transaction_type_wallet_owner(
        public."TransactionType"
    )
from anon;

grant execute on function
    public.fetch_transaction_type_wallet_owner(
        public."TransactionType"
    )
to authenticated;

notify pgrst, 'reload schema';