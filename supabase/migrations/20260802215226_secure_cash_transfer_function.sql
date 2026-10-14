alter function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
owner to postgres;

alter function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
security definer;

alter function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
set search_path = pg_catalog, public;

revoke all
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon, authenticated;

grant usage on schema public
to service_role;

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