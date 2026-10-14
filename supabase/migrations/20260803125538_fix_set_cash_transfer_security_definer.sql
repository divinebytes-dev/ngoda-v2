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
set search_path = '';

revoke all
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public;

grant execute
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to authenticated;