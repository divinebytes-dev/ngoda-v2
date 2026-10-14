do $$
declare
    v_table record;
begin
    for v_table in
        select distinct
            kcu.table_schema,
            kcu.table_name,
            kcu.column_name
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_name = tc.constraint_name
         and kcu.constraint_schema = tc.constraint_schema
        join information_schema.columns c
          on c.table_schema = kcu.table_schema
         and c.table_name = kcu.table_name
         and c.column_name = kcu.column_name
        where tc.constraint_type = 'PRIMARY KEY'
          and kcu.table_schema = 'public'
          and kcu.column_name = 'id'
          and c.data_type in (
              'text',
              'character varying'
          )
          and c.column_default is null
          and kcu.table_name not in (
              '_prisma_migrations',
              'users'
          )
    loop
        execute format(
            'alter table %I.%I alter column %I set default gen_random_uuid()::text',
            v_table.table_schema,
            v_table.table_name,
            v_table.column_name
        );
    end loop;
end;
$$;