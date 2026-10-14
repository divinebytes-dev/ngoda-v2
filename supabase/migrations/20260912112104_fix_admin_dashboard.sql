CREATE OR REPLACE FUNCTION public.build_my_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_total_users integer := 0;
    v_total_credit_agents integer := 0;

    v_global_role_counts jsonb :=
        '{}'::jsonb;

    v_roles jsonb :=
        '[]'::jsonb;

    v_supported_currencies jsonb :=
        '[]'::jsonb;

    v_operational_countries jsonb :=
        '[]'::jsonb;

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
     * Fetch every configured application role.
     */
    select coalesce(
        jsonb_agg(
            configured_role.role_name
            order by
                configured_role.role_name
        ),
        '[]'::jsonb
    )
    into v_roles
    from (
        select lower(
            role_record.name::text
        ) as role_name
        from public.user_role
            role_record
    ) configured_role;

    /*
     * Fetch every currency supported by the system.
     *
     * is_reporting is null because reporting status is a
     * country-level configuration.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                lower(
                    btrim(
                        supported_record.currency_code
                    )
                ),

                'name',
                supported_record.name,

                'decimals',
                supported_record.decimals,

                'symbol',
                supported_record.symbol,

                'rate_api',
                supported_record.rate_api,

                'is_active',
                supported_record.is_active,

                'is_reporting',
                null
            )
            order by
                lower(
                    btrim(
                        supported_record.currency_code
                    )
                )
        ),
        '[]'::jsonb
    )
    into v_supported_currencies
    from public.supported_currency
        supported_record;

    /*
     * Fetch every operational country.
     *
     * Country-currency is_active and is_reporting values
     * come from country_currencies.
     *
     * Currency name, decimals, symbol and rate API come
     * from supported_currency.
     */
        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'country_code',
                    lower(
                        btrim(
                            country_record.country_code
                        )
                    ),

                    'name',
                    country_record.name,

                    'calling_code',
                    country_record.calling_code,

                    'is_active',
                    country_record.is_active,

                    'currencies',
                    coalesce(
                        (
                            select jsonb_agg(
                                jsonb_build_object(
                                    'currency_code',
                                    lower(
                                        btrim(
                                            supported_record.currency_code
                                        )
                                    ),

                                    'name',
                                    supported_record.name,

                                    'decimals',
                                    supported_record.decimals,

                                    'symbol',
                                    supported_record.symbol,

                                    'rate_api',
                                    supported_record.rate_api,

                                    /*
                                    * In this list, is_active is the
                                    * country-currency status.
                                    */
                                    'is_active',
                                    country_currency_record.is_active,

                                    'is_reporting',
                                    country_currency_record.is_reporting
                                )
                                order by
                                    lower(
                                        btrim(
                                            supported_record.currency_code
                                        )
                                    )
                            )
                            from public.country_currencies
                                country_currency_record

                            join public.supported_currency
                                supported_record
                            on lower(
                                btrim(
                                    supported_record.currency_code
                                )
                            ) =
                                lower(
                                    btrim(
                                        country_currency_record.currency_code
                                    )
                                )

                            where lower(
                                btrim(
                                    country_currency_record.country_code
                                )
                            ) =
                                lower(
                                    btrim(
                                        country_record.country_code
                                    )
                                )
                        ),
                        '[]'::jsonb
                    )
                )
                order by
                    country_record.name,
                    country_record.country_code
            ),
            '[]'::jsonb
        )
        into v_operational_countries
        from public.operational_country
            country_record;
    /*
     * Total registered users globally.
     */
    select count(*)::integer
    into v_total_users
    from public.users;

    /*
     * Count active credit agents globally.
     *
     * A credit agent has one account per currency, so
     * merchant_id must be counted distinctly.
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
     * Global user count for every configured role.
     */
    select coalesce(
        jsonb_object_agg(
            role_count.role_name,
            role_count.user_count
            order by
                role_count.role_name
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

        from public.user_role
            role_record

        left join public.users
            user_record
          on user_record.role_id =
             role_record.id

        group by
            lower(
                role_record.name::text
            )
    ) role_count;

    /*
     * Build per-country user totals.
     */
    for v_country in
        select distinct
            lower(
                btrim(
                    user_record.country_code
                )
            ) as country_code

        from public.users
            user_record

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
         * Total users in this country.
         */
        select count(*)::integer
        into v_country_total_users
        from public.users
            user_record
        where lower(
            btrim(
                user_record.country_code
            )
        ) =
            v_country.country_code;

        /*
         * Active credit agents in this country.
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
         */
        select coalesce(
            jsonb_object_agg(
                role_count.role_name,
                role_count.user_count
                order by
                    role_count.role_name
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

            from public.user_role
                role_record

            left join public.users
                user_record
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

        /*
         * Per-country user statistics.
         */
        'countries',
        v_countries,

        /*
         * System configuration.
         */
        'roles',
        v_roles,

        'supportedCurrencies',
        v_supported_currencies,

        'operationalCountries',
        v_operational_countries
    );
end;
$function$
