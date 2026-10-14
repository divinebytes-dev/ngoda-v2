revoke all
on function public.fetch_operational_countries()
from public, anon, authenticated, service_role;

grant execute
on function public.fetch_operational_countries()
to anon;

revoke all privileges
on table public.operational_country
from anon, authenticated;

notify pgrst, 'reload schema';