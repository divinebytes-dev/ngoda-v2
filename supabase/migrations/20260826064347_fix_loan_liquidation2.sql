/*
 * Run this file by itself and commit it before 02-rpc-repairs.sql.
 */

alter type public."LiquidationJobStatus"
    add value if not exists 'accounting_failed';

alter table public.liquidation_job
    add column if not exists gold_price numeric,
    add column if not exists target_ltv numeric,
    add column if not exists liquidation_ltv numeric,
    add column if not exists penalty_rate numeric,
    add column if not exists document_number text,
    add column if not exists blockchain_queue_id text,
    add column if not exists completed_at timestamptz,
    add column if not exists accounting_retry_count integer not null default 0,
    add column if not exists accounting_started_at timestamptz;

alter table public.liquidation_blockchain_queue
    add column if not exists liquidation_job_id text,
    add column if not exists treasury_id text,
    add column if not exists sender_wallet_address text,
    add column if not exists receiver_wallet_address text,
    add column if not exists debt_repayment_amount numeric,
    add column if not exists penalty_amount numeric,
    add column if not exists total_liquidation_proceeds numeric,
    add column if not exists gold_price numeric,
    add column if not exists tx_hash text,
    add column if not exists confirmed_at timestamptz,
    add column if not exists processing_started_at timestamptz,
    add column if not exists last_attempt_at timestamptz,
    add column if not exists signed_payload jsonb,
    add column if not exists signed_at timestamptz,
    add column if not exists claimed_at timestamptz,
    add column if not exists lease_expires_at timestamptz,
    add column if not exists submitted_at timestamptz,
    add column if not exists explorer_url text,
    add column if not exists error_message text,
    add column if not exists manual_review_required boolean not null default false,
    add column if not exists attempt_count integer not null default 0,
    add column if not exists retry_count integer not null default 0,
    add column if not exists updated_at timestamptz not null default now();

/* Preserve useful errors from the legacy reason column. */
update public.liquidation_blockchain_queue queue_record
set error_message = nullif(btrim(queue_record.reason), '')
where nullif(btrim(queue_record.error_message), '') is null
  and nullif(btrim(queue_record.reason), '') is not null;

update public.liquidation_blockchain_queue
set tx_hash = null
where tx_hash is not null
  and nullif(btrim(tx_hash), '') is null;

/* Quarantine ambiguous legacy processing rows. */
update public.liquidation_blockchain_queue queue_record
set
    manual_review_required = true,
    error_message = coalesce(
        nullif(btrim(queue_record.error_message), ''),
        'LEGACY_PROCESSING_STATE_REQUIRES_RECONCILIATION'
    ),
    updated_at = now()
where queue_record.status::text = 'processing'
  and nullif(btrim(queue_record.tx_hash), '') is null
  and queue_record.claimed_at is null;

update public.liquidation_job job_record
set error_message = coalesce(
    nullif(btrim(job_record.error_message), ''),
    'LEGACY_PROCESSING_STATE_REQUIRES_RECONCILIATION'
)
where exists (
    select 1
    from public.liquidation_blockchain_queue queue_record
    where queue_record.liquidation_job_id = job_record.id::text
      and queue_record.manual_review_required = true
);

/*
 * The live index UNIQUE (user_id, status) blocks multiple completed jobs.
 */
drop index if exists public.liquidation_job_user_id_status_key;

create unique index if not exists liquidation_job_unfinished_position_unique
on public.liquidation_job (
    lower(btrim(country_code)),
    user_id
)
where status <> 'completed'::public."LiquidationJobStatus";

create unique index if not exists liquidation_blockchain_queue_job_unique
on public.liquidation_blockchain_queue (liquidation_job_id)
where liquidation_job_id is not null;

create unique index if not exists liquidation_blockchain_queue_tx_hash_unique
on public.liquidation_blockchain_queue (lower(btrim(tx_hash)))
where tx_hash is not null;

create index if not exists liquidation_blockchain_queue_claim_idx
on public.liquidation_blockchain_queue (
    country_code,
    status,
    lease_expires_at,
    created_at
);

create index if not exists liquidation_blockchain_queue_job_idx
on public.liquidation_blockchain_queue (liquidation_job_id);

create index if not exists liquidation_job_accounting_claim_idx
on public.liquidation_job (
    country_code,
    status,
    accounting_started_at,
    created_at
);

do $block$
begin
    if not exists (
        select 1
        from pg_constraint constraint_record
        where constraint_record.conname =
              'liquidation_blockchain_queue_attempt_count_check'
          and constraint_record.conrelid =
              'public.liquidation_blockchain_queue'::regclass
    ) then
        alter table public.liquidation_blockchain_queue
            add constraint liquidation_blockchain_queue_attempt_count_check
            check (attempt_count >= 0 and retry_count >= 0);
    end if;
end;
$block$;
