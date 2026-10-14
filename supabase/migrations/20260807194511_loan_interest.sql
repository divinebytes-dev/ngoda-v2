/*
 * ============================================================
 * DAILY LOAN INTEREST ACCRUAL
 * ============================================================
 *
 * Existing reusable functions used:
 *
 * public.fetch_operational_countries()
 * public.fetch_fiscal_period(text)
 * public.fetch_gl_mappings("TransactionType")
 * public.fetch_transaction_doc_num_prefix("TransactionType")
 * public.generate_document_number(text, integer, integer, text)
 * public.post_financial_entries(...)
 * public.update_loan_snapshot(...)
 */


/*
 * ============================================================
 * 1. ACCRUE INTEREST FOR ONE LOAN
 * ============================================================
 */

create or replace function public.accrue_daily_interest_for_loan(
    p_loan_id text,
    p_accrual_date date
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_loan public.loan%rowtype;

    v_last_accrued_date date;
    v_days_missing integer;

    v_principal numeric := 0;
    v_interest_rate numeric := 0;
    v_daily_rate numeric := 0;
    v_interest numeric := 0;

    v_fiscal_year integer;
    v_period integer;

    v_document_prefix text;
    v_document_number text;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_financial_transaction_id bigint;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Lock the loan so two accrual processes cannot process
     * the same loan concurrently.
     */
    v_stage := 'fetch and lock active loan';

    select loan_record.*
    into v_loan
    from public.loan loan_record
    where loan_record.id =
          p_loan_id
      and loan_record.status =
          'active'::public."LoanStatus"
    for update;

    if not found then
        return false;
    end if;

    /*
     * Determine the last date for which interest was accrued.
     */
    v_stage := 'calculate missing accrual days';

    v_last_accrued_date :=
        coalesce(
            v_loan.last_accrued_at::date,
            v_loan.created_at::date
        );

    v_days_missing :=
        p_accrual_date -
        v_last_accrued_date;

    if v_days_missing <= 0 then
        return false;
    end if;

    /*
     * Prevent duplicate accrual for the same loan and date.
     */
    v_stage := 'check existing accrual';

    perform 1
    from public.loan_entry loan_entry_record
    where loan_entry_record.loan_id =
          v_loan.id
      and loan_entry_record.entry_type =
          'interest_accrual'::public."LoanEntryType"
      and loan_entry_record.accrual_date::date =
          p_accrual_date
    limit 1;

    if found then
        /*
         * The entry exists, so ensure last_accrued_at agrees
         * with the existing accrual.
         */
        update public.loan
        set
            last_accrued_at =
                p_accrual_date
        where id =
              v_loan.id;

        return false;
    end if;

    /*
     * Calculate outstanding principal.
     */
    v_stage := 'calculate outstanding principal';

    select coalesce(
        sum(
            coalesce(
                loan_entry_record.debit_principal,
                0
            ) -
            coalesce(
                loan_entry_record.credit_principal,
                0
            )
        ),
        0
    )
    into v_principal
    from public.loan_entry loan_entry_record
    where loan_entry_record.loan_id =
          v_loan.id;

    if v_principal <= 0 then
        return false;
    end if;

    /*
     * Calculate catch-up interest for all missing days.
     */
    v_stage := 'calculate interest';

    v_interest_rate :=
        coalesce(
            v_loan.interest_rate,
            12
        );

    if v_interest_rate <= 0 then
        raise exception
            'INVALID_LOAN_INTEREST_RATE';
    end if;

    v_daily_rate :=
        v_interest_rate /
        100 /
        365;

    v_interest :=
        v_principal *
        v_daily_rate *
        v_days_missing;

    if v_interest <= 0 then
        return false;
    end if;

    /*
     * Fetch fiscal period.
     */
    v_stage := 'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_loan.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch GL mappings.
     */
    v_stage := 'fetch GL mappings';

    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        'loan_interest_accrual'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Interest accrual is a balanced principal component:
     *
     * Debit:  accrued loan interest
     * Credit: interest income/payable GL
     *
     * The GL mapping determines the actual account codes.
     */
    v_stage := 'build posting components';

    v_components :=
        array[
            row(
                'principal'::public."ComponentType",
                v_interest,
                v_interest
            )::public.posting_component
        ];

    /*
     * Generate the document number using the configured prefix.
     */
    v_stage := 'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'loan_interest_accrual'::public."TransactionType"
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_loan.country_code
        );

    /*
     * Insert the loan interest entry.
     */
    v_stage := 'create loan interest entry';

    insert into public.loan_entry (
        loan_id,
        fiscal_year,
        period,
        document_number,
        entry_type,
        debit_principal,
        credit_principal,
        debit_interest,
        credit_interest,
        currency_code,
        accrual_date,
        country_code
    )
    values (
        v_loan.id,
        v_fiscal_year,
        v_period,
        v_document_number,
        'interest_accrual'::public."LoanEntryType",
        0,
        0,
        v_interest,
        0,
        v_loan.currency_code,
        p_accrual_date,
        v_loan.country_code
    );

    /*
     * Create the financial transaction header.
     */
    v_stage := 'create financial transaction';

    insert into public.financial_transaction (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_document_number,
        v_fiscal_year,
        v_period,
        'loan_interest_accrual'::public."TransactionType",
        format(
            'Loan interest accrual for %s (%s days)',
            v_loan.id,
            v_days_missing
        ),
        'admin',
        v_interest,
        v_loan.currency_code,
        v_loan.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post the GL entries.
     */
    v_stage := 'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_loan.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'loan_interest_accrual'::public."TransactionType",

        p_created_by =>
            'admin',

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_loan.currency_code,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_document_number,

        p_deposit_type =>
            null
    );

    /*
     * Update the loan balance snapshot using the existing
     * positional function signature:
     *
     * update_loan_snapshot(
     *   loan_id,
     *   user_id,
     *   country_code,
     *   debit_principal,
     *   credit_principal,
     *   debit_interest,
     *   credit_interest,
     *   fiscal_year,
     *   period
     * )
     */
    v_stage := 'update loan snapshot';

    perform public.update_loan_snapshot(
        v_loan.id,
        v_loan.user_id,
        v_loan.country_code,
        0::numeric,
        0::numeric,
        v_interest,
        0::numeric,
        v_fiscal_year,
        v_period
    );

    /*
     * Mark the loan as accrued through the processing date.
     */
    v_stage := 'update last accrued date';

    update public.loan
    set
        last_accrued_at =
            p_accrual_date
    where id =
          v_loan.id;

    if not found then
        raise exception
            'LOAN_UPDATE_FAILED';
    end if;

    return true;

