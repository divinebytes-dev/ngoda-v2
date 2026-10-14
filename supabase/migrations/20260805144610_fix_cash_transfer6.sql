begin;

grant usage
on schema public
to service_role;

grant select
on table public.financial_entry
to service_role;

commit;

notify pgrst, 'reload schema';