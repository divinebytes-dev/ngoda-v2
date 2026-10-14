/* Edge Function service-role permissions */

grant usage on schema public
to service_role;

/*
 * Used by fetchUserWithId().
 */
grant select on table
    public.users,
    public.user_role,

to service_role;

/*
 * Used when creating and updating transaction state.
 */
grant select, insert, update
on table public.transaction_state
to service_role;

/*
 * Used by fetchTransactionV().
 */
grant select
on table public.transaction_v
to service_role;

grant execute
on function public.get_transaction_v(text)
to service_role;

/*
 * Main protected posting function.
 */
grant execute
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to service_role;

