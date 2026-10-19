BEGIN;

ALTER FUNCTION public.ngoda_validate_document_balance()
    OWNER TO postgres;

ALTER FUNCTION public.ngoda_validate_document_balance()
    SECURITY DEFINER;

ALTER FUNCTION public.ngoda_validate_document_balance()
    SET search_path TO '';

REVOKE ALL
ON FUNCTION public.ngoda_validate_document_balance()
FROM PUBLIC, anon, authenticated, service_role;

COMMIT;