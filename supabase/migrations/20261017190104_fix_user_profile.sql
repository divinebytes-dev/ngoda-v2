BEGIN;

REVOKE ALL ON FUNCTION public.get_next_wallet_index()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_next_wallet_index()
TO service_role;


REVOKE ALL ON FUNCTION public.create_customer_profile(
    uuid,
    text,
    text,
    text,
    text,
    bigint,
    text,
    text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_customer_profile(
    uuid,
    text,
    text,
    text,
    text,
    bigint,
    text,
    text
)
TO service_role;

COMMIT;