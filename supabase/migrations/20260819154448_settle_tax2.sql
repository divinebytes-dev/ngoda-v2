REVOKE ALL ON FUNCTION
    public.create_my_government_tax_settlement_batch(
        text,
        date,
        date
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.create_my_government_tax_settlement_batch(
        text,
        date,
        date
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.create_my_government_tax_settlement_batch(
        text,
        date,
        date
    )
TO authenticated;

NOTIFY pgrst, 'reload schema';