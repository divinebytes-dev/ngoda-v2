/*
 * READ-ONLY PREFLIGHT
 *
 * Result 1 must contain zero rows before 01-schema.sql is run.
 */

select
    lower(btrim(job_record.country_code)) as country_code,
    job_record.user_id,
    count(*) as unfinished_job_count,
    array_agg(job_record.id order by job_record.created_at, job_record.id) as job_ids,
    array_agg(job_record.status::text order by job_record.created_at, job_record.id) as statuses
from public.liquidation_job job_record
where job_record.status::text <> 'completed'
group by
    lower(btrim(job_record.country_code)),
    job_record.user_id
having count(*) > 1
order by country_code, job_record.user_id;

/*
 * Result 2 may contain rows. They will be quarantined for manual review,
 * because no transaction hash was persisted and their on-chain state is
 * therefore uncertain.
 */
select
    queue_record.id as queue_id,
    queue_record.liquidation_job_id,
    queue_record.country_code,
    queue_record.user_id,
    queue_record.status::text as queue_status,
    queue_record.created_at
from public.liquidation_blockchain_queue queue_record
where queue_record.status::text = 'processing'
  and nullif(btrim(queue_record.tx_hash), '') is null
  and queue_record.claimed_at is null
order by queue_record.created_at, queue_record.id;

/* Result 3 should normally contain zero rows. */
select
    queue_record.id as queue_id,
    queue_record.liquidation_job_id,
    queue_record.tx_hash,
    queue_record.status::text as queue_status
from public.liquidation_blockchain_queue queue_record
where nullif(btrim(queue_record.tx_hash), '') is not null
  and queue_record.tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
order by queue_record.created_at, queue_record.id;

/* Result 4 must contain zero rows: one hash may belong to only one queue. */
select
    lower(btrim(queue_record.tx_hash)) as tx_hash,
    count(*) as queue_count,
    array_agg(queue_record.id order by queue_record.created_at, queue_record.id)
        as queue_ids
from public.liquidation_blockchain_queue queue_record
where nullif(btrim(queue_record.tx_hash), '') is not null
group by lower(btrim(queue_record.tx_hash))
having count(*) > 1
order by tx_hash;

/* Result 5 identifies queue rows whose parent job is missing. */
select
    queue_record.id as queue_id,
    queue_record.liquidation_job_id
from public.liquidation_blockchain_queue queue_record
left join public.liquidation_job job_record
  on job_record.id::text = queue_record.liquidation_job_id
where queue_record.liquidation_job_id is not null
  and job_record.id is null
order by queue_record.created_at, queue_record.id;
