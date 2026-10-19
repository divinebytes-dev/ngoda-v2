BEGIN;

REVOKE ALL ON FUNCTION public.cash_withdrawal(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.cash_withdrawal(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
TO service_role;

COMMIT;