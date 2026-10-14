CREATE OR REPLACE FUNCTION public.fetch_my_liquidated_loans_today(
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_offset integer;
    v_total_entries integer := 0;
    v_total_pages integer := 1;

    v_rows jsonb :=
        '[]'::jsonb;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Accounts and Finance may review liquidation reports.
     */
    v_stage :=
        'authorize reporting user';

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

    /*
     * Validate pagination.
     */
    v_stage :=
        'validate pagination';

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

    /*
     * A loan appears here only after liquidation accounting
     * has created both the loan ledger entry and financial
     * transaction header.
     *
     * This avoids treating a merely detected or queued job
     * as a completed liquidation.
     */
    v_stage :=
        'fetch liquidated loans';

    with report_rows as materialized (
        select
            loan_entry_record.loan_id::text
                as loan_id,

            loan_record.user_id
                as user_id,

            user_record.email,
            user_record.phone,
            user_record.first_name,
            user_record.surname,

            loan_entry_record.document_number,

            lower(
                btrim(
                    loan_entry_record.currency_code
                )
            ) as currency_code,

            trim_scale(
                coalesce(
                    sum(
                        loan_entry_record.credit_principal
                    ),
                    0
                )
            )::text as principal_liquidated,

            trim_scale(
                coalesce(
                    sum(
                        loan_entry_record.credit_interest
                    ),
                    0
                )
            )::text as interest_liquidated,

            trim_scale(
                coalesce(
                    sum(
                        loan_entry_record.credit_principal +
                        loan_entry_record.credit_interest
                    ),
                    0
                )
            )::text as total_liquidated,

            loan_record.status::text
                as loan_status,

            min(
                transaction_record.created_at
            ) as liquidated_at

        from public.loan_entry
            loan_entry_record

        join public.loan
            loan_record
          on loan_record.id =
             loan_entry_record.loan_id

        join public.users
            user_record
          on user_record.id =
             loan_record.user_id

        join public.financial_transaction
            transaction_record
          on transaction_record.document_number =
             loan_entry_record.document_number

         and transaction_record.country_code =
             loan_entry_record.country_code

         and transaction_record.transaction_type =
             'loan_liquidation'::public."TransactionType"

        where lower(
            btrim(
                loan_entry_record.country_code
            )
        ) =
            lower(
                btrim(
                    v_user.country_code
                )
            )

          and loan_entry_record.entry_type::text =
              'liquidation'

          and transaction_record.created_at >=
              current_date

          and transaction_record.created_at <
              current_date + 1

        group by
            loan_entry_record.loan_id,
            loan_record.user_id,
            user_record.email,
            user_record.phone,
            user_record.first_name,
            user_record.surname,
            loan_entry_record.document_number,
            lower(
                btrim(
                    loan_entry_record.currency_code
                )
            ),
            loan_record.status::text
    ),

    page_rows as (
        select report_record.*
        from report_rows
            report_record
        order by
            report_record.liquidated_at desc,
            report_record.document_number desc,
            report_record.loan_id
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
                    to_jsonb(
                        page_record
                    )
                    order by
                        page_record.liquidated_at desc,
                        page_record.document_number desc,
                        page_record.loan_id
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

exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,

            message = format(
                'LIQUIDATED_LOANS_REPORT_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the liquidated-loans report stage'
            );
end;
$function$;


CREATE OR REPLACE FUNCTION public.fetch_my_incomplete_liquidation_jobs(
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_offset integer;
    v_total_entries integer := 0;
    v_total_pages integer := 1;

    v_rows jsonb :=
        '[]'::jsonb;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Accounts and Finance may review failed liquidation
     * processing.
     */
    v_stage :=
        'authorize reporting user';

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

    /*
     * Validate pagination.
     */
    v_stage :=
        'validate pagination';

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

    /*
     * Return incomplete jobs having either a job-level
     * error or a failed blockchain queue entry.
     *
     * to_jsonb(queue_record) lets this report support the
     * existing queue schemas that used either error_message
     * or reason for the blockchain failure text.
     */
    v_stage :=
        'fetch incomplete liquidation jobs';

    with report_rows as materialized (
        select
            job_record.id::text
                as job_id,

            job_record.user_id,

            user_record.email,
            user_record.phone,
            user_record.first_name,
            user_record.surname,

            job_record.document_number,

            lower(
                btrim(
                    job_record.country_code
                )
            ) as country_code,

            job_record.fiscal_year,
            job_record.period,

            job_record.status::text
                as job_status,

            trim_scale(
                job_record.total_principal
            )::text as total_principal,

            trim_scale(
                job_record.total_interest
            )::text as total_interest,

            trim_scale(
                job_record.total_debt
            )::text as total_debt,

            trim_scale(
                job_record.penalty_amount
            )::text as penalty_amount,

            trim_scale(
                job_record.repayment_required
            )::text as repayment_required,

            trim_scale(
                job_record.collateral_required
            )::text as collateral_required,

            trim_scale(
                job_record.gold_price
            )::text as gold_price,

            job_record.blockchain_queue_id,

            queue_record.status::text
                as blockchain_status,

            nullif(
                to_jsonb(queue_record) ->>
                    'tx_hash',
                ''
            ) as tx_hash,

            coalesce(
                nullif(
                    job_record.error_message,
                    ''
                ),
                nullif(
                    to_jsonb(queue_record) ->>
                        'error_message',
                    ''
                ),
                nullif(
                    to_jsonb(queue_record) ->>
                        'reason',
                    ''
                )
            ) as error_message,

            coalesce(
                nullif(
                    to_jsonb(queue_record) ->>
                        'retry_count',
                    ''
                )::integer,
                0
            ) as retry_count,

            job_record.created_at

        from public.liquidation_job
            job_record

        join public.users
            user_record
          on user_record.id =
             job_record.user_id

        left join lateral (
            select queue_source.*
            from public.liquidation_blockchain_queue
                queue_source
            where queue_source.liquidation_job_id =
                  job_record.id::text
            order by
                queue_source.id desc
            limit 1
        ) as queue_record
          on true

        where lower(
            btrim(
                job_record.country_code
            )
        ) =
            lower(
                btrim(
                    v_user.country_code
                )
            )

          and job_record.status::text <>
              'completed'

          and (
              nullif(
                  btrim(
                      job_record.error_message
                  ),
                  ''
              ) is not null

              or queue_record.status::text =
                 'failed'

              or nullif(
                  btrim(
                      coalesce(
                          to_jsonb(queue_record) ->>
                              'error_message',
                          to_jsonb(queue_record) ->>
                              'reason'
                      )
                  ),
                  ''
              ) is not null
          )
    ),

    page_rows as (
        select report_record.*
        from report_rows
            report_record
        order by
            report_record.created_at desc,
            report_record.job_id desc
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
                    to_jsonb(
                        page_record
                    )
                    order by
                        page_record.created_at desc,
                        page_record.job_id desc
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

exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,

            message = format(
                'INCOMPLETE_LIQUIDATION_JOBS_REPORT_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the incomplete-liquidation report stage'
            );
end;
$function$;
