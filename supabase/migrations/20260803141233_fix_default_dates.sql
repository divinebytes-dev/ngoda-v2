do $$
declare
    v_column record;
begin
    for v_column in
        select
            table_schema,
            table_name,
            column_name
        from information_schema.columns
        where table_schema = 'public'
          and column_name in (
              'created_at',
              'updated_at'
          )
          and is_nullable = 'NO'
          and column_default is null
    loop
        execute format(
            'alter table %I.%I alter column %I set default now()',
            v_column.table_schema,
            v_column.table_name,
            v_column.column_name
        );
    end loop;
end;
$$;