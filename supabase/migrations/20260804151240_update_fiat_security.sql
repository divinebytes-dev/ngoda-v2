grant usage on schema public
to service_role;

grant select
on table public.supported_currency
to service_role;

grant select, update
on table public.current_rates
to service_role;