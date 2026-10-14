create table if not exists public.user_presence (
    user_id text primary key,
    is_online boolean not null default false,
    last_seen_at timestamptz not null default now()
);

alter table public.user_presence
enable row level security;


/*
 * User may read only their own presence row.
 */
drop policy if exists
    user_presence_select_own
on public.user_presence;

create policy
    user_presence_select_own
on public.user_presence
for select
to authenticated
using (
    user_id = auth.uid()::text
);


/*
 * User may create only their own presence row.
 */
drop policy if exists
    user_presence_insert_own
on public.user_presence;

create policy
    user_presence_insert_own
on public.user_presence
for insert
to authenticated
with check (
    user_id = auth.uid()::text
);


/*
 * User may update only their own presence row,
 * and cannot change it to another user's ID.
 */
drop policy if exists
    user_presence_update_own
on public.user_presence;

create policy
    user_presence_update_own
on public.user_presence
for update
to authenticated
using (
    user_id = auth.uid()::text
)
with check (
    user_id = auth.uid()::text
);


drop policy if exists
    user_presence_select_authenticated
on public.user_presence;

create policy
    user_presence_select_authenticated
on public.user_presence
for select
to authenticated
using (true);