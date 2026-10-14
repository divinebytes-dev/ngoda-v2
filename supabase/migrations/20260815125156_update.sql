CREATE OR REPLACE FUNCTION public.build_my_admin_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_total_users integer := 0;
    v_total_credit_agents integer := 0;

    v_global_role_counts jsonb :=
        '{}'::jsonb;

    v_countries jsonb :=
        '[]'::jsonb;

    v_country record;
    v_country_role_counts jsonb;
    v_country_total_users integer;
    v_country_credit_agents integer;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Only the global system administrator may access
     * this dashboard.
     */
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
     * Total registered users across every country.
     */
    select count(*)::integer
    into v_total_users
    from public.users;

    /*
     * Count approved credit agents globally.
     *
     * A merchant may have one credit_agent_account row
     * per currency, therefore merchant_id must be counted
     * distinctly.
     */
    select count(
        distinct account_record.merchant_id
    )::integer
    into v_total_credit_agents
    from public.credit_agent_account
        account_record
    join public.users merchant_record
      on merchant_record.id =
         account_record.merchant_id
    where account_record.is_active =
          true

      and merchant_record.status =
          'active'::public."UserStatus";

    /*
     * Global totals per actual application role.
     *
     * Roles with no users are still returned with zero.
     */
    select coalesce(
        jsonb_object_agg(
            role_count.role_name,
            role_count.user_count
            order by role_count.role_name
        ),
        '{}'::jsonb
    )
    into v_global_role_counts
    from (
        select
            lower(
                role_record.name::text
            ) as role_name,

            count(
                user_record.id
            )::integer as user_count

        from public.user_role role_record

        left join public.users user_record
          on user_record.role_id =
             role_record.id

        group by
            lower(
                role_record.name::text
            )
    ) role_count;

    /*
     * Build one dashboard row for every country that has
     * at least one registered user.
     */
    for v_country in
        select distinct
            lower(
                btrim(
                    user_record.country_code
                )
            ) as country_code

        from public.users user_record

        where nullif(
            btrim(
                user_record.country_code
            ),
            ''
        ) is not null

        order by
            lower(
                btrim(
                    user_record.country_code
                )
            )
    loop
        /*
         * Total users in the selected country.
         */
        select count(*)::integer
        into v_country_total_users
        from public.users user_record
        where lower(
            btrim(
                user_record.country_code
            )
        ) =
            v_country.country_code;

        /*
         * Active credit agents in the selected country.
         */
        select count(
            distinct account_record.merchant_id
        )::integer
        into v_country_credit_agents
        from public.credit_agent_account
            account_record
        join public.users merchant_record
          on merchant_record.id =
             account_record.merchant_id
        where lower(
            btrim(
                account_record.country_code
            )
        ) =
            v_country.country_code

          and account_record.is_active =
              true

          and merchant_record.status =
              'active'::public."UserStatus";

        /*
         * User counts per role for this country.
         *
         * Every configured role is included, even when
         * its count is zero.
         */
        select coalesce(
            jsonb_object_agg(
                role_count.role_name,
                role_count.user_count
                order by role_count.role_name
            ),
            '{}'::jsonb
        )
        into v_country_role_counts
        from (
            select
                lower(
                    role_record.name::text
                ) as role_name,

                count(
                    user_record.id
                )::integer as user_count

            from public.user_role role_record

            left join public.users user_record
              on user_record.role_id =
                 role_record.id

             and lower(
                 btrim(
                     user_record.country_code
                 )
             ) =
                 v_country.country_code

            group by
                lower(
                    role_record.name::text
                )
        ) role_count;

        v_countries :=
            v_countries ||
            jsonb_build_array(
                jsonb_build_object(
                    'countryCode',
                    v_country.country_code,

                    'totalUsers',
                    v_country_total_users,

                    'creditAgents',
                    v_country_credit_agents,

                    'roleCounts',
                    v_country_role_counts
                )
            );
    end loop;

    return jsonb_build_object(
        'summary',
        jsonb_build_object(
            'totalUsers',
            v_total_users,

            'creditAgents',
            v_total_credit_agents,

            'roleCounts',
            v_global_role_counts
        ),

        'countries',
        v_countries
    );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.build_my_admin_dashboard()
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.build_my_admin_dashboard()
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.build_my_admin_dashboard()
TO authenticated;