exception
    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_error_message =
                message_text,

            v_error_detail =
                pg_exception_detail,

            v_error_hint =
                pg_exception_hint,

            v_error_context =
                pg_exception_context;

        raise exception using
            errcode =
                v_error_state,

            message =
                format(
                    'LOAN_INTEREST_ACCRUAL_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                coalesce(
                    nullif(
                        concat_ws(
                            E'\n',
                            nullif(
                                v_error_detail,
                                ''
                            ),
                            nullif(
                                v_error_context,
                                ''
                            )
                        ),
                        ''
                    ),
                    'No additional PostgreSQL context'
                ),

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the loan interest accrual stage reported in the error'
                );
end;
$function$;


/*
 * This function is internal and should not be callable by
 * application roles.
 */
revoke all on function public.accrue_daily_interest_for_loan(
    text,
    date
)
from public;

revoke all on function public.accrue_daily_interest_for_loan(
    text,
    date
)
from anon;

revoke all on function public.accrue_daily_interest_for_loan(
    text,
    date
)
from authenticated;

revoke all on function public.accrue_daily_interest_for_loan(
    text,
    date
)
from service_role;


/*
 * ============================================================
 * 2. PROCESS ALL ACTIVE OPERATIONAL COUNTRIES
 * ============================================================
 *
 * This is deliberately a procedure rather than a function.
 * It commits after each loan, preserving the original behaviour
 * where one failed loan does not roll back successful loans.
 *
 * Do not make this procedure SECURITY DEFINER and do not add
 * a procedure-level SET clause. PostgreSQL does not allow
 * transaction control in those procedure configurations.
 */

create or replace procedure public.run_daily_loan_interest_accrual()
language plpgsql
as $procedure$
declare
    v_accrual_date date :=
        (
            now() at time zone 'UTC'
        )::date;

    v_country_codes text[] :=
        array[]::text[];

    v_loan_ids text[] :=
        array[]::text[];

    v_country_code text;
    v_loan_id text;

    v_processed boolean;
    v_job_lock_acquired boolean := false;

    v_processed_count integer := 0;
    v_skipped_count integer := 0;
    v_failed_count integer := 0;

    v_error_state text;
    v_error_message text;
    v_error_detail text;
