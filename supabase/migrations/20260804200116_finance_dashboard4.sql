revoke all
on function public.build_my_finance_reserve_summary()
from public, anon, authenticated;

drop function if exists
    public.build_my_finance_reserve_summary();