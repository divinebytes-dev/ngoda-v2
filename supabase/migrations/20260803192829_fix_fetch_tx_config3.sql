revoke execute
on function public.fetch_my_transaction_configs()
from public, anon;

grant execute
on function public.fetch_my_transaction_configs()
to authenticated;

revoke execute
on function public.fetch_all_transaction_configs(
    text,
    text
)
from public, anon, authenticated;

notify pgrst, 'reload schema';