create or replace function public.fetch_gl_mappings(
    p_transaction_type public."TransactionType"
)
returns setof public.transaction_gl_mapping
language plpgsql
stable
as $$
begin
    /*
     * At least one active mapping must exist.
     */
    if not exists (
        select 1
        from public.transaction_gl_mapping m
        where m.transaction_type = p_transaction_type
          and m.is_active = true
    ) then
        raise exception
            'GL_MAPPING_NOT_FOUND_%',
            p_transaction_type;
    end if;

    /*
     * Every transaction must have an active principal mapping.
     */
    if not exists (
        select 1
        from public.transaction_gl_mapping m
        where m.transaction_type = p_transaction_type
          and m.component_type = 'principal'
          and m.is_active = true
    ) then
        raise exception
            'PRINCIPAL_GL_MAPPING_NOT_FOUND_%',
            p_transaction_type;
    end if;

    return query
    select m.*
    from public.transaction_gl_mapping m
    where m.transaction_type = p_transaction_type
      and m.is_active = true
    order by m.component_type asc;
end;
$$;