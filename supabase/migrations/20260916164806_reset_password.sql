CREATE OR REPLACE FUNCTION public.fetch_password_reset_context(
    p_identifier text
)
RETURNS TABLE(
    identifier_type text,
    email text,
    phone text,
    calling_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_identifier text;
BEGIN

    -- ========================================================
    -- IDENTIFIER
    -- ========================================================

    v_identifier :=
        NULLIF(
            btrim(p_identifier),
            ''
        );


    IF v_identifier IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'IDENTIFIER_MISSING';
    END IF;


    -- ========================================================
    -- EMAIL
    -- ========================================================

    IF position('@' IN v_identifier) > 0 THEN

        RETURN QUERY
        SELECT
            'email'::text,
            user_record.email,
            NULL::text,
            NULL::text
        FROM public.users user_record
        WHERE lower(user_record.email) =
              lower(v_identifier)
          AND user_record.status =
              'active'::public."UserStatus"
        LIMIT 1;


        RETURN;

    END IF;


    -- ========================================================
    -- PHONE
    --
    -- We return the user's stored phone together with the
    -- calling code for their country.
    --
    -- The Edge Function will normalize it to E.164.
    -- ========================================================

    RETURN QUERY
    SELECT
        'phone'::text,
        NULL::text,
        user_record.phone,
        country_record.calling_code
    FROM public.users user_record
    JOIN public.operational_country country_record
      ON country_record.country_code =
         user_record.country_code
    WHERE
        (
            user_record.phone =
                v_identifier

            OR

            regexp_replace(
                user_record.phone,
                '[^0-9]',
                '',
                'g'
            ) =
            regexp_replace(
                v_identifier,
                '[^0-9]',
                '',
                'g'
            )
        )
      AND user_record.status =
          'active'::public."UserStatus"
      AND country_record.is_active =
          true
    LIMIT 1;

END;
$function$;


REVOKE ALL
ON FUNCTION public.fetch_password_reset_context(text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_password_reset_context(text)
TO anon, authenticated;