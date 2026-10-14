begin;

/*
 * The main posting function executes with the
 * privileges of the postgres function owner.
 */
alter function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
security definer;

alter function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
owner to postgres;


/*
 * Ensure the financial posting helper functions are
 * owned by postgres.
 *
 * The loop handles their existing parameter signatures
 * without requiring them to be repeated here.
 */
do $block$
declare
    v_function record;
begin
    for v_function in
        select
            procedure_record.oid::regprocedure
                as function_signature
        from pg_catalog.pg_proc procedure_record
        join pg_catalog.pg_namespace schema_record
          on schema_record.oid =
             procedure_record.pronamespace
        where schema_record.nspname = 'public'
          and procedure_record.proname in (
              'post_financial_entries',
              'update_gl_balance_snapshot',
              'apply_gl_snapshot_update',
              'post_wallet_entries',
              'update_wallet_balance_snapshot',
              'apply_wallet_snapshot_update',
              'generate_document_number'
          )
    loop
        execute format(
            'alter function %s owner to postgres',
            v_function.function_signature
        );
    end loop;
end;
$block$;


/*
 * Only the service-role client inside the Edge Function
 * may start the privileged cash-transfer posting.
 */
revoke execute on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to service_role;

commit;