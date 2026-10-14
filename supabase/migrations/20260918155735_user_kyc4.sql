CREATE OR REPLACE FUNCTION public.build_my_compliance_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE

    -- ========================================================
    -- GLOBAL COUNTS
    -- ========================================================

    v_total_users integer := 0;
    v_started integer := 0;
    v_not_started integer := 0;
    v_verified integer := 0;
    v_rejected integer := 0;
    v_pending_review integer := 0;


    -- ========================================================
    -- JSON RESULTS
    -- ========================================================

    v_role_counts jsonb :=
        '{}'::jsonb;

    v_countries jsonb :=
        '[]'::jsonb;


    -- ========================================================
    -- COUNTRY LOOP
    -- ========================================================

    v_country record;

    v_country_total_users integer;
    v_country_started integer;
    v_country_not_started integer;
    v_country_verified integer;
    v_country_rejected integer;
    v_country_pending_review integer;

    v_country_role_counts jsonb;

BEGIN

    -- ========================================================
    -- AUTHENTICATION
    -- ========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    -- ========================================================
    -- AUTHORIZATION
    --
    -- Only compliance users may access this dashboard.
    -- ========================================================

    IF NOT public.has_role(
        ARRAY[
            'compliance'
        ]::text[]
    ) THEN

        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';

    END IF;


    -- ========================================================
    -- GLOBAL KYC STATISTICS
    --
    -- Start from users because a user does not have a
    -- user_kyc record until KYC has actually started.
    --
    -- Only the following roles participate in KYC:
    --
    -- customer
    -- agent
    -- vendor
    -- merchant
    -- ========================================================

    SELECT

        count(*)::integer,

        count(
            kyc_record.id
        )::integer,

        count(*) FILTER (
            WHERE kyc_record.id IS NULL
        )::integer,

        count(*) FILTER (
            WHERE
                kyc_record.kyc_status::text =
                    'verified'
        )::integer,

        count(*) FILTER (
            WHERE
                kyc_record.kyc_status::text =
                    'rejected'
        )::integer,

        count(*) FILTER (
            WHERE
                kyc_record.id IS NOT NULL

                AND
                kyc_record.kyc_status::text
                    NOT IN (
                        'verified',
                        'rejected'
                    )
        )::integer

    INTO
        v_total_users,
        v_started,
        v_not_started,
        v_verified,
        v_rejected,
        v_pending_review

    FROM
        public.users user_record

    INNER JOIN
        public.user_role role_record
        ON role_record.id =
           user_record.role_id

    LEFT JOIN
        public.user_kyc kyc_record
        ON kyc_record.user_id =
           user_record.id
       AND kyc_record.is_current =
           true

    WHERE
        lower(
            btrim(
                role_record.name::text
            )
        ) IN (
            'customer',
            'agent',
            'vendor',
            'merchant'
        );


    -- ========================================================
    -- GLOBAL STATISTICS BY ROLE
    --
    -- Build all four supported KYC roles even when one of the
    -- roles currently has zero users.
    -- ========================================================

    SELECT
        COALESCE(
            jsonb_object_agg(
                role_statistics.role_name,
                jsonb_build_object(

                    'total_users',
                        role_statistics.total_users,

                    'started',
                        role_statistics.started,

                    'not_started',
                        role_statistics.not_started,

                    'verified',
                        role_statistics.verified,

                    'rejected',
                        role_statistics.rejected,

                    'pending_review',
                        role_statistics.pending_review
                )
                ORDER BY
                    role_statistics.role_name
            ),
            '{}'::jsonb
        )

    INTO
        v_role_counts

    FROM (

        SELECT

            lower(
                btrim(
                    role_record.name::text
                )
            )
                AS role_name,


            count(
                user_record.id
            )::integer
                AS total_users,


            count(
                kyc_record.id
            )::integer
                AS started,


            count(
                user_record.id
            ) FILTER (
                WHERE
                    kyc_record.id IS NULL
            )::integer
                AS not_started,


            count(
                user_record.id
            ) FILTER (
                WHERE
                    kyc_record.kyc_status::text =
                        'verified'
            )::integer
                AS verified,


            count(
                user_record.id
            ) FILTER (
                WHERE
                    kyc_record.kyc_status::text =
                        'rejected'
            )::integer
                AS rejected,


            count(
                user_record.id
            ) FILTER (
                WHERE
                    kyc_record.id IS NOT NULL

                    AND
                    kyc_record.kyc_status::text
                        NOT IN (
                            'verified',
                            'rejected'
                        )
            )::integer
                AS pending_review


        FROM
            public.user_role role_record


        LEFT JOIN
            public.users user_record
            ON user_record.role_id =
               role_record.id


        LEFT JOIN
            public.user_kyc kyc_record
            ON kyc_record.user_id =
               user_record.id
           AND kyc_record.is_current =
               true


        WHERE
            lower(
                btrim(
                    role_record.name::text
                )
            ) IN (
                'customer',
                'agent',
                'vendor',
                'merchant'
            )


        GROUP BY
            lower(
                btrim(
                    role_record.name::text
                )
            )

    ) role_statistics;


    -- ========================================================
    -- PER-COUNTRY STATISTICS
    --
    -- Use operational_country so the response contains the
    -- country name as well as country code.
    --
    -- Only countries containing at least one KYC-relevant user
    -- are included.
    -- ========================================================

    FOR v_country IN

        SELECT
            lower(
                btrim(
                    country_record.country_code
                )
            )
                AS country_code,

            country_record.name
                AS country_name

        FROM
            public.operational_country
                country_record

        WHERE EXISTS (

            SELECT 1

            FROM
                public.users user_record

            INNER JOIN
                public.user_role role_record
                ON role_record.id =
                   user_record.role_id

            WHERE
                lower(
                    btrim(
                        user_record.country_code
                    )
                ) =
                    lower(
                        btrim(
                            country_record.country_code
                        )
                    )

                AND
                lower(
                    btrim(
                        role_record.name::text
                    )
                ) IN (
                    'customer',
                    'agent',
                    'vendor',
                    'merchant'
                )
        )

        ORDER BY
            country_record.name,
            country_record.country_code

    LOOP

        -- ====================================================
        -- COUNTRY TOTALS
        -- ====================================================

        SELECT

            count(*)::integer,

            count(
                kyc_record.id
            )::integer,

            count(*) FILTER (
                WHERE
                    kyc_record.id IS NULL
            )::integer,

            count(*) FILTER (
                WHERE
                    kyc_record.kyc_status::text =
                        'verified'
            )::integer,

            count(*) FILTER (
                WHERE
                    kyc_record.kyc_status::text =
                        'rejected'
            )::integer,

            count(*) FILTER (
                WHERE
                    kyc_record.id IS NOT NULL

                    AND
                    kyc_record.kyc_status::text
                        NOT IN (
                            'verified',
                            'rejected'
                        )
            )::integer

        INTO
            v_country_total_users,
            v_country_started,
            v_country_not_started,
            v_country_verified,
            v_country_rejected,
            v_country_pending_review

        FROM
            public.users user_record

        INNER JOIN
            public.user_role role_record
            ON role_record.id =
               user_record.role_id

        LEFT JOIN
            public.user_kyc kyc_record
            ON kyc_record.user_id =
               user_record.id
           AND kyc_record.is_current =
               true

        WHERE
            lower(
                btrim(
                    user_record.country_code
                )
            ) =
                v_country.country_code

            AND
            lower(
                btrim(
                    role_record.name::text
                )
            ) IN (
                'customer',
                'agent',
                'vendor',
                'merchant'
            );


        -- ====================================================
        -- COUNTRY STATISTICS BY ROLE
        --
        -- All four roles are returned even when a country has
        -- zero users for a particular role.
        -- ====================================================

        SELECT
            COALESCE(
                jsonb_object_agg(
                    role_statistics.role_name,
                    jsonb_build_object(

                        'total_users',
                            role_statistics.total_users,

                        'started',
                            role_statistics.started,

                        'not_started',
                            role_statistics.not_started,

                        'verified',
                            role_statistics.verified,

                        'rejected',
                            role_statistics.rejected,

                        'pending_review',
                            role_statistics.pending_review
                    )
                    ORDER BY
                        role_statistics.role_name
                ),
                '{}'::jsonb
            )

        INTO
            v_country_role_counts

        FROM (

            SELECT

                lower(
                    btrim(
                        role_record.name::text
                    )
                )
                    AS role_name,


                count(
                    user_record.id
                )::integer
                    AS total_users,


                count(
                    kyc_record.id
                )::integer
                    AS started,


                count(
                    user_record.id
                ) FILTER (
                    WHERE
                        kyc_record.id IS NULL
                )::integer
                    AS not_started,


                count(
                    user_record.id
                ) FILTER (
                    WHERE
                        kyc_record.kyc_status::text =
                            'verified'
                )::integer
                    AS verified,


                count(
                    user_record.id
                ) FILTER (
                    WHERE
                        kyc_record.kyc_status::text =
                            'rejected'
                )::integer
                    AS rejected,


                count(
                    user_record.id
                ) FILTER (
                    WHERE
                        kyc_record.id IS NOT NULL

                        AND
                        kyc_record.kyc_status::text
                            NOT IN (
                                'verified',
                                'rejected'
                            )
                )::integer
                    AS pending_review


            FROM
                public.user_role role_record


            LEFT JOIN
                public.users user_record
                ON user_record.role_id =
                   role_record.id

               AND lower(
                       btrim(
                           user_record.country_code
                       )
                   ) =
                       v_country.country_code


            LEFT JOIN
                public.user_kyc kyc_record
                ON kyc_record.user_id =
                   user_record.id
               AND kyc_record.is_current =
                   true


            WHERE
                lower(
                    btrim(
                        role_record.name::text
                    )
                ) IN (
                    'customer',
                    'agent',
                    'vendor',
                    'merchant'
                )


            GROUP BY
                lower(
                    btrim(
                        role_record.name::text
                    )
                )

        ) role_statistics;


        -- ====================================================
        -- ADD COUNTRY
        -- ====================================================

        v_countries :=
            v_countries ||
            jsonb_build_array(
                jsonb_build_object(

                    'country_code',
                        v_country.country_code,

                    'country_name',
                        v_country.country_name,

                    'total_users',
                        v_country_total_users,

                    'started',
                        v_country_started,

                    'not_started',
                        v_country_not_started,

                    'verified',
                        v_country_verified,

                    'rejected',
                        v_country_rejected,

                    'pending_review',
                        v_country_pending_review,

                    'role_counts',
                        v_country_role_counts
                )
            );

    END LOOP;


    -- ========================================================
    -- RESPONSE
    -- ========================================================

    RETURN jsonb_build_object(

        'summary',
            jsonb_build_object(

                'total_users',
                    v_total_users,

                'started',
                    v_started,

                'not_started',
                    v_not_started,

                'verified',
                    v_verified,

                'rejected',
                    v_rejected,

                'pending_review',
                    v_pending_review,

                'role_counts',
                    v_role_counts
            ),


        'countries',
            v_countries
    );

END;
$function$;


-- ============================================================
-- PERMISSIONS
-- ============================================================

REVOKE ALL
ON FUNCTION public.build_my_compliance_dashboard()
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.build_my_compliance_dashboard()
TO authenticated;