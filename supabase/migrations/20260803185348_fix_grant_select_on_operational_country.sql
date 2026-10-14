revoke all privileges
on table public.operational_country
from anon, authenticated;

grant execute
on function public.fetch_operational_countries()
to service_role;

notify pgrst, 'reload schema';