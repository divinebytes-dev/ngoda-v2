revoke all
on function public.get_last_wallet_transactions(
    text,
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
)
from public, anon, authenticated;