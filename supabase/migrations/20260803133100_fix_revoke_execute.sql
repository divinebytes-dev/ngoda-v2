revoke execute
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon;

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