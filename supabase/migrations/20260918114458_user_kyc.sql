CREATE OR REPLACE FUNCTION public.fetch_user_kyc_review(
    p_user_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_requested_user_id text;
    v_reviewer_id text;

    v_user
        public.users%rowtype;

    v_kyc
        public.user_kyc%rowtype;

    v_country_name text;

    v_id_front jsonb;
    v_id_back jsonb;
    v_proof_of_address jsonb;
    v_selfie jsonb;

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
    --  Compliance review must not be available to an ordinary
    --  authenticated customer.
    --  ========================================================

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

    v_requested_user_id :=
        NULLIF(
            btrim(p_user_id),
            ''
        );


    IF v_requested_user_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'USER_ID_MISSING';
    END IF;


    -- ========================================================
    -- CUSTOMER
    -- ========================================================

    SELECT user_record.*
    INTO v_user
    FROM public.users user_record
    WHERE user_record.id =
          v_requested_user_id
    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0002',
            MESSAGE = 'USER_NOT_FOUND';
    END IF;


    -- ========================================================
    -- COUNTRY
    -- ========================================================

    SELECT country_record.name
    INTO v_country_name
    FROM public.operational_country country_record
    WHERE country_record.country_code =
          v_user.country_code
    LIMIT 1;


    -- ========================================================
    -- CURRENT KYC
    -- 
    --  user_kyc keeps history.
    -- 
    --  Compliance reviews only the current submission.
    -- ========================================================

    SELECT kyc_record.*
    INTO v_kyc
    FROM public.user_kyc kyc_record
    WHERE kyc_record.user_id =
          v_requested_user_id
      AND kyc_record.is_current =
          true
    ORDER BY
        kyc_record.created_at DESC
    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0002',
            MESSAGE = 'KYC_NOT_FOUND';
    END IF;


    -- ========================================================
    -- ID FRONT
    -- 
    -- Verification documents also retain history.
    -- 
    -- Pull the latest document of each type.
    -- ========================================================

    SELECT jsonb_build_object(
        'id',
            document_record.id,

        'document_type',
            document_record.document_type::text,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at,

        'verified_by',
            document_record.verified_by
    )
    INTO v_id_front
    FROM public.user_verification_document document_record
    WHERE document_record.user_id =
          v_requested_user_id
      AND document_record.document_type =
          'id_front'::public."VerificationDocumentType"
    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC
    LIMIT 1;


    -- ========================================================
    -- ID BACK
    -- ========================================================

    SELECT jsonb_build_object(
        'id',
            document_record.id,

        'document_type',
            document_record.document_type::text,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at,

        'verified_by',
            document_record.verified_by
    )
    INTO v_id_back
    FROM public.user_verification_document document_record
    WHERE document_record.user_id =
          v_requested_user_id
      AND document_record.document_type =
          'id_back'::public."VerificationDocumentType"
    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC
    LIMIT 1;


    -- ========================================================
    -- PROOF OF ADDRESS
    -- ========================================================

    SELECT jsonb_build_object(
        'id',
            document_record.id,

        'document_type',
            document_record.document_type::text,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at,

        'verified_by',
            document_record.verified_by
    )
    INTO v_proof_of_address
    FROM public.user_verification_document document_record
    WHERE document_record.user_id =
          v_requested_user_id
      AND document_record.document_type =
          'proof_of_address'::public."VerificationDocumentType"
    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC
    LIMIT 1;


    -- ========================================================
    -- SELFIE
    -- ========================================================

    SELECT jsonb_build_object(
        'id',
            document_record.id,

        'document_type',
            document_record.document_type::text,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at,

        'verified_by',
            document_record.verified_by
    )
    INTO v_selfie
    FROM public.user_verification_document document_record
    WHERE document_record.user_id =
          v_requested_user_id
      AND document_record.document_type =
          'selfie'::public."VerificationDocumentType"
    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC
    LIMIT 1;


    -- ========================================================
    -- RESPONSE
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
        ),


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
        ),


        'kyc_details',
        jsonb_build_object(
            'id',
                v_kyc.id,

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
                v_kyc.kyc_status::text,

            'created_at',
                v_kyc.created_at,

            'updated_at',
                v_kyc.updated_at,

            'verified_at',
                v_kyc.verified_at,

            'verified_by',
                v_kyc.verified_by
        ),


        'verification_documents',
        jsonb_build_object(
            'id_front',
                v_id_front,

            'id_back',
                v_id_back,

            'proof_of_address',
                v_proof_of_address,

            'selfie',
                v_selfie,

            'verification_status',
                v_kyc.kyc_status::text
        )

    );

END;
$function$;


REVOKE ALL
ON FUNCTION public.fetch_user_kyc_review(text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_user_kyc_review(text)
TO authenticated;