drop function if exists
    public.fetch_my_recent_financial_transactions(
        date,
        date,
        text,
        integer,
        integer
    );

notify pgrst, 'reload schema';