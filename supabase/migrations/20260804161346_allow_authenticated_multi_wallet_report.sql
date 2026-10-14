alter function public.get_multi_wallet_balances(text)
security invoker;

revoke all
on function public.get_multi_wallet_balances(text)
from public, anon;

grant usage on schema public
to authenticated;

grant execute
on function public.get_multi_wallet_balances(text)
to authenticated;