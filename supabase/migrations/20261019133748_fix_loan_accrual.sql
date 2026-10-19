-- Run in QA as postgres. Prerequisite: operational_country.time_zone configured.
BEGIN;
DO $preflight$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.operational_country c
        WHERE c.is_active AND (
            nullif(btrim(c.time_zone), '') IS NULL OR NOT EXISTS (
                SELECT 1 FROM pg_catalog.pg_timezone_names t
                WHERE t.name = c.time_zone
            )
        )
    ) THEN RAISE EXCEPTION 'ACTIVE_COUNTRY_TIME_ZONE_REQUIRED'; END IF;
END;
$preflight$;
CREATE OR REPLACE FUNCTION "public"."accrue_daily_interest_for_loan"("p_loan_id" "text", "p_accrual_date" "date") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
    v_loan public.loan%rowtype;

    v_last_accrued_date date;
    v_country_time_zone text;
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
    v_stage := 'validate country time zone';

    select c.time_zone into v_country_time_zone
    from public.operational_country as c
    where c.country_code = v_loan.country_code;

    if nullif(btrim(v_country_time_zone), '') is null
       or not exists (
           select 1 from pg_catalog.pg_timezone_names as t
           where t.name = v_country_time_zone
       )
    then
        raise exception 'INVALID_OR_MISSING_COUNTRY_TIME_ZONE: %', v_loan.country_code;
    end if;

    if p_accrual_date is null then
        raise exception 'ACCRUAL_DATE_REQUIRED';
    end if;

    v_stage := 'calculate missing accrual days';

    v_last_accrued_date :=
        coalesce(
            v_loan.last_accrued_at::date,
            (v_loan.created_at at time zone v_country_time_zone)::date
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
        v_loan.country_code,
        p_accrual_date::timestamp
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
$$;


ALTER FUNCTION "public"."accrue_daily_interest_for_loan"("p_loan_id" "text", "p_accrual_date" "date") OWNER TO "postgres";

CREATE OR REPLACE PROCEDURE public.run_daily_loan_interest_accrual()
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_countries public.operational_country[];
    v_country public.operational_country%rowtype;
    v_local_now timestamp;
    v_accrual_date date;
    v_loan_ids text[];
    v_loan_id text;
    v_processed boolean;
    v_processed_count integer := 0;
    v_skipped_count integer := 0;
    v_failed_count integer := 0;
    v_error_state text;
    v_error_message text;
    v_error_detail text;
BEGIN
    -- Snapshot configuration before acquiring the session lock.
    SELECT coalesce(
        array_agg(c ORDER BY c.country_code),
        ARRAY[]::public.operational_country[]
    ) INTO v_countries
    FROM public.operational_country AS c
    WHERE c.is_active;

    IF NOT pg_catalog.pg_try_advisory_lock(
        pg_catalog.hashtext('daily-loan-interest-accrual')
    ) THEN
        RAISE NOTICE 'Daily loan interest accrual is already running';
        RETURN;
    END IF;

    FOREACH v_country IN ARRAY v_countries LOOP
        v_loan_ids := ARRAY[]::text[];
        v_accrual_date := NULL;

        BEGIN
            IF nullif(btrim(v_country.time_zone), '') IS NULL
               OR NOT EXISTS (
                   SELECT 1 FROM pg_catalog.pg_timezone_names AS t
                   WHERE t.name = v_country.time_zone
               )
            THEN
                RAISE EXCEPTION 'INVALID_OR_MISSING_COUNTRY_TIME_ZONE: %',
                    v_country.country_code;
            END IF;

            -- Use wall-clock time, not the UTC date or a fixed UTC offset.
            v_local_now := pg_catalog.clock_timestamp()
                AT TIME ZONE v_country.time_zone;
            v_accrual_date := v_local_now::date;

            -- 00:01 is the opening of the daily accrual window.
            -- Checking throughout the day catches delayed or missed cron runs.
            -- Per-loan last_accrued_at and existing loan-entry checks prevent
            -- charging completed loans again for this local date.
            IF v_local_now::time >= TIME '00:01:00' THEN
                SELECT coalesce(
                    array_agg(l.id::text ORDER BY l.created_at, l.id),
                    ARRAY[]::text[]
                ) INTO v_loan_ids
                FROM public.loan AS l
                WHERE l.country_code = v_country.country_code
                  AND l.status = 'active'::public."LoanStatus"
                  AND coalesce(
                      l.last_accrued_at::date,
                      (l.created_at AT TIME ZONE v_country.time_zone)::date
                  ) < v_accrual_date;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_state = RETURNED_SQLSTATE,
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL;
            v_failed_count := v_failed_count + 1;
            BEGIN
                INSERT INTO public.job_error_log(
                    job_name, reference, country_code, error
                ) VALUES (
                    'accrue_interest',
                    'country:' || v_country.country_code,
                    v_country.country_code,
                    concat_ws(E'\n',
                        format('[%s] %s', v_error_state, v_error_message),
                        nullif(v_error_detail, '')
                    )
                );
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Could not record country accrual error for %',
                    v_country.country_code;
            END;
        END;

        COMMIT;

        FOREACH v_loan_id IN ARRAY v_loan_ids LOOP
            BEGIN
                v_processed := public.accrue_daily_interest_for_loan(
                    v_loan_id, v_accrual_date
                );
                IF v_processed THEN
                    v_processed_count := v_processed_count + 1;
                ELSE
                    v_skipped_count := v_skipped_count + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS
                    v_error_state = RETURNED_SQLSTATE,
                    v_error_message = MESSAGE_TEXT,
                    v_error_detail = PG_EXCEPTION_DETAIL;
                v_failed_count := v_failed_count + 1;
                BEGIN
                    INSERT INTO public.job_error_log(
                        job_name, reference, country_code, error
                    ) VALUES (
                        'accrue_interest', v_loan_id, v_country.country_code,
                        concat_ws(E'\n',
                            format('[%s] %s; local accrual date=%s',
                                v_error_state, v_error_message, v_accrual_date),
                            nullif(v_error_detail, '')
                        )
                    );
                EXCEPTION WHEN OTHERS THEN
                    RAISE WARNING 'Could not record interest accrual error for loan %',
                        v_loan_id;
                END;
            END;
            -- Keep existing independent per-loan transactions.
            COMMIT;
        END LOOP;
    END LOOP;

    PERFORM pg_catalog.pg_advisory_unlock(
        pg_catalog.hashtext('daily-loan-interest-accrual')
    );
    RAISE NOTICE 'Country-local interest accrual completed. Processed: %, skipped: %, failed: %',
        v_processed_count, v_skipped_count, v_failed_count;
END;
$procedure$;

ALTER PROCEDURE public.run_daily_loan_interest_accrual() OWNER TO postgres;
REVOKE ALL ON PROCEDURE public.run_daily_loan_interest_accrual()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.run_daily_loan_interest_accrual() TO service_role;

REVOKE ALL ON FUNCTION public.accrue_daily_interest_for_loan(text,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.accrue_daily_interest_for_loan(text,date) TO service_role;
COMMIT;
