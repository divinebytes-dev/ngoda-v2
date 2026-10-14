drop function if exists public.execute_my_gold_inventory_purchase(
    public."TransactionType",
    numeric,
    numeric,
    numeric,
    text,
    text,
    text,
    text,
    text,
    text,
    text
);

notify pgrst, 'reload schema';