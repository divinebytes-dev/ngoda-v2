-- ============================================================
-- DROP PREVIOUS FUNCTION
--
-- Required because the return structure changed.
-- ============================================================

DROP FUNCTION IF EXISTS
public.fetch_password_reset_context(text);


-- ============================================================
-- PASSWORD RESET CONTEXT
-- ============================================================

CREATE FUNCTION public.fetch_password_reset_context(
    p_identifier text
)
RETURNS TABLE(
    identifier_type text,
    email text,
    phone text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_identifier text;
    v_identifier_digits text;
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
    --
    -- Flutter determines email/phone using @, but we repeat
    -- that determination here because SQL must not trust the
    -- caller to supply an identifier type.
    -- ========================================================

    IF position('@' IN v_identifier) > 0 THEN

        RETURN QUERY
        SELECT
            'email'::text,
            lower(user_record.email),
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
    -- Strip everything except digits from what Flutter sent.
    --
    -- Examples:
    --
    -- 0661874837
    -- +263661874837
    -- 263661874837
    -- ========================================================

    v_identifier_digits :=
        regexp_replace(
            v_identifier,
            '[^0-9]',
            '',
            'g'
        );


    IF v_identifier_digits = '' THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_IDENTIFIER';
    END IF;


    -- ========================================================
    -- FIND PHONE
    --
    -- users.country_code
    --        ↓
    -- operational_country.country_code
    --        ↓
    -- operational_country.calling_code
    --
    -- This allows a local number such as:
    --
    -- 0661874837
    --
    -- to match a stored E.164 number:
    --
    -- +263661874837
    -- ========================================================

    RETURN QUERY
    SELECT
        'phone'::text,
        NULL::text,
        user_record.phone
    FROM public.users user_record

    JOIN public.operational_country country_record
      ON country_record.country_code =
         user_record.country_code
     AND country_record.is_active =
         true

    WHERE user_record.status =
          'active'::public."UserStatus"

      AND user_record.phone IS NOT NULL

      AND (

          -- ==================================================
          -- EXACT VALUE
          --
          -- Example:
          -- +263661874837 = +263661874837
          -- ==================================================

          user_record.phone =
              v_identifier


          OR


          -- ==================================================
          -- DIGITS ONLY
          --
          -- Example:
          -- +263661874837
          -- matches
          -- 263661874837
          -- ==================================================

          regexp_replace(
              user_record.phone,
              '[^0-9]',
              '',
              'g'
          )
          =
          v_identifier_digits


          OR


          -- ==================================================
          -- LOCAL NUMBER
          --
          -- calling_code = +263
          -- identifier   = 0661874837
          --
          -- becomes:
          --
          -- 263 || 661874837
          --
          -- = 263661874837
          -- ==================================================

          regexp_replace(
              user_record.phone,
              '[^0-9]',
              '',
              'g'
          )
          =
          (
              regexp_replace(
                  country_record.calling_code,
                  '[^0-9]',
                  '',
                  'g'
              )
              ||
              regexp_replace(
                  v_identifier_digits,
                  '^0+',
                  ''
              )
          )
      )

    LIMIT 1;

END;
$function$;


-- ============================================================
-- PERMISSIONS
--
-- Password reset occurs before authentication, therefore anon
-- must be allowed to execute this function.
-- ============================================================

REVOKE ALL
ON FUNCTION public.fetch_password_reset_context(text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_password_reset_context(text)
TO anon, authenticated;