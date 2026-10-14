/* Verify required enum values. */
select
    type_record.typname as enum_name,
    enum_record.enumlabel,
    enum_record.enumsortorder
from pg_type type_record
join pg_enum enum_record
  on enum_record.enumtypid = type_record.oid
where type_record.typname in (
    'BlockchainLiquidationStatus',
    'LiquidationJobStatus'
)
order by type_record.typname, enum_record.enumsortorder;

/* Verify there is exactly one signature per public liquidation RPC. */
select
    procedure_record.proname as function_name,
    pg_get_function_identity_arguments(procedure_record.oid) as arguments,
    procedure_record.prosecdef as security_definer,
    procedure_record.proacl as acl
from pg_proc procedure_record
join pg_namespace namespace_record
  on namespace_record.oid = procedure_record.pronamespace
where namespace_record.nspname = 'public'
  and procedure_record.proname in (
      'claim_country_liquidation_accounting_jobs',
      'claim_country_liquidation_blockchain_jobs',
      'confirm_liquidation_blockchain_transfer',
      'fail_liquidation_accounting_job',
      'fail_liquidation_blockchain_transfer',
      'prepare_country_liquidation_blockchain_jobs',
      'record_liquidation_blockchain_submission',
      'save_liquidation_blockchain_signed_payload'
  )
order by procedure_record.proname, arguments;

/* Verify corrected indexes. */
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in (
      'liquidation_job',
      'liquidation_blockchain_queue'
  )
order by tablename, indexname;

/* These final checks should return zero rows. */
select
    lower(btrim(job_record.country_code)) as country_code,
    job_record.user_id,
    count(*) as unfinished_job_count
from public.liquidation_job job_record
where job_record.status::text <> 'completed'
group by lower(btrim(job_record.country_code)), job_record.user_id
having count(*) > 1;

select queue_record.id, queue_record.tx_hash
from public.liquidation_blockchain_queue queue_record
where nullif(btrim(queue_record.tx_hash), '') is not null
  and queue_record.tx_hash !~ '^0x[0-9A-Fa-f]{64}$';

select
    lower(btrim(queue_record.tx_hash)) as tx_hash,
    count(*) as queue_count
from public.liquidation_blockchain_queue queue_record
where nullif(btrim(queue_record.tx_hash), '') is not null
group by lower(btrim(queue_record.tx_hash))
having count(*) > 1;
