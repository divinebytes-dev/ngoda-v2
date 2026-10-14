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
    -- NORMALIZE INPUT
    --
    -- Country codes in Ngoda are stored in lowercase.
    --
    -- Example:
    --
    -- ZW / Zw / zw
    --      -> zw
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
            lower(
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
    -- PHONE VALIDATION
    --
    -- The Edge Function converts the local phone number to
    -- E.164 using operational_country.calling_code before
    -- calling this function.
    --
    -- Example:
    --
    -- 0661874837
    --      -> +263661874837
    -- ========================================================

    IF v_phone IS NOT NULL
       AND v_phone !~ '^\+[1-9][0-9]{7,14}$'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_PHONE';
    END IF;


    -- ========================================================
    -- COUNTRY VALIDATION
    --
    -- users.country_code references
    -- operational_country.country_code.
    --
    -- Therefore we validate the exact lowercase country code
    -- before updating the user.
    -- ========================================================

    IF v_country_code IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'COUNTRY_CODE_MISSING';
    END IF;


    SELECT country_record.name
    INTO v_country_name
    FROM public.operational_country country_record
    WHERE country_record.country_code =
          v_country_code
      AND country_record.is_active =
          true
    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_COUNTRY';
    END IF;


    -- ========================================================
    -- EMAIL UNIQUENESS
    -- ========================================================

    IF v_email IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.users existing_user
            WHERE lower(existing_user.email) =
                  v_email
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
    -- UPDATE USER
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
    -- USER NOT FOUND / INACTIVE
    -- ========================================================

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'USER_NOT_AUTHORIZED';
    END IF;


    -- ========================================================
    -- RETURN
    --
    -- Matches UserContactDetails expected by Flutter.
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
                    v_user.country_code,

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


-- ============================================================
-- PERMISSIONS
-- ============================================================

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



CREATE OR REPLACE FUNCTION public.fetch_my_user_contact_context(
    p_country_code text
)
RETURNS TABLE(
    user_id text,
    current_email text,
    current_phone text,
    country_code text,
    country_name text,
    calling_code text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_country_code text;

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
    -- COUNTRY CODE
    --
    -- Ngoda stores country codes in lowercase.
    -- ========================================================

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'COUNTRY_CODE_MISSING';
    END IF;


    v_country_code :=
        lower(
            btrim(p_country_code)
        );


    -- ========================================================
    -- TRUSTED CONTACT CONTEXT
    --
    -- calling_code is fetched from operational_country.
    --
    -- The Edge Function uses this value to convert a local
    -- phone number to E.164.
    -- ========================================================

    RETURN QUERY
    SELECT
        user_record.id,

        user_record.email,

        user_record.phone,

        country_record.country_code,

        country_record.name,

        country_record.calling_code

    FROM public.users user_record

    JOIN public.operational_country country_record
      ON country_record.country_code =
         v_country_code

    WHERE user_record.id =
          auth.uid()::text

      AND user_record.status =
          'active'::public."UserStatus"

      AND country_record.is_active =
          true

    LIMIT 1;


    -- ========================================================
    -- CONTEXT NOT FOUND
    -- ========================================================

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'USER_CONTACT_CONTEXT_NOT_FOUND';
    END IF;

END;
$function$;


-- ============================================================
-- PERMISSIONS
-- ============================================================

REVOKE ALL
ON FUNCTION public.fetch_my_user_contact_context(text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_my_user_contact_context(text)
TO authenticated;