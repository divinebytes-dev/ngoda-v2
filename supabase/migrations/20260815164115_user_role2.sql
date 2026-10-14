CREATE OR REPLACE FUNCTION public.change_my_user_role(
    p_identifier text,
    p_new_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_admin public.users%rowtype;
    v_target_user public.users%rowtype;

    v_old_role public.user_role%rowtype;
    v_new_role public.user_role%rowtype;

    v_identifier text;
    v_new_role_name text;

    v_fiscal_year integer;
    v_period integer;

    v_changed boolean := false;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate and authorize the global system
     * administrator.
     */
    v_stage := 'authorize administrator';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'admin'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    v_stage := 'validate input';

    v_identifier :=
        nullif(
            btrim(p_identifier),
            ''
        );

    v_new_role_name :=
        lower(
            nullif(
                btrim(p_new_role),
                ''
            )
        );

    if v_identifier is null then
        raise exception
            'USER_IDENTIFIER_REQUIRED';
    end if;

    if v_new_role_name is null then
        raise exception
            'NEW_ROLE_REQUIRED';
    end if;

    if v_new_role_name = 'admin' then
        raise exception
            'CANNOT_ASSIGN_ROLE';
    end if;

    /*
     * Fetch the administrator.
     */
    v_stage := 'fetch administrator';

    v_admin :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_admin.id is null then
        raise exception
            'ADMIN_USER_NOT_FOUND';
    end if;

    /*
     * Fetch the target user using email, phone or user ID.
     */
    v_stage := 'fetch target user';

    select user_record.*
    into v_target_user
    from public.users user_record
    where lower(
        coalesce(
            user_record.email,
            ''
        )
    ) =
        lower(v_identifier)

       or user_record.phone =
          v_identifier

       or user_record.id =
          v_identifier
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_target_user.id =
       v_admin.id
    then
        raise exception
            'CANNOT_CHANGE_OWN_ROLE';
    end if;

    if v_target_user.country_code is null
       or btrim(v_target_user.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch the user's current role.
     */
    v_stage := 'fetch current role';

    select role_record.*
    into v_old_role
    from public.user_role role_record
    where role_record.id =
          v_target_user.role_id
    limit 1;

    if not found then
        raise exception
            'CURRENT_ROLE_NOT_FOUND';
    end if;

    /*
     * Fetch the requested role.
     */
    v_stage := 'fetch new role';

    select role_record.*
    into v_new_role
    from public.user_role role_record
    where lower(
        role_record.name::text
    ) =
        v_new_role_name
    limit 1;

    if not found then
        raise exception
            'ROLE_NOT_FOUND';
    end if;

    /*
     * Make the operation idempotent.
     *
     * If the database role is already correct, return the
     * user information so the Edge Function can retry the
     * Supabase Auth metadata update.
     */
    if v_target_user.role_id =
       v_new_role.id
    then
        return jsonb_build_object(
            'success',
            true,

            'changed',
            false,

            'user_id',
            v_target_user.id,

            'user_email',
            v_target_user.email,

            'user_phone',
            v_target_user.phone,

            'country_code',
            lower(
                v_target_user.country_code
            ),

            'old_role_name',
            lower(
                v_old_role.name::text
            ),

            'new_role_name',
            lower(
                v_new_role.name::text
            )
        );
    end if;

    /*
     * Use the target user's country for the fiscal period.
     */
    v_stage := 'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_target_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Update the public application user.
     */
    v_stage := 'update user role';

    update public.users
    set
        role_id =
            v_new_role.id,

        updated_at =
            now()
    where id =
          v_target_user.id;

    if not found then
        raise exception
            'USER_ROLE_UPDATE_FAILED';
    end if;

    v_changed := true;

    /*
     * Audit the role change.
     */
    v_stage := 'create audit log';

    insert into public.audit_log (
        fiscal_year,
        period,
        country_code,
        document_number,
        user_id,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata
    )
    values (
        v_fiscal_year,
        v_period,
        v_target_user.country_code,
        '',
        v_admin.id,
        'user_role_changed'::public."AuditActionType",
        'user',
        v_target_user.id,

        jsonb_build_object(
            'role_id',
            v_old_role.id,

            'role_name',
            lower(
                v_old_role.name::text
            )
        ),

        jsonb_build_object(
            'role_id',
            v_new_role.id,

            'role_name',
            lower(
                v_new_role.name::text
            )
        ),

        jsonb_build_object(
            'identifier',
            v_identifier,

            'user_email',
            v_target_user.email,

            'user_phone',
            v_target_user.phone,

            'changed_by',
            v_admin.id
        )
    );

    return jsonb_build_object(
        'success',
        true,

        'changed',
        v_changed,

        'user_id',
        v_target_user.id,

        'user_email',
        v_target_user.email,

        'user_phone',
        v_target_user.phone,

        'country_code',
        lower(
            v_target_user.country_code
        ),

        'old_role_name',
        lower(
            v_old_role.name::text
        ),

        'new_role_name',
        lower(
            v_new_role.name::text
        )
    );

exception
    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_error_message =
                message_text,

            v_error_detail =
                pg_exception_detail,

            v_error_hint =
                pg_exception_hint,

            v_error_context =
                pg_exception_context;

        raise exception using
            errcode =
                v_error_state,

            message =
                format(
                    'CHANGE_USER_ROLE_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                concat_ws(
                    E'\n',
                    nullif(
                        v_error_detail,
                        ''
                    ),
                    nullif(
                        v_error_context,
                        ''
                    )
                ),

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    format(
                        'Check the User Role Change stage: %s',
                        v_stage
                    )
                );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.change_my_user_role(
        text,
        text
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.change_my_user_role(
        text,
        text
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.change_my_user_role(
        text,
        text
    )
TO authenticated;