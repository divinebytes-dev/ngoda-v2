alter function public.post_financial_entries(
    text,
    text,
    bigint,
    public."TransactionType",
    text,
    public.posting_component[],
    public.transaction_gl_mapping[],
    text,
    integer,
    integer,
    text,
    public."CustomerDepositType"
)
security definer;

alter function public.post_financial_entries(
    text,
    text,
    bigint,
    public."TransactionType",
    text,
    public.posting_component[],
    public.transaction_gl_mapping[],
    text,
    integer,
    integer,
    text,
    public."CustomerDepositType"
)
set search_path = '';


revoke execute
on function public.post_financial_entries(
    text,
    text,
    bigint,
    public."TransactionType",
    text,
    public.posting_component[],
    public.transaction_gl_mapping[],
    text,
    integer,
    integer,
    text,
    public."CustomerDepositType"
)
from public, anon, authenticated;

