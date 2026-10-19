BEGIN;

REVOKE ALL ON FUNCTION public.record_financial_activity(
    text,
    text,
    text,
    text,
    text,
    public.financial_activity_type,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_financial_activity(
    text,
    text,
    text,
    text,
    text,
    public.financial_activity_type,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric,
    numeric
)
TO service_role;

COMMIT;