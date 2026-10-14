CREATE OR REPLACE FUNCTION public.submit_my_verification_document(
    p_document_type text,
    p_url text,
    p_file_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_document_type public."VerificationDocumentType";
    v_url text;
    v_file_name text;

    v_document public.user_verification_document%rowtype;

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
    -- DOCUMENT TYPE
    -- ========================================================

    IF p_document_type IS NULL
       OR btrim(p_document_type) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'DOCUMENT_TYPE_MISSING';
    END IF;


    BEGIN

        v_document_type :=
            lower(
                btrim(p_document_type)
            )::public."VerificationDocumentType";

    EXCEPTION
        WHEN invalid_text_representation THEN

            RAISE EXCEPTION USING
                ERRCODE = '22023',
                MESSAGE = 'INVALID_DOCUMENT_TYPE';

    END;


    -- ========================================================
    -- DOCUMENT PATH
    -- ========================================================

    v_url :=
        NULLIF(
            btrim(p_url),
            ''
        );


    IF v_url IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'DOCUMENT_URL_MISSING';
    END IF;


    -- ========================================================
    -- FILE NAME
    -- ========================================================

    v_file_name :=
        NULLIF(
            btrim(p_file_name),
            ''
        );


    IF v_file_name IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'DOCUMENT_FILE_NAME_MISSING';
    END IF;


    -- ========================================================
    -- PATH OWNERSHIP
    --
    -- Documents belonging to the authenticated user must
    -- live underneath that user's storage folder.
    --
    -- Example:
    --
    -- <user-id>/id_front/<uuid>.jpg
    -- ========================================================

    IF v_url NOT LIKE
       v_user_id || '/%'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_DOCUMENT_PATH';
    END IF;


    -- ========================================================
    -- DOCUMENT TYPE PATH
    --
    -- Prevent a caller from claiming that an object uploaded
    -- under selfie is actually an id_front document.
    -- ========================================================

    IF v_url NOT LIKE
       v_user_id || '/' ||
       v_document_type::text ||
       '/%'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_DOCUMENT_TYPE_PATH';
    END IF;


    -- ========================================================
    -- INSERT DOCUMENT
    --
    -- Do not update/delete previous documents.
    -- They form the verification-document history.
    -- ========================================================

    INSERT INTO public.user_verification_document (
        user_id,
        document_type,
        url,
        file_name,
        status,
        uploaded_at,
        verified_by,
        verified_at,
        created_at,
        updated_at,
        updated_by
    )
    VALUES (
        v_user_id,
        v_document_type,
        v_url,
        v_file_name,
        'pending'::public."KycStatus",
        now(),
        NULL,
        NULL,
        now(),
        now(),
        v_user_id
    )
    RETURNING *
    INTO v_document;


    -- ========================================================
    -- RETURN
    -- ========================================================

    RETURN jsonb_build_object(
        'user_id',
            v_user_id,

        'document',
            jsonb_build_object(
                'id',
                    v_document.id,

                'document_type',
                    v_document.document_type::text,

                'url',
                    v_document.url,

                'file_name',
                    v_document.file_name,

                'status',
                    v_document.status::text,

                'uploaded_at',
                    v_document.uploaded_at,

                'verified_at',
                    v_document.verified_at
            )
    );

END;
$function$;


REVOKE ALL
ON FUNCTION public.submit_my_verification_document(
    text,
    text,
    text
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.submit_my_verification_document(
    text,
    text,
    text
)
TO authenticated;