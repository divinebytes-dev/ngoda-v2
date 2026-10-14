/*
 * Manual-review liquidation reports.
 *
 * These RPCs are read-only. They never accept or confirm a blockchain
 * transaction hash. Receipt and token-transfer verification must be done by
 * the trusted liquidation service before any lifecycle state is changed.
 */


create or replace function public.fetch_my_manual_review_liquidation_jobs(
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_offset integer;
    v_total_entries integer := 0;
    v_total_pages integer := 1;
    v_rows jsonb := '[]'::jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'REPORTING_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'REPORTING_USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(
            v_user.country_code
        ),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if p_page is null
       or p_page < 1
    then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    v_offset :=
        (p_page - 1) *
        p_page_size;

    with report_rows as materialized (
        select
            queue_record.id::text
                as queue_id,

            job_record.id::text
                as liquidation_job_id,

            job_record.document_number,
            job_record.fiscal_year,
            job_record.period,

            lower(
                btrim(
                    job_record.country_code
                )
            ) as country_code,

            job_record.user_id,
            customer_record.email,
            customer_record.phone,
            customer_record.first_name,
            customer_record.surname,

            job_record.status::text
                as job_status,

            queue_record.status::text
                as queue_status,

            queue_record.sender_wallet_address
                as from_address,

            coalesce(
                nullif(
                    btrim(
                        queue_record.signed_payload ->> 'to'
                    ),
                    ''
                ),
                queue_record.receiver_wallet_address
            ) as to_address,

            trim_scale(
                queue_record.collateral
            )::text as amount,

            'gold'::text
                as currency_code,

            queue_record.tx_hash,
            queue_record.explorer_url,
            queue_record.attempt_count,
            queue_record.retry_count,
            queue_record.error_message,
            queue_record.created_at,
            queue_record.signed_at,
            queue_record.last_attempt_at,

            case
                when nullif(
                    btrim(
                        queue_record.tx_hash
                    ),
                    ''
                ) is null
                then 'VERIFY_ON_CHAIN'

                when queue_record.status::text = 'confirmed'
                     and blockchain_record.id is not null
                then 'RESUME_ACCOUNTING'

                else 'VERIFY_STORED_TRANSACTION'
            end as recommended_action,

            case
                when nullif(
                    btrim(
                        queue_record.tx_hash
                    ),
                    ''
                ) is null
                then
                    'Find and verify the Chiado transaction before retrying.'

                when queue_record.status::text = 'confirmed'
                     and blockchain_record.id is not null
                then
                    'The transfer is recorded; continue liquidation accounting.'

                else
                    'Verify the stored hash, receipt and Gold transfer event.'
            end as action_message,

            coalesce(
                queue_record.last_attempt_at,
                queue_record.signed_at,
                queue_record.created_at
            ) as review_sort_at

        from public.liquidation_blockchain_queue
            queue_record

        join public.liquidation_job
            job_record
          on job_record.id::text =
             queue_record.liquidation_job_id

        left join public.users
            customer_record
          on customer_record.id =
             job_record.user_id

        left join lateral (
            select transaction_record.id
            from public.blockchain_transaction
                transaction_record
            where nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is not null

              and lower(
                  transaction_record.tx_hash
              ) = lower(
                  btrim(
                      queue_record.tx_hash
                  )
              )
            limit 1
        ) as blockchain_record
          on true

        where queue_record.manual_review_required = true

          and lower(
              btrim(
                  queue_record.country_code
              )
          ) = lower(
              btrim(
                  v_user.country_code
              )
          )
    ),

    page_rows as (
        select report_record.*
        from report_rows
            report_record
        order by
            report_record.review_sort_at desc,
            report_record.queue_id desc
        limit p_page_size
        offset v_offset
    )
    select
        (
            select count(*)::integer
            from report_rows
        ),

        coalesce(
            (
                select jsonb_agg(
                    to_jsonb(page_record) - 'review_sort_at'
                    order by
                        page_record.review_sort_at desc,
                        page_record.queue_id desc
                )
                from page_rows
                    page_record
            ),
            '[]'::jsonb
        )
    into
        v_total_entries,
        v_rows;

    v_total_pages :=
        greatest(
            ceil(
                v_total_entries::numeric /
                p_page_size
            )::integer,
            1
        );

    return jsonb_build_object(
        'rows',
        v_rows,

        'pagination',
        jsonb_build_object(
            'page',
            p_page,

            'page_size',
            p_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            p_page > 1,

            'has_next',
            p_page < v_total_pages
        )
    );
end;
$function$;


create or replace function public.fetch_my_manual_review_liquidation_job(
    p_job_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_job_id text;
    v_result jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'REPORTING_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'REPORTING_USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(
            v_user.country_code
        ),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
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

        'manual_review_required',
        queue_record.manual_review_required,

        'document',
        jsonb_build_object(
            'document_number',
            job_record.document_number,

            'fiscal_year',
            job_record.fiscal_year,

            'period',
            job_record.period,

            'country_code',
            lower(
                btrim(
                    job_record.country_code
                )
            )
        ),

        'customer',
        jsonb_build_object(
            'user_id',
            job_record.user_id,

            'email',
            customer_record.email,

            'phone',
            customer_record.phone,

            'first_name',
            customer_record.first_name,

            'surname',
            customer_record.surname
        ),

        'status',
        jsonb_build_object(
            'job_status',
            job_record.status::text,

            'queue_status',
            queue_record.status::text,

            'job_error',
            job_record.error_message,

            'queue_error',
            queue_record.error_message,

            'attempt_count',
            queue_record.attempt_count,

            'retry_count',
            queue_record.retry_count
        ),

        'expected_transfer',
        jsonb_build_object(
            'chain',
            'chiado',

            'transaction_type',
            'loan_liquidation',

            'from',
            queue_record.sender_wallet_address,

            'to',
            coalesce(
                nullif(
                    btrim(
                        queue_record.signed_payload ->> 'to'
                    ),
                    ''
                ),
                queue_record.receiver_wallet_address
            ),

            'currency_code',
            'gold',

            'amount',
            trim_scale(
                queue_record.collateral
            )::text,

            'raw_amount',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'parsedAmount'
                ),
                ''
            ),

            'permit_owner',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'owner'
                ),
                ''
            ),

            'permit_nonce',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'nonce'
                ),
                ''
            ),

            'permit_deadline',
            case
                when queue_record.signed_payload ->> 'deadline'
                     ~ '^[0-9]+$'
                then to_timestamp(
                    (
                        queue_record.signed_payload ->>
                        'deadline'
                    )::double precision
                )
                else null
            end,

            'permit_expired',
            case
                when queue_record.signed_payload ->> 'deadline'
                     ~ '^[0-9]+$'
                then to_timestamp(
                    (
                        queue_record.signed_payload ->>
                        'deadline'
                    )::double precision
                ) < now()
                else null
            end
        ),

        'liquidation_values',
        jsonb_build_object(
            'principal',
            trim_scale(
                job_record.total_principal
            )::text,

            'interest',
            trim_scale(
                job_record.total_interest
            )::text,

            'total_debt',
            trim_scale(
                job_record.total_debt
            )::text,

            'repayment_required',
            trim_scale(
                job_record.repayment_required
            )::text,

            'penalty_amount',
            trim_scale(
                job_record.penalty_amount
            )::text,

            'total_proceeds',
            trim_scale(
                job_record.total_required
            )::text,

            'collateral_required',
            trim_scale(
                job_record.collateral_required
            )::text,

            'gold_price',
            trim_scale(
                job_record.gold_price
            )::text
        ),

        'blockchain_evidence',
        jsonb_build_object(
            'queue_tx_hash',
            queue_record.tx_hash,

            'recorded_tx_hash',
            blockchain_record.tx_hash,

            'blockchain_transaction_id',
            blockchain_record.id,

            'transaction_status',
            blockchain_record.status,

            'chain_status',
            blockchain_record.chain_status,

            'explorer_url',
            coalesce(
                queue_record.explorer_url,
                blockchain_record.explorer_url
            ),

            'submitted_at',
            queue_record.submitted_at,

            'confirmed_at',
            queue_record.confirmed_at,

            'recorded_at',
            blockchain_record.created_at
        ),

        'timeline',
        jsonb_build_object(
            'created_at',
            queue_record.created_at,

            'processing_started_at',
            queue_record.processing_started_at,

            'last_attempt_at',
            queue_record.last_attempt_at,

            'signed_at',
            queue_record.signed_at,

            'claimed_at',
            queue_record.claimed_at
        ),

        'recommended_action',
        case
            when nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is null
            then jsonb_build_object(
                'code',
                'VERIFY_ON_CHAIN',

                'message',
                'Search Chiado for the expected Gold transfer before changing this job.',

                'success_result',
                'A trusted service must verify and record the transaction hash, then confirm the transfer.',

                'not_found_result',
                'If the permit nonce is unchanged and no transfer exists, clear the expired signature and retry.',

                'uncertain_result',
                'If the nonce advanced but the matching transfer is not identified, keep manual review enabled.'
            )

            when queue_record.status::text = 'confirmed'
                 and blockchain_record.id is not null
            then jsonb_build_object(
                'code',
                'RESUME_ACCOUNTING',

                'message',
                'Blockchain confirmation is recorded. Resume liquidation accounting.'
            )

            else jsonb_build_object(
                'code',
                'VERIFY_STORED_TRANSACTION',

                'message',
                'Verify the stored hash, successful receipt and exact Gold transfer event before continuing.'
            )
        end,

        'verification_requirements',
        jsonb_build_array(
            'The transaction receipt succeeded on Chiado.',
            'The token contract is the configured Gold token contract.',
            'The transfer sender equals expected_transfer.from.',
            'The transfer receiver equals expected_transfer.to.',
            'The raw token amount equals expected_transfer.raw_amount.',
            'The permit nonce belongs to expected_transfer.permit_owner.'
        )
    )
    into v_result
    from public.liquidation_job
        job_record

    join public.liquidation_blockchain_queue
        queue_record
      on queue_record.liquidation_job_id =
         job_record.id::text

    left join public.users
        customer_record
      on customer_record.id =
         job_record.user_id

    left join lateral (
        select transaction_record.*
        from public.blockchain_transaction
            transaction_record
        where (
            nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is not null

            and lower(
                transaction_record.tx_hash
            ) = lower(
                btrim(
                    queue_record.tx_hash
                )
            )
        )

        or (
            nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is null

            and transaction_record.document_number =
                job_record.document_number

            and transaction_record.transaction_type =
                'loan_liquidation'::public."TransactionType"
        )
        order by
            transaction_record.created_at desc
        limit 1
    ) as blockchain_record
      on true

    where job_record.id::text =
          v_job_id

      and queue_record.manual_review_required = true

      and lower(
          btrim(
              job_record.country_code
          )
      ) = lower(
          btrim(
              v_user.country_code
          )
      );

    if v_result is null then
        raise exception
            'MANUAL_REVIEW_LIQUIDATION_JOB_NOT_FOUND';
    end if;

    return v_result;
end;
$function$;


revoke all on function public.fetch_my_manual_review_liquidation_jobs(
    integer,
    integer
)
from public, anon;

grant execute on function public.fetch_my_manual_review_liquidation_jobs(
    integer,
    integer
)
to authenticated;


revoke all on function public.fetch_my_manual_review_liquidation_job(
    text
)
from public, anon;

grant execute on function public.fetch_my_manual_review_liquidation_job(
    text
)
to authenticated;
