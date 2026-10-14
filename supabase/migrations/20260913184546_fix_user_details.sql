CREATE OR REPLACE FUNCTION public.upsert_my_user_basic_profile(
    p_first_name text DEFAULT NULL::text,
    p_middle_name text DEFAULT NULL::text,
    p_surname text DEFAULT NULL::text,
    p_dob date DEFAULT NULL::date,
    p_gender text DEFAULT NULL::text,
    p_nationality text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_gender public."GenderType";
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
    -- Input is text because this comes from the API.
    -- It is normalized here and converted to GenderType.
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
                v_gender :=
                    'male'::public."GenderType";

            WHEN 'female' THEN
                v_gender :=
                    'female'::public."GenderType";

            WHEN 'other' THEN
                v_gender :=
                    'other'::public."GenderType";

            WHEN 'prefernottosay' THEN
                v_gender :=
                    'prefer_not_to_say'::public."GenderType";

            ELSE
                RAISE EXCEPTION USING
                    ERRCODE = '22023',
                    MESSAGE = 'INVALID_GENDER';

        END CASE;

    END IF;


    -- ========================================================
    -- UPDATE CURRENT USER
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
                    v_user.gender::text,

                'nationality',
                    v_user.nationality
            )
    );

END;
$function$;