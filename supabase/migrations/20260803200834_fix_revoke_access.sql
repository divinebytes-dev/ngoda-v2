revoke execute
on function public.fetch_user_by_id(text)
from public, anon, authenticated;

revoke execute
on function public.get_transaction_v(text)
from public, anon, authenticated;