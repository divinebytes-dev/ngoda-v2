revoke execute
on function public.fetch_all_transaction_configs(
    text,
    text
)
from public, anon, authenticated;