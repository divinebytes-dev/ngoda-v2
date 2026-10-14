revoke all privileges
on table
    public.users,
    public.transaction_v,
    public.user_role
from anon, authenticated;