BEGIN;

REVOKE ALL ON FUNCTION public.calculate_required_collateral(text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.calculate_required_collateral(text)
TO service_role;

COMMIT;