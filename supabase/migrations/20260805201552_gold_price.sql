revoke all
on function public.fetch_gold_price()
from public;

grant execute
on function public.fetch_gold_price()
to anon, authenticated;