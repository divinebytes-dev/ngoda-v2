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
    -- BASIC VALIDATION
    -- ========================================================

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'COUNTRY_CODE_MISSING';
    END IF;


    v_country_code :=
        upper(
            btrim(p_country_code)
        );


    -- ========================================================
    -- TRUSTED CONTACT CONTEXT
    --
    -- calling_code comes from operational_country.
    -- Do not trust a calling code supplied by Flutter.
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
      ON upper(country_record.country_code) =
         v_country_code

    WHERE user_record.id =
          auth.uid()::text

      AND user_record.status =
          'active'::public."UserStatus"

      AND country_record.is_active =
          true

    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'USER_CONTACT_CONTEXT_NOT_FOUND';
    END IF;

END;
$function$;


REVOKE ALL
ON FUNCTION public.fetch_my_user_contact_context(text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_my_user_contact_context(text)
TO authenticated;