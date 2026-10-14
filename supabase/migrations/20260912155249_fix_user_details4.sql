CREATE OR REPLACE FUNCTION public.fetch_my_user_details()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$

DECLARE

    v_user public.users%rowtype;

    v_country_name text;

    v_kyc public.user_kyc%rowtype;

    v_id_front jsonb;

    v_id_back jsonb;

    v_proof_of_address jsonb;

    v_selfie jsonb;

    v_verification_status text;

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
    -- USER
    -- ========================================================

    SELECT user_record.*
    INTO v_user
    FROM public.users user_record

    WHERE user_record.id =
          auth.uid()::text

      AND user_record.status =
          'active'::public."UserStatus"

    LIMIT 1;


    IF NOT FOUND THEN

        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'USER_NOT_AUTHORIZED';

    END IF;


    -- ========================================================
    -- COUNTRY
    -- ========================================================

    SELECT country_record.name
    INTO v_country_name

    FROM public.operational_country country_record

    WHERE lower(
        country_record.country_code
    ) = lower(
        v_user.country_code
    )

    LIMIT 1;


    -- ========================================================
    -- CURRENT KYC PROFILE
    -- ========================================================

    SELECT kyc_record.*
    INTO v_kyc

    FROM public.user_kyc kyc_record

    WHERE kyc_record.user_id =
          v_user.id

      AND kyc_record.is_current =
          true

    ORDER BY
        kyc_record.updated_at DESC NULLS LAST,
        kyc_record.created_at DESC NULLS LAST

    LIMIT 1;


    -- ========================================================
    -- ID FRONT
    -- ========================================================

    SELECT jsonb_build_object(

        'id',
            document_record.id,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at

    )
    INTO v_id_front

    FROM public.user_verification_document
         document_record

    WHERE document_record.user_id =
          v_user.id

      AND document_record.document_type =
          'id_front'::public."VerificationDocumentType"

    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC,
        document_record.id DESC

    LIMIT 1;


    -- ========================================================
    -- ID BACK
    -- ========================================================

    SELECT jsonb_build_object(

        'id',
            document_record.id,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at

    )
    INTO v_id_back

    FROM public.user_verification_document
         document_record

    WHERE document_record.user_id =
          v_user.id

      AND document_record.document_type =
          'id_back'::public."VerificationDocumentType"

    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC,
        document_record.id DESC

    LIMIT 1;


    -- ========================================================
    -- PROOF OF ADDRESS
    -- ========================================================

    SELECT jsonb_build_object(

        'id',
            document_record.id,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at

    )
    INTO v_proof_of_address

    FROM public.user_verification_document
         document_record

    WHERE document_record.user_id =
          v_user.id

      AND document_record.document_type =
          'proof_of_address'::public."VerificationDocumentType"

    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC,
        document_record.id DESC

    LIMIT 1;


    -- ========================================================
    -- SELFIE
    -- ========================================================

    SELECT jsonb_build_object(

        'id',
            document_record.id,

        'url',
            document_record.url,

        'file_name',
            document_record.file_name,

        'status',
            document_record.status::text,

        'uploaded_at',
            document_record.uploaded_at,

        'verified_at',
            document_record.verified_at

    )
    INTO v_selfie

    FROM public.user_verification_document
         document_record

    WHERE document_record.user_id =
          v_user.id

      AND document_record.document_type =
          'selfie'::public."VerificationDocumentType"

    ORDER BY
        document_record.uploaded_at DESC,
        document_record.created_at DESC,
        document_record.id DESC

    LIMIT 1;


    -- ========================================================
    -- OVERALL VERIFICATION STATUS
    --
    -- For now the KYC profile verification status remains the
    -- source of truth.
    -- ========================================================

    IF v_kyc.id IS NOT NULL THEN

        v_verification_status :=
            v_kyc.verification_status::text;

    ELSE

        v_verification_status := NULL;

    END IF;


    -- ========================================================
    -- RETURN
    -- ========================================================

    RETURN jsonb_build_object(

        'user_id',
            v_user.id,


        -- ====================================================
        -- BASIC PROFILE
        -- ====================================================

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

            ),


        -- ====================================================
        -- CONTACT DETAILS
        -- ====================================================

        'contact_details',

            jsonb_build_object(

                'email',
                    v_user.email,

                'phone',
                    v_user.phone,

                'country_code',
                    lower(
                        v_user.country_code
                    ),

                'country_name',
                    v_country_name,

                'residential_address',
                    COALESCE(
                        v_user.residential_address,
                        v_user.address
                    ),

                'city',
                    v_user.city,

                'province_state',
                    v_user.province_state

            ),


        -- ====================================================
        -- KYC DETAILS
        -- ====================================================

        'kyc_details',

            jsonb_build_object(

                'id_type',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.id_type::text
                    END,


                'id_number',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.id_number
                    END,


                'expiry_date',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.expiry_date
                    END,


                'occupation',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.occupation
                    END,


                'source_of_funds',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.source_of_funds
                    END,


                'tax_number',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.tax_number
                    END,


                'kyc_status',

                    CASE
                        WHEN v_kyc.id IS NULL
                        THEN NULL

                        ELSE
                            v_kyc.verification_status::text
                    END

            ),


        -- ====================================================
        -- VERIFICATION DOCUMENTS
        -- ====================================================

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
                    v_verification_status

            )

    );

END;
$function$;


REVOKE ALL
ON FUNCTION public.fetch_my_user_details()
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.fetch_my_user_details()
TO authenticated;