begin
    /*
     * Use a session advisory lock to prevent manual execution
     * from overlapping the scheduled execution.
     */
    select pg_catalog.pg_try_advisory_lock(
        pg_catalog.hashtext(
            'daily-loan-interest-accrual'
        )
    )
    into v_job_lock_acquired;

    if not v_job_lock_acquired then
        raise notice
            'Daily loan interest accrual is already running';

        return;
    end if;

    /*
     * Fetch all currently operational countries once.
     *
     * The existing function is expected to return a
     * country_code column.
     */
    select coalesce(
        array_agg(
            operational_country.country_code
            order by
                operational_country.country_code
        ),
        array[]::text[]
    )
    into v_country_codes
    from public.fetch_operational_countries()
        as operational_country;

    /*
     * Process every active loan in every operational country.
     */
    foreach v_country_code
    in array v_country_codes
    loop
        v_loan_ids :=
            array[]::text[];

        begin
            select coalesce(
                array_agg(
                    loan_record.id
                    order by
                        loan_record.created_at,
                        loan_record.id
                ),
                array[]::text[]
            )
            into v_loan_ids
            from public.loan loan_record
            where loan_record.country_code =
                  v_country_code
              and loan_record.status =
                  'active'::public."LoanStatus";

        exception
            when others then
                get stacked diagnostics
                    v_error_state =
                        returned_sqlstate,

                    v_error_message =
                        message_text,

                    v_error_detail =
                        pg_exception_detail;

                begin
                    insert into public.job_error_log (
                        job_name,
                        reference,
                        country_code,
                        error
                    )
                    values (
                        'accrue_interest',
                        'country:' ||
                            v_country_code,
                        v_country_code,
                        concat_ws(
                            E'\n',
                            format(
                                '[%s] %s',
                                v_error_state,
                                v_error_message
                            ),
                            nullif(
                                v_error_detail,
                                ''
                            )
                        )
                    );

                exception
                    when others then
                        raise warning
                            'Could not record country accrual error for %',
                            v_country_code;
                end;

                v_failed_count :=
                    v_failed_count + 1;
        end;

        /*
         * Finish the country lookup transaction before
         * beginning per-loan transactions.
         */
        commit;

        foreach v_loan_id
        in array v_loan_ids
        loop
            v_processed := false;

            begin
                select public.accrue_daily_interest_for_loan(
                    v_loan_id,
                    v_accrual_date
                )
                into v_processed;

                if v_processed then
                    v_processed_count :=
                        v_processed_count + 1;
                else
                    v_skipped_count :=
                        v_skipped_count + 1;
                end if;

            exception
                when others then
                    get stacked diagnostics
                        v_error_state =
                            returned_sqlstate,

                        v_error_message =
                            message_text,

                        v_error_detail =
                            pg_exception_detail;

                    v_failed_count :=
                        v_failed_count + 1;

                    /*
                     * Log outside the failed function's
                     * subtransaction.
                     */
                    begin
                        insert into public.job_error_log (
                            job_name,
                            reference,
                            country_code,
                            error
                        )
                        values (
                            'accrue_interest',
                            v_loan_id,
                            v_country_code,
                            concat_ws(
                                E'\n',
                                format(
                                    '[%s] %s',
                                    v_error_state,
                                    v_error_message
                                ),
                                nullif(
                                    v_error_detail,
                                    ''
                                )
                            )
                        );

                    exception
                        when others then
                            raise warning
                                'Could not record interest accrual error for loan %',
                                v_loan_id;
                    end;
            end;

            /*
             * Commit this loan independently.
             */
            commit;
        end loop;
    end loop;

    perform pg_catalog.pg_advisory_unlock(
        pg_catalog.hashtext(
            'daily-loan-interest-accrual'
        )
    );

    raise notice
        'Loan interest accrual completed. Date: %, processed: %, skipped: %, failed: %',
        v_accrual_date,
        v_processed_count,
        v_skipped_count,
        v_failed_count;
end;
$procedure$;


revoke all on procedure public.run_daily_loan_interest_accrual()
from public;

revoke all on procedure public.run_daily_loan_interest_accrual()
from anon;

revoke all on procedure public.run_daily_loan_interest_accrual()
from authenticated;

revoke all on procedure public.run_daily_loan_interest_accrual()
from service_role;


/*
 * ============================================================
 * 3. SCHEDULE THE JOB
 * ============================================================
 *
 * Enable Supabase Cron/pg_cron through:
 * Dashboard -> Integrations -> Cron
 *
 * The following removes the previous job with this name,
 * then recreates it.
 */

select cron.unschedule(job_record.jobid)
from cron.job job_record
where job_record.jobname =
      'daily-loan-interest-accrual';


select cron.schedule(
    'daily-loan-interest-accrual',
    '0 0 * * *',
    $cron$
        call public.run_daily_loan_interest_accrual();
    $cron$
);