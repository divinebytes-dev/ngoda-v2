CREATE OR REPLACE FUNCTION public.fetch_kyc_review_queue(
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_page integer;
    v_page_size integer;
    v_offset integer;

    v_total_entries integer;
    v_total_pages integer;

    v_has_previous boolean;
    v_has_next boolean;

    v_data jsonb;

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
    -- Only compliance users can access the KYC review queue.
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
    -- PAGINATION
    -- ========================================================

    v_page :=
        COALESCE(
            p_page,
            1
        );


    v_page_size :=
        COALESCE(
            p_page_size,
            20
        );


    IF v_page < 1 THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_PAGE';
    END IF;


    IF (
        v_page_size < 1
        OR
        v_page_size > 100
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_PAGE_SIZE';
    END IF;


    v_offset :=
        (v_page - 1) *
        v_page_size;


    -- ========================================================
    -- TOTAL ENTRIES
    --
    -- Start from users.
    --
    -- Eligible roles:
    --
    -- customer
    -- agent
    -- vendor
    -- merchant
    --
    -- LEFT JOIN user_kyc because a newly registered user may
    -- not yet have started KYC.
    --
    -- Include:
    --
    --   no current KYC
    --   OR
    --   current KYC is not verified
    --
    -- Exclude:
    --
    --   current KYC = verified
    -- ========================================================

    SELECT
        count(*)
    INTO
        v_total_entries
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
        lower(role_record.name) IN (
            'customer',
            'agent',
            'vendor',
            'merchant'
        )

        AND (
            kyc_record.id IS NULL
            OR
            kyc_record.kyc_status <>
                'verified'::public."KycStatus"
        );


    -- ========================================================
    -- TOTAL PAGES
    -- ========================================================

    IF v_total_entries = 0 THEN

        v_total_pages :=
            0;

    ELSE

        v_total_pages :=
            CEIL(
                v_total_entries::numeric /
                v_page_size::numeric
            )::integer;

    END IF;


    -- ========================================================
    -- PREVIOUS / NEXT
    -- ========================================================

    v_has_previous :=
        v_page > 1;


    v_has_next :=
        v_page <
        v_total_pages;


    -- ========================================================
    -- PAGE DATA
    --
    -- Users with an existing KYC process are displayed first.
    --
    -- Users who have not started KYC follow afterwards.
    --
    -- Within an existing KYC queue, the oldest outstanding
    -- KYC is shown first.
    -- ========================================================

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(

                    'user_id',
                        queue_record.user_id,

                    'first_name',
                        queue_record.first_name,

                    'middle_name',
                        queue_record.middle_name,

                    'surname',
                        queue_record.surname,

                    'email',
                        queue_record.email,

                    'phone',
                        queue_record.phone,

                    'country_code',
                        queue_record.country_code,

                    'role_id',
                        queue_record.role_id,

                    'role',
                        queue_record.role,

                    'kyc_id',
                        queue_record.kyc_id,

                    'kyc_status',
                        queue_record.kyc_status,

                    'kyc_started_at',
                        queue_record.kyc_started_at,

                    'kyc_updated_at',
                        queue_record.kyc_updated_at
                )
                ORDER BY
                    queue_record.kyc_sort_order ASC,
                    queue_record.kyc_started_at ASC NULLS LAST,
                    queue_record.user_id ASC
            ),
            '[]'::jsonb
        )
    INTO
        v_data

    FROM (

        SELECT

            -- =================================================
            -- USER
            -- =================================================

            user_record.id
                AS user_id,

            user_record.first_name,

            user_record.middle_name,

            user_record.surname,

            user_record.email,

            user_record.phone,

            user_record.country_code,


            -- =================================================
            -- ROLE
            -- =================================================

            role_record.id
                AS role_id,

            role_record.name::text
                AS role,


            -- =================================================
            -- KYC
            --
            -- These values are NULL when the user has not yet
            -- started KYC.
            -- =================================================

            kyc_record.id
                AS kyc_id,

            kyc_record.kyc_status::text
                AS kyc_status,

            kyc_record.created_at
                AS kyc_started_at,

            kyc_record.updated_at
                AS kyc_updated_at,


            -- =================================================
            -- SORT
            --
            -- Existing KYC = 0
            -- Not started   = 1
            -- =================================================

            CASE
                WHEN kyc_record.id IS NOT NULL
                    THEN 0
                ELSE 1
            END
                AS kyc_sort_order


        FROM
            public.users user_record


        -- =====================================================
        -- ROLE
        --
        -- Every user has one role through users.role_id.
        -- =====================================================

        INNER JOIN
            public.user_role role_record
            ON role_record.id =
               user_record.role_id


        -- =====================================================
        -- CURRENT KYC
        --
        -- LEFT JOIN is deliberate.
        --
        -- A user exists before KYC starts.
        -- =====================================================

        LEFT JOIN
            public.user_kyc kyc_record
            ON kyc_record.user_id =
               user_record.id
           AND kyc_record.is_current =
               true


        -- =====================================================
        -- FILTER
        -- =====================================================

        WHERE
            lower(role_record.name) IN (
                'customer',
                'agent',
                'vendor',
                'merchant'
            )

            AND (
                kyc_record.id IS NULL
                OR
                kyc_record.kyc_status <>
                    'verified'::public."KycStatus"
            )


        -- =====================================================
        -- ORDER BEFORE PAGINATION
        -- =====================================================

        ORDER BY

            CASE
                WHEN kyc_record.id IS NOT NULL
                    THEN 0
                ELSE 1
            END ASC,

            kyc_record.created_at ASC
                NULLS LAST,

            user_record.id ASC


        -- =====================================================
        -- PAGINATION
        -- =====================================================

        LIMIT
            v_page_size

        OFFSET
            v_offset

    ) queue_record;


    -- ========================================================
    -- RESPONSE
    -- ========================================================

    RETURN jsonb_build_object(

        'page',
            v_page,

        'page_size',
            v_page_size,

        'total_entries',
            v_total_entries,

        'total_pages',
            v_total_pages,

        'has_previous',
            v_has_previous,

        'has_next',
            v_has_next,

        'data',
            v_data
    );

END;
$function$;


-- ============================================================
-- PERMISSIONS
-- ============================================================

REVOKE ALL
ON FUNCTION public.fetch_kyc_review_queue(
    integer,
    integer
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_kyc_review_queue(
    integer,
    integer
)
TO authenticated;