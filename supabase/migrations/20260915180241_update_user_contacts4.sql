CREATE OR REPLACE FUNCTION public.upsert_my_user_kyc_details(
    p_id_type text DEFAULT NULL::text,
    p_id_number text DEFAULT NULL::text,
    p_expiry_date date DEFAULT NULL::date,
    p_occupation text DEFAULT NULL::text,
    p_source_of_funds text DEFAULT NULL::text,
    p_tax_number text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;

    v_id_type public."KycDocumentType";

    v_id_number text;
    v_occupation text;
    v_source_of_funds text;
    v_tax_number text;

    v_kyc public.user_kyc%rowtype;

BEGIN

    -- ========================================================
    -- AUTHENTICATION
    -- ========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    v_user_id :=
        auth.uid()::text;


    -- ========================================================
    -- ACTIVE USER
    -- ========================================================

    IF NOT EXISTS (
        SELECT 1
        FROM public.users user_record
        WHERE user_record.id =
              v_user_id
          AND user_record.status =
              'active'::public."UserStatus"
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'USER_NOT_AUTHORIZED';
    END IF;


    -- ========================================================
    -- ID TYPE
    -- ========================================================

    IF p_id_type IS NULL
       OR btrim(p_id_type) = ''
    THEN
        v_id_type := NULL;

    ELSE

        BEGIN

            v_id_type :=
                lower(
                    btrim(p_id_type)
                )::public."KycDocumentType";

        EXCEPTION
            WHEN invalid_text_representation THEN

                RAISE EXCEPTION USING
                    ERRCODE = '22023',
                    MESSAGE = 'INVALID_ID_TYPE';

        END;

    END IF;


    -- ========================================================
    -- NORMALIZE VALUES
    -- ========================================================

    v_id_number :=
        NULLIF(
            btrim(p_id_number),
            ''
        );


    v_occupation :=
        NULLIF(
            btrim(p_occupation),
            ''
        );


    v_source_of_funds :=
        NULLIF(
            btrim(p_source_of_funds),
            ''
        );


    v_tax_number :=
        NULLIF(
            btrim(p_tax_number),
            ''
        );


    -- ========================================================
    -- EXPIRY DATE VALIDATION
    --
    -- If an expiry date is supplied it should not already
    -- have expired.
    -- ========================================================

    IF p_expiry_date IS NOT NULL
       AND p_expiry_date < CURRENT_DATE
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'ID_DOCUMENT_EXPIRED';
    END IF;


    -- ========================================================
    -- LOCK CURRENT KYC
    --
    -- Prevent two simultaneous saves from creating two
    -- current KYC records for the same user.
    -- ========================================================

    PERFORM kyc_record.id
    FROM public.user_kyc kyc_record
    WHERE kyc_record.user_id =
          v_user_id
      AND kyc_record.is_current =
          true
    FOR UPDATE;


    -- ========================================================
    -- CLOSE CURRENT KYC
    --
    -- We retain the previous KYC row for history.
    -- ========================================================

    UPDATE public.user_kyc kyc_record
    SET
        is_current =
            false,

        updated_at =
            now(),

        updated_by =
            v_user_id

    WHERE kyc_record.user_id =
          v_user_id

      AND kyc_record.is_current =
          true;


    -- ========================================================
    -- CREATE NEW CURRENT KYC
    --
    -- The user cannot control KYC status.
    --
    -- Any user-submitted KYC profile starts as pending.
    -- ========================================================

    INSERT INTO public.user_kyc (
        user_id,
        id_type,
        id_number,
        expiry_date,
        occupation,
        source_of_funds,
        tax_number,
        kyc_status,
        is_current,
        verified_by,
        verified_at,
        created_at,
        updated_at,
        updated_by
    )
    VALUES (
        v_user_id,
        v_id_type,
        v_id_number,
        p_expiry_date,
        v_occupation,
        v_source_of_funds,
        v_tax_number,
        'pending'::public."KycStatus",
        true,
        NULL,
        NULL,
        now(),
        now(),
        v_user_id
    )
    RETURNING *
    INTO v_kyc;


    -- ========================================================
    -- RETURN
    -- ========================================================

    RETURN jsonb_build_object(
        'user_id',
            v_user_id,

        'kyc_details',
            jsonb_build_object(

                'id_type',
                    v_kyc.id_type::text,

                'id_number',
                    v_kyc.id_number,

                'expiry_date',
                    v_kyc.expiry_date,

                'occupation',
                    v_kyc.occupation,

                'source_of_funds',
                    v_kyc.source_of_funds,

                'tax_number',
                    v_kyc.tax_number,

                'kyc_status',
                    v_kyc.kyc_status::text
            )
    );

END;
$function$;


-- ============================================================
-- PERMISSIONS
-- ============================================================

REVOKE ALL
ON FUNCTION public.upsert_my_user_kyc_details(
    text,
    text,
    date,
    text,
    text,
    text
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.upsert_my_user_kyc_details(
    text,
    text,
    date,
    text,
    text,
    text
)
TO authenticated;