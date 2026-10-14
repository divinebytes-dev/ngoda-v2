alter table public.document_sequence
alter column id set default gen_random_uuid();