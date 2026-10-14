revoke all
on function public.get_my_last_wallet_transactions(
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
)
from public, anon;

grant execute
on function public.get_my_last_wallet_transactions(
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
)
to authenticated;