-- ============================================================
-- USER PROFILE / KYC / VERIFICATION DOCUMENT SCHEMA
-- ============================================================


-- ============================================================
-- 1. USERS
--
-- Add fields required by:
--
-- UserBasicProfile
-- UserContactDetails
--
-- Existing fields such as:
-- first_name
-- middle_name
-- surname
-- dob
-- nationality
-- email
-- phone
-- country_code
--
-- remain unchanged.
-- ============================================================

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS gender text NULL;

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS residential_address text NULL;

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS city text NULL;

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS province_state text NULL;


-- ============================================================
-- 2. USER KYC
--
-- The old fields have already been renamed:
--
-- document_type       -> id_type
-- document_number     -> id_number
-- verification_status -> kyc_status
--
-- Therefore we DO NOT rename or backfill anything here.
-- ============================================================

ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS expiry_date date NULL;

ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS occupation text NULL;

ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS source_of_funds text NULL;

ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS tax_number text NULL;

ALTER TABLE public.user_kyc
ADD COLUMN IF NOT EXISTS is_current boolean
NOT NULL DEFAULT true;


-- ============================================================
-- 3. CURRENT KYC INDEX
--
-- A user may have KYC history, but only one record may be
-- marked as current.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS
user_kyc_current_user_key
ON public.user_kyc (
    user_id
)
WHERE is_current = true;


CREATE INDEX IF NOT EXISTS
user_kyc_user_current_idx
ON public.user_kyc (
    user_id,
    is_current
);


-- ============================================================
-- 4. VERIFICATION DOCUMENT TYPE
-- ============================================================

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type type_record

        JOIN pg_namespace namespace_record
          ON namespace_record.oid =
             type_record.typnamespace

        WHERE type_record.typname =
              'VerificationDocumentType'

          AND namespace_record.nspname =
              'public'
    ) THEN

        CREATE TYPE public."VerificationDocumentType"
        AS ENUM (
            'id_front',
            'id_back',
            'proof_of_address',
            'selfie'
        );

    END IF;

END
$$;


-- ============================================================
-- 5. USER VERIFICATION DOCUMENT
-- ============================================================

CREATE TABLE IF NOT EXISTS
public.user_verification_document (

    id text NOT NULL
        DEFAULT gen_random_uuid()::text,

    user_id text NOT NULL,

    document_type
        public."VerificationDocumentType"
        NOT NULL,

    url text NOT NULL,

    file_name text NULL,

    status
        public."KycStatus"
        NOT NULL
        DEFAULT 'pending'::public."KycStatus",

    uploaded_at timestamptz NOT NULL
        DEFAULT now(),

    verified_by text NULL,

    verified_at timestamptz NULL,

    created_at timestamptz NOT NULL
        DEFAULT now(),

    updated_at timestamptz NOT NULL
        DEFAULT now(),

    updated_by text NULL,


    CONSTRAINT user_verification_document_pkey
        PRIMARY KEY (id),

    CONSTRAINT user_verification_document_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES public.users (id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
)
TABLESPACE pg_default;


-- ============================================================
-- 6. IMPORTANT
--
-- Because CREATE TABLE IF NOT EXISTS does not add missing
-- columns to an already-existing table, explicitly make sure
-- the expected columns exist.
--
-- This makes this script safe after the previous partial run.
-- ============================================================

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS user_id text;

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS document_type
public."VerificationDocumentType";

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS url text;

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS file_name text;

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS status
public."KycStatus";

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS uploaded_at timestamptz
DEFAULT now();

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS verified_by text;

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS verified_at timestamptz;

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS created_at timestamptz
DEFAULT now();

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS updated_at timestamptz
DEFAULT now();

ALTER TABLE public.user_verification_document
ADD COLUMN IF NOT EXISTS updated_by text;


-- ============================================================
-- 7. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS
user_verification_document_user_id_idx
ON public.user_verification_document (
    user_id
);


CREATE INDEX IF NOT EXISTS
user_verification_document_user_type_idx
ON public.user_verification_document (
    user_id,
    document_type
);


CREATE INDEX IF NOT EXISTS
user_verification_document_user_status_idx
ON public.user_verification_document (
    user_id,
    status
);


CREATE INDEX IF NOT EXISTS
user_verification_document_uploaded_at_idx
ON public.user_verification_document (
    user_id,
    uploaded_at DESC
);


-- ============================================================
-- 8. NO DELETE TRIGGER
-- ============================================================

DROP TRIGGER IF EXISTS
user_verification_document_no_delete
ON public.user_verification_document;


CREATE TRIGGER
user_verification_document_no_delete
BEFORE DELETE
ON public.user_verification_document
FOR EACH ROW
EXECUTE FUNCTION public.ngoda_prevent_delete();


-- ============================================================
-- 9. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.user_verification_document
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 10. COMMENTS
-- ============================================================

COMMENT ON TABLE
public.user_verification_document
IS
'Stores uploaded user KYC verification documents separately from the KYC profile.';


COMMENT ON COLUMN
public.user_kyc.is_current
IS
'Identifies the current KYC profile. Historical KYC records may remain in the table.';