ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS verification_comments text;

CREATE OR REPLACE FUNCTION public.verify_user_kyc(
    p_user_id text,
    p_decision text,
    p_comments text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_reviewer_id text;
    v_comments text;

    v_decision public."KycStatus";

    v_kyc
        public.user_kyc%rowtype;

    v_document_count integer := 0;

BEGIN

    -- ========================================================
    -- AUTHENTICATION
    -- ========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    v_reviewer_id :=
        auth.uid()::text;


    -- ========================================================
    -- AUTHORIZATION
    --
    -- Only compliance can make the KYC decision.
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
    -- USER ID
    -- ========================================================

    v_user_id :=
        NULLIF(
            btrim(p_user_id),
            ''
        );


    IF v_user_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'USER_ID_MISSING';
    END IF;


    -- ========================================================
    -- COMMENTS
    -- ========================================================

    v_comments :=
        NULLIF(
            btrim(p_comments),
            ''
        );


    -- ========================================================
    -- DECISION
    -- ========================================================

    IF p_decision IS NULL
       OR btrim(p_decision) = '' THEN

        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'KYC_DECISION_MISSING';

    END IF;


    BEGIN

        v_decision :=
            lower(
                btrim(p_decision)
            )::public."KycStatus";

    EXCEPTION
        WHEN invalid_text_representation THEN

            RAISE EXCEPTION USING
                ERRCODE = '22023',
                MESSAGE = 'INVALID_KYC_DECISION';

    END;


    -- ========================================================
    -- ALLOWED COMPLIANCE DECISIONS
    --
    -- Compliance should not use this operation to put the KYC
    -- back into a submission/pending state.
    --
    -- Adjust these values if your KycStatus enum uses different
    -- names.
    -- ========================================================

    IF v_decision NOT IN (
        'verified'::public."KycStatus",
        'rejected'::public."KycStatus"
    ) THEN

        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'INVALID_KYC_DECISION';

    END IF;


    -- ========================================================
    -- REJECTION COMMENTS
    --
    -- If compliance rejects KYC, the customer needs to know
    -- what needs to be corrected.
    -- ========================================================

    IF v_decision =
           'rejected'::public."KycStatus"
       AND v_comments IS NULL THEN

        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'KYC_REJECTION_COMMENTS_REQUIRED';

    END IF;


    -- ========================================================
    -- USER
    -- ========================================================

    IF NOT EXISTS (
        SELECT 1
        FROM public.users user_record
        WHERE user_record.id =
              v_user_id
    ) THEN

        RAISE EXCEPTION USING
            ERRCODE = 'P0002',
            MESSAGE = 'USER_NOT_FOUND';

    END IF;


    -- ========================================================
    -- CURRENT KYC
    --
    -- Lock the current KYC record while compliance makes the
    -- decision.
    -- ========================================================

    SELECT kyc_record.*
    INTO v_kyc
    FROM public.user_kyc kyc_record
    WHERE kyc_record.user_id =
          v_user_id
      AND kyc_record.is_current =
          true
    ORDER BY
        kyc_record.created_at DESC
    LIMIT 1
    FOR UPDATE;


    IF NOT FOUND THEN

        RAISE EXCEPTION USING
            ERRCODE = 'P0002',
            MESSAGE = 'KYC_NOT_FOUND';

    END IF;


    -- ========================================================
    -- VERIFICATION DOCUMENTS
    --
    -- There must be at least one submitted verification
    -- document before compliance can make the overall
    -- verification decision.
    -- ========================================================

    SELECT count(*)
    INTO v_document_count
    FROM public.user_verification_document document_record
    WHERE document_record.user_id =
          v_user_id;


    IF v_document_count = 0 THEN

        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'KYC_DOCUMENTS_NOT_FOUND';

    END IF;


    -- ========================================================
    -- UPDATE KYC
    -- ========================================================

    UPDATE public.user_kyc
    SET
        kyc_status =
            v_decision,

        verification_comments =
            v_comments,

        verified_by =
            v_reviewer_id,

        verified_at =
            now(),

        updated_at =
            now()
    WHERE id =
          v_kyc.id;


    -- ========================================================
    -- UPDATE LATEST DOCUMENT OF EACH TYPE
    --
    -- user_verification_document retains historical uploads.
    --
    -- We therefore update only the latest document for each
    -- document type rather than modifying historical versions.
    -- ========================================================

    WITH latest_documents AS (
        SELECT DISTINCT ON (
            document_record.document_type
        )
            document_record.id
        FROM public.user_verification_document
            document_record
        WHERE document_record.user_id =
              v_user_id
        ORDER BY
            document_record.document_type,
            document_record.uploaded_at DESC,
            document_record.created_at DESC
    )
    UPDATE public.user_verification_document
        AS document_record
    SET
        status =
            v_decision,

        verified_by =
            v_reviewer_id,

        verified_at =
            now()
    WHERE document_record.id IN (
        SELECT latest_document.id
        FROM latest_documents
            latest_document
    );


    -- ========================================================
    -- RESPONSE
    -- ========================================================

    RETURN jsonb_build_object(
        'user_id',
            v_user_id,

        'kyc_id',
            v_kyc.id,

        'decision',
            v_decision::text,

        'comments',
            v_comments,

        'verified_by',
            v_reviewer_id,

        'verified_at',
            now()
    );

END;
$function$;


REVOKE ALL
ON FUNCTION public.verify_user_kyc(
    text,
    text,
    text
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.verify_user_kyc(
    text,
    text,
    text
)
TO authenticated;