-- Complete KYC correction. Apply as migration owner after user_kyc/users exist.
-- No user rows, statuses or documents are deleted. Public API signatures stay the same.
BEGIN;
LOCK TABLE public.user_kyc IN ACCESS EXCLUSIVE MODE;

-- The existing RPC accepts optional details and documents are managed in
-- user_verification_document. Do not invent a fake legacy document URL.
ALTER TABLE public.user_kyc
  ALTER COLUMN id_type DROP NOT NULL,
  ALTER COLUMN id_number DROP NOT NULL,
  ALTER COLUMN document_url DROP NOT NULL;

-- This index enforces exactly the intended maximum of ONE current version.
-- Old non-current records can coexist. Existing duplicate-current rows cause
-- failure; this migration does not silently choose or delete one.
CREATE UNIQUE INDEX IF NOT EXISTS user_kyc_current_user_key
  ON public.user_kyc(user_id) WHERE is_current = true;

-- Remove full user-only uniqueness whether it is a constraint or a plain index.
-- Uses catalog column identity, not assumptions about Prisma-generated names.
-- No CASCADE: an unexpected dependency fails and rolls back the migration.
DO $migration$
DECLARE r record; user_att smallint;
BEGIN
  SELECT attnum INTO STRICT user_att FROM pg_attribute
  WHERE attrelid='public.user_kyc'::regclass AND attname='user_id' AND NOT attisdropped;
  FOR r IN SELECT conname FROM pg_constraint
    WHERE conrelid='public.user_kyc'::regclass AND contype='u'
      AND conkey=ARRAY[user_att]::smallint[]
  LOOP
    EXECUTE format('ALTER TABLE public.user_kyc DROP CONSTRAINT %I',r.conname);
  END LOOP;
  FOR r IN SELECT ni.nspname,i.relname
    FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
    JOIN pg_namespace ni ON ni.oid=i.relnamespace
    WHERE x.indrelid='public.user_kyc'::regclass
      AND x.indisunique AND NOT x.indisprimary
      AND x.indpred IS NULL AND x.indexprs IS NULL AND x.indnkeyatts=1
      AND x.indkey[0]=user_att
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid=x.indexrelid)
  LOOP
    EXECUTE format('DROP INDEX %I.%I',r.nspname,r.relname);
  END LOOP;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.upsert_my_user_kyc_details(p_id_type text DEFAULT NULL::text, p_id_number text DEFAULT NULL::text, p_expiry_date date DEFAULT NULL::date, p_occupation text DEFAULT NULL::text, p_source_of_funds text DEFAULT NULL::text, p_tax_number text DEFAULT NULL::text)
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

    -- Lock a stable parent even when no KYC exists yet. Both submission
    -- and verification use this lock, then lock the current KYC row.
    PERFORM 1
    FROM public.users AS user_record
    WHERE user_record.id = v_user_id
      AND user_record.status = 'active'::public."UserStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
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

CREATE OR REPLACE FUNCTION public.verify_user_kyc(p_user_id text, p_decision text, p_comments text DEFAULT NULL::text)
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

    -- Same parent-before-KYC lock order as customer submission.
    PERFORM 1
    FROM public.users AS user_record
    WHERE user_record.id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN

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


    -- Optional customer drafts are permitted, but approval needs identity.
    IF v_decision = 'verified'::public."KycStatus"
       AND (v_kyc.id_type IS NULL
            OR nullif(btrim(v_kyc.id_number), '') IS NULL)
    THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'KYC_IDENTITY_DETAILS_REQUIRED';
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

        updated_at = now(),
        updated_by = v_reviewer_id
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

-- Both RPCs have explicit auth checks. Preserve backend execution too.
REVOKE ALL ON FUNCTION public.upsert_my_user_kyc_details(text,text,date,text,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.verify_user_kyc(text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.upsert_my_user_kyc_details(text,text,date,text,text,text)
  TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.verify_user_kyc(text,text,text)
  TO authenticated,service_role;
COMMIT;


-- READ ONLY: countryless fiscal-linked tables and their direct readers/writers.
SELECT jsonb_build_object(
 'columns', (SELECT jsonb_agg(jsonb_build_object(
   'table',table_name,'column',column_name,'type',udt_name,
   'nullable',is_nullable,'default',column_default) ORDER BY table_name,ordinal_position)
   FROM information_schema.columns WHERE table_schema='public'
   AND table_name IN ('spread_config','reserve_asset_adjustment_request','tokenised_asset_adjustment_request')),
 'functions', (SELECT jsonb_agg(jsonb_build_object(
   'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
   'definition',pg_get_functiondef(p.oid)) ORDER BY p.proname)
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prokind='f'
   AND p.prosrc ~* '(^|[^a-z0-9_])(spread_config|reserve_asset_adjustment_request|tokenised_asset_adjustment_request)([^a-z0-9_]|$)')
) AS countryless_fiscal_dependencies;


-- Read-only checks after migration.
SELECT indexname,indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename='user_kyc' ORDER BY indexname;
SELECT column_name,is_nullable FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_kyc'
  AND column_name IN ('id_type','id_number','document_url');
SELECT user_id,count(*) AS current_versions FROM public.user_kyc
WHERE is_current GROUP BY user_id HAVING count(*)>1;
-- Expected: no rows above. Historical rows are not an error.
SELECT user_id,count(*) AS versions,count(*) FILTER (WHERE is_current) AS current_versions
FROM public.user_kyc GROUP BY user_id HAVING count(*)>1;
