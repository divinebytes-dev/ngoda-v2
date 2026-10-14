CREATE OR REPLACE FUNCTION public.upsert_my_user_contact_details(
    p_email text DEFAULT NULL::text,
    p_phone text DEFAULT NULL::text,
    p_country_code text DEFAULT NULL::text,
    p_residential_address text DEFAULT NULL::text,
    p_city text DEFAULT NULL::text,
    p_province_state text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_email text;
    v_phone text;
    v_country_code text;
    v_country_name text;

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
    -- NORMALIZE VALUES
    -- ========================================================

    v_email :=
        NULLIF(
            lower(
                btrim(p_email)
            ),
            ''
        );

    v_phone :=
        NULLIF(
            btrim(p_phone),
            ''
        );

    v_country_code :=
        NULLIF(
            upper(
                btrim(p_country_code)
            ),
            ''
        );


    -- ========================================================
    -- EMAIL VALIDATION
    -- ========================================================

    IF v_email IS NOT NULL
       AND v_email !~*
           '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_EMAIL';
    END IF;


    -- ========================================================
    -- COUNTRY VALIDATION
    -- ========================================================

    IF v_country_code IS NOT NULL THEN

        SELECT country_record.name
        INTO v_country_name
        FROM public.operational_country country_record
        WHERE lower(country_record.country_code) =
              lower(v_country_code)
          AND country_record.is_active = true
        LIMIT 1;


        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                ERRCODE = '22023',
                MESSAGE = 'INVALID_COUNTRY';
        END IF;

    END IF;


    -- ========================================================
    -- EMAIL UNIQUENESS
    -- ========================================================

    IF v_email IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.users existing_user
            WHERE lower(existing_user.email) =
                  lower(v_email)
              AND existing_user.id <>
                  auth.uid()::text
       )
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '23505',
            MESSAGE = 'EMAIL_ALREADY_IN_USE';
    END IF;


    -- ========================================================
    -- PHONE UNIQUENESS
    -- ========================================================

    IF v_phone IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.users existing_user
            WHERE existing_user.phone =
                  v_phone
              AND existing_user.id <>
                  auth.uid()::text
       )
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '23505',
            MESSAGE = 'PHONE_ALREADY_IN_USE';
    END IF;


    -- ========================================================
    -- UPDATE USER CONTACT DETAILS
    -- ========================================================

    UPDATE public.users user_record
    SET
        email =
            v_email,

        phone =
            v_phone,

        country_code =
            v_country_code,

        residential_address =
            NULLIF(
                btrim(
                    p_residential_address
                ),
                ''
            ),

        city =
            NULLIF(
                btrim(p_city),
                ''
            ),

        province_state =
            NULLIF(
                btrim(p_province_state),
                ''
            ),

        updated_at =
            now()

    WHERE user_record.id =
          auth.uid()::text

      AND user_record.status =
          'active'::public."UserStatus"

    RETURNING user_record.*
    INTO v_user;


    -- ========================================================
    -- USER NOT FOUND / NOT ACTIVE
    -- ========================================================

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'USER_NOT_AUTHORIZED';
    END IF;


    -- ========================================================
    -- COUNTRY NAME
    --
    -- If country code is null there is naturally no country.
    -- ========================================================

    IF v_user.country_code IS NOT NULL THEN

        SELECT country_record.name
        INTO v_country_name
        FROM public.operational_country country_record
        WHERE lower(country_record.country_code) =
              lower(v_user.country_code)
        LIMIT 1;

    ELSE

        v_country_name := NULL;

    END IF;


    -- ========================================================
    -- RETURN
    -- ========================================================

    RETURN jsonb_build_object(
        'user_id',
            v_user.id,

        'contact_details',
            jsonb_build_object(
                'email',
                    v_user.email,

                'phone',
                    v_user.phone,

                'country_code',
                    lower(v_user.country_code),

                'country_name',
                    v_country_name,

                'residential_address',
                    v_user.residential_address,

                'city',
                    v_user.city,

                'province_state',
                    v_user.province_state
            )
    );

END;
$function$;


REVOKE ALL
ON FUNCTION public.upsert_my_user_contact_details(
    text,
    text,
    text,
    text,
    text,
    text
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.upsert_my_user_contact_details(
    text,
    text,
    text,
    text,
    text,
    text
)
TO authenticated;