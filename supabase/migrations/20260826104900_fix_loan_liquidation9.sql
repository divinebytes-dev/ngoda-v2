/*
 * Private manual-review reconciliation context.
 *
 * Run this file after 06-manual-review-reporting-rpcs.sql.
 */

create or replace function public.fetch_liquidation_reconciliation_context(
    p_job_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_job_id text;
    v_result jsonb;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_job_id :=
        nullif(
            btrim(
                p_job_id
            ),
            ''
        );

    if v_job_id is null then
        raise exception
            'LIQUIDATION_JOB_ID_REQUIRED';
    end if;

    select jsonb_build_object(
        'queue_id',
        queue_record.id::text,

        'liquidation_job_id',
        job_record.id::text,

        'job_status',
        job_record.status::text,

        'queue_status',
        queue_record.status::text,

        'manual_review_required',
        queue_record.manual_review_required,

        'country_code',
        lower(
            btrim(
                job_record.country_code
            )
        ),

        'document_number',
        job_record.document_number,

        'sender_wallet_address',
        queue_record.sender_wallet_address,

        'receiver_wallet_address',
        coalesce(
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'to'
                ),
                ''
            ),
            queue_record.receiver_wallet_address
        ),

        'collateral',
        trim_scale(
            queue_record.collateral
        )::text,

        'tx_hash',
        queue_record.tx_hash,

        'signed_payload',
        queue_record.signed_payload
    )
    into v_result
    from public.liquidation_job
        job_record

    join public.liquidation_blockchain_queue
        queue_record
      on queue_record.liquidation_job_id =
         job_record.id::text

    where job_record.id::text =
          v_job_id

      and queue_record.manual_review_required = true;

    if v_result is null then
        raise exception
            'LIQUIDATION_RECONCILIATION_CONTEXT_NOT_FOUND';
    end if;

    return v_result;
end;
$function$;


revoke all on function public.fetch_liquidation_reconciliation_context(
    text
)
from public, anon, authenticated;

grant execute on function public.fetch_liquidation_reconciliation_context(
    text
)
to service_role;


/* Ask PostgREST to discover the new RPC immediately. */
notify pgrst, 'reload schema';


/*
 * Verification: this query must return exactly one row.
 */
select
    procedure_record.proname as function_name,
    pg_get_function_identity_arguments(
        procedure_record.oid
    ) as arguments,
    procedure_record.prosecdef as security_definer,
    procedure_record.proacl as acl
from pg_proc
    procedure_record
join pg_namespace
    namespace_record
  on namespace_record.oid =
     procedure_record.pronamespace
where namespace_record.nspname = 'public'
  and procedure_record.proname =
      'fetch_liquidation_reconciliation_context';
