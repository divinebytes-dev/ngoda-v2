grant execute
on function public.fetch_all_transaction_configs(
    text,
    text
)
to postgres;

revoke execute
on function public.fetch_all_transaction_configs(
    text,
    text
)
from public, anon, authenticated;

grant execute
on function public.fetch_my_transaction_configs()
to authenticated;

notify pgrst, 'reload schema';
