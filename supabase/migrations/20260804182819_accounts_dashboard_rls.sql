revoke all
on function public.build_my_accounts_dashboard()
from public, anon;

grant execute
on function public.build_my_accounts_dashboard()
to authenticated;