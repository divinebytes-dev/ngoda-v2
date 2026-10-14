/*
 * ============================================================
 * CENTRALIZED ROLE VALIDATION
 *
 * Transaction functions must call only:
 *
 *     public.has_role(text[])
 *
 * public.user_has_role() is an internal helper.
 * ============================================================
 */


/*
 * Internal helper.
 *
 * This function can validate a specified user, but it is not
 * exposed directly to authenticated clients.
 */
create or replace function public.user_has_role(
    p_user_id text,
    p_allowed_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
    select
        p_user_id is not null

        and coalesce(
            cardinality(
                p_allowed_roles
            ),
            0
        ) > 0

        and exists (
            select 1
            from public.users user_record

            join public.user_role role_record
              on role_record.id =
                 user_record.role_id

            where user_record.id =
                  p_user_id

              and user_record.status =
                  'active'::public."UserStatus"

              and lower(
                  role_record.name::text
              ) in (
                  select lower(
                      allowed_role
                  )
                  from unnest(
                      p_allowed_roles
                  ) as allowed_role
              )
        );
$function$;


/*
 * The only role-validation function that transaction
 * functions should call.
 *
 * The user ID always comes from auth.uid().
 */
create or replace function public.has_role(
    p_allowed_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
    select
        auth.uid() is not null

        and public.user_has_role(
            auth.uid()::text,
            p_allowed_roles
        );
$function$;


/*
 * Ensure both functions execute with postgres table access.
 */
alter function public.user_has_role(
    text,
    text[]
)
owner to postgres;

alter function public.has_role(
    text[]
)
owner to postgres;


/*
 * The internal helper must not be callable directly by
 * application roles.
 */
revoke all
on function public.user_has_role(
    text,
    text[]
)
from public, anon, authenticated, service_role;


/*
 * Only the centralized authenticated wrapper is exposed.
 */
revoke all
on function public.has_role(
    text[]
)
from public, anon, authenticated, service_role;

grant execute
on function public.has_role(
    text[]
)
to authenticated, service_role;