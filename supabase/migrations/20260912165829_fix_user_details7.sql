CREATE OR REPLACE FUNCTION public.upsert_my_user_basic_profile(
    p_first_name text DEFAULT NULL,
    p_middle_name text DEFAULT NULL,
    p_surname text DEFAULT NULL,
    p_dob date DEFAULT NULL,
    p_gender text DEFAULT NULL,
    p_nationality text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;
    v_gender text;
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
    -- DATE OF BIRTH VALIDATION
    -- ========================================================

    IF p_dob IS NOT NULL
       AND p_dob > CURRENT_DATE
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_DATE_OF_BIRTH';
    END IF;


    -- ========================================================
    -- GENDER
    --
    -- Flutter uses camelCase enum names while the backend may
    -- receive snake_case values.
    --
    -- Accept:
    --
    -- male
    -- female
    -- other
    -- preferNotToSay
    -- prefer_not_to_say
    --
    -- Store one consistent backend value:
    --
    -- prefer_not_to_say
    -- ========================================================

    IF p_gender IS NULL
       OR btrim(p_gender) = ''
    THEN
        v_gender := NULL;

    ELSE

        CASE regexp_replace(
            lower(btrim(p_gender)),
            '[_\-\s]',
            '',
            'g'
        )

            WHEN 'male' THEN
                v_gender := 'male';

            WHEN 'female' THEN
                v_gender := 'female';

            WHEN 'other' THEN
                v_gender := 'other';

            WHEN 'prefernottosay' THEN
                v_gender := 'prefer_not_to_say';

            ELSE
                RAISE EXCEPTION USING
                    ERRCODE = '22023',
                    MESSAGE = 'INVALID_GENDER';

        END CASE;

    END IF;


    -- ========================================================
    -- UPDATE CURRENT USER
    --
    -- The users row already exists when the account is created,
    -- therefore this screen updates that existing row.
    -- ========================================================

    UPDATE public.users user_record
    SET
        first_name =
            NULLIF(
                btrim(p_first_name),
                ''
            ),

        middle_name =
            NULLIF(
                btrim(p_middle_name),
                ''
            ),

        surname =
            NULLIF(
                btrim(p_surname),
                ''
            ),

        dob =
            p_dob::timestamp without time zone,

        gender =
            v_gender,

        nationality =
            NULLIF(
                btrim(p_nationality),
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
    -- RETURN
    --
    -- Return the same names expected by UserBasicProfile.
    -- ========================================================

    RETURN jsonb_build_object(
        'user_id',
            v_user.id,

        'basic_profile',
            jsonb_build_object(
                'first_name',
                    v_user.first_name,

                'middle_name',
                    v_user.middle_name,

                'surname',
                    v_user.surname,

                'dob',
                    v_user.dob,

                'gender',
                    v_user.gender,

                'nationality',
                    v_user.nationality
            )
    );

END;
$function$;

REVOKE ALL
ON FUNCTION public.upsert_my_user_basic_profile(
    text,
    text,
    text,
    date,
    text,
    text
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.upsert_my_user_basic_profile(
    text,
    text,
    text,
    date,
    text,
    text
)
TO authenticated;