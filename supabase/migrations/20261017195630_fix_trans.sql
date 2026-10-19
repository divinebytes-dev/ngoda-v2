BEGIN;

REVOKE ALL ON FUNCTION public.fetch_device_tokens(
    text,
    text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fetch_device_tokens(
    text,
    text
)
TO service_role;

COMMIT;