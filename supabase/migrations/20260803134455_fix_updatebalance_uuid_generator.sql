alter table public.gl_balance_snapshot
alter column id set default gen_random_uuid();