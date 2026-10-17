-- Pooled collateral repayment correction, 2026-10-17.
-- Replaces execute_my_loan_repayment in full; signature and result unchanged.
-- No Edge change is required. No historical postings are rewritten.
-- Source of locked GOLD: collateral.locked_tokens (one user-wide pool).
-- Source of debt: loan_entry. Saved max_ltv_percent matches top-up policy.
-- loan.collateral is current allocation, NOT historical locked quantity.
-- collateral_entry records actual pool increases/decreases with loan attribution;
-- its per-loan sums do not represent allocations after pool redistribution.
BEGIN;

CREATE OR REPLACE FUNCTION public.execute_my_loan_repayment(p_amount text, p_reference text, p_currency_code text DEFAULT 'usd'::text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, principal_paid text, interest_paid text, collateral_unlocked text, unused_payment text, loans_closed integer, customer_id text, country_code text, currency_code text, payment_applied text, wallet_debit text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_transaction_type
        public."TransactionType" :=
            'loan_repayment'::public."TransactionType";

    v_stage text :=
        'initialization';

    v_user
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_collateral
        public.collateral%rowtype;

    v_loan
        public.loan%rowtype;

    v_reference text;
    v_currency text;


    /*
     * ==========================================================
     * REPAYMENT AMOUNTS
     * ==========================================================
     */

    /*
     * Amount entered by the customer.
     */
    v_payment_amount numeric;

    /*
     * Portion of the entered amount that remains after all
     * outstanding loans have been satisfied.
     *
     * This amount is NOT deducted from the customer's wallet.
     */
    v_remaining_payment numeric;


    v_principal_outstanding numeric;
    v_interest_outstanding numeric;

    v_principal_paid numeric;
    v_interest_paid numeric;


    v_total_principal_paid numeric :=
        0;

    v_total_interest_paid numeric :=
        0;


    /*
     * Exact amount actually applied to outstanding debt.
     *
     * payment_applied =
     *     principal_paid + interest_paid
     *
     * This is also the exact customer wallet debit.
     */
    v_total_payment_applied numeric :=
        0;


    v_principal_remaining numeric;
    v_interest_remaining numeric;

    /*
     * Remaining total debt after this repayment allocation.
     *
     * Collateral protection is based on the complete debt
     * position, not principal alone.
     */
    v_total_debt_remaining numeric :=
        0;


    /*
     * ==========================================================
     * COLLATERAL / RISK
     * ==========================================================
     */

    /*
     * Same current gold price source used by preview_my_loan().
     */
    v_market_price numeric :=
        0;

    -- Shared-pool calculation and current per-loan allocation plan.
    v_previous_locked numeric;
    v_required_pool numeric := 0;
    v_retained_pool numeric;
    v_remaining_pool numeric;
    v_allocation numeric;
    v_target_ltv numeric;
    v_target_collateral numeric;
    v_portfolio_ids text[] := ARRAY[]::text[];
    v_portfolio_id text;
    v_plan jsonb := '[]'::jsonb;
    v_plan_row jsonb;
    v_payments jsonb := '[]'::jsonb;
    v_payment_row jsonb;
    v_release_remaining numeric;
    v_payment_remaining numeric;
    v_release_part numeric;
    v_release_sum numeric := 0;
    v_liquidation_price numeric;

    /*
     * Total released across all loans affected by this repayment.
     */
    v_total_collateral_unlock numeric :=
        0;


    v_closed_loans_count integer :=
        0;

    v_active_loan_found boolean :=
        false;


    /*
     * ==========================================================
     * ACCOUNTING
     * ==========================================================
     */

    v_fiscal_year integer;
    v_period integer;

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];


    /*
     * ==========================================================
     * ERROR DIAGNOSTICS
     * ==========================================================
     */

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;

begin
/*
 * ==========================================================
 * AUTHORIZE BORROWER
 * ==========================================================
 *
 * SVA / loan functionality is available to:
 *
 * - customer
 * - agent
 * - vendor
 *
 * Agent and vendor loans belong to the same user and use
 * that user's personal/customer wallet for repayment.
 */

    v_stage :=
        'authorize borrower';


    if auth.uid() is null then
        raise exception using
            errcode =
                '42501',

            message =
                'UNAUTHORIZED';
    end if;


    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;


    select
        user_record.*
    into
        v_user
    from public.users
        user_record
    where user_record.id =
        auth.uid()::text
    limit 1;


    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;


    if v_user.status is distinct from
    'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;


    if v_user.country_code is null
    or btrim(
        v_user.country_code
    ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * ==========================================================
     * PARSE REPAYMENT AMOUNT
     * ==========================================================
     */

    v_stage :=
        'parse repayment amount';


    begin
        v_payment_amount :=
            nullif(
                btrim(
                    p_amount
                ),
                ''
            )::numeric;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_REPAYMENT_AMOUNT';
    end;


    if v_payment_amount is null
       or v_payment_amount::text in ('NaN', 'Infinity', '-Infinity')
       or v_payment_amount <= 0
       or v_payment_amount <> trunc(v_payment_amount, 2)
    then
        raise exception
            'INVALID_REPAYMENT_AMOUNT';
    end if;


    v_remaining_payment :=
        v_payment_amount;


    /*
     * ==========================================================
     * PARSE REFERENCE
     * ==========================================================
     */

    v_stage :=
        'parse reference';


    v_reference :=
        nullif(
            btrim(
                p_reference
            ),
            ''
        );


    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;


    /*
     * ==========================================================
     * PARSE CURRENCY
     * ==========================================================
     *
     * Loans are always USD.
     */

    v_stage :=
        'parse currency';


    v_currency :=
        lower(
            nullif(
                btrim(
                    p_currency_code
                ),
                ''
            )
        );


    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;


    if v_currency <> 'usd' then
        raise exception
            'UNSUPPORTED_LOAN_CURRENCY';
    end if;


    /*
     * ==========================================================
     * PREVENT REPLAY
     * ==========================================================
     */

    v_stage :=
        'lock repayment reference';


    perform
        pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                v_reference,
                0
            )
        );


    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.reference =
          v_reference;


    if found then
        raise exception using
            errcode =
                '23505',

            message =
                'TRANSACTION_REPLAY';
    end if;


    /*
     * ==========================================================
     * SERIALIZE CUSTOMER REPAYMENTS
     * ==========================================================
     *
     * Prevent two repayments from allocating against the same
     * outstanding loan balances concurrently.
     */

    v_stage := 'lock customer loan position';

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'loan-position:' || v_user.id,
            0
        )
    );

    if exists (
        select 1
        from public.liquidation_job as j
        where j.user_id = v_user.id
        and j.status::text not in (
            'completed',
            'cancelled'
        )
    ) then
        raise exception
            'LOAN_POSITION_LIQUIDATION_IN_PROGRESS';
    end if;


    /*
     * ==========================================================
     * FETCH TREASURY
     * ==========================================================
     */

    v_stage :=
        'fetch country treasury';


    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );


    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * LOCK CUSTOMER COLLATERAL
     * ==========================================================
     */

    v_stage :=
        'lock collateral';


    select
        collateral_record.*
    into
        v_collateral
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_user.id
    for update;


    if not found then
        raise exception
            'COLLATERAL_NOT_FOUND';
    end if;


    if v_collateral.country_code
       is distinct from
       v_user.country_code
    then
        raise exception
            'COLLATERAL_COUNTRY_MISMATCH';
    end if;


    /*
     * ==========================================================
     * FETCH CURRENT GOLD PRICE
     * ==========================================================
     *
     * This is the exact same source used by preview_my_loan().
     */

    v_previous_locked := v_collateral.locked_tokens;
    if v_previous_locked is null
       or v_previous_locked::text in ('NaN', 'Infinity', '-Infinity')
       or v_previous_locked < 0
       or v_previous_locked <> trunc(v_previous_locked, 6)
    then
        raise exception 'INVALID_LOCKED_COLLATERAL';
    end if;

    v_stage :=
        'fetch current gold price';


    select
        current_rate.rate_to_usd
    into
        v_market_price
    from public.current_rates
        current_rate
    where lower(
        btrim(
            current_rate.code
        )
    ) = 'gold'
    limit 1;


    v_market_price :=
        coalesce(
            v_market_price,
            0
        );


    if v_market_price is null
       or v_market_price::text in ('NaN', 'Infinity', '-Infinity')
       or v_market_price <= 0 then
        raise exception
            'INVALID_MARKET_PRICE';
    end if;


    /*
     * ==========================================================
     * FETCH FISCAL PERIOD
     * ==========================================================
     */

    v_stage :=
        'fetch fiscal period';


    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;


    if not found
       or v_fiscal_year is null
       or v_period is null
    then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * FETCH DOCUMENT PREFIX
     * ==========================================================
     */

    v_stage :=
        'fetch document prefix';


    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );


    if v_document_prefix is null
       or btrim(
           v_document_prefix
       ) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * GENERATE DOCUMENT NUMBER
     * ==========================================================
     */

    v_stage :=
        'generate document number';


    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );


    /* Lock the whole active portfolio before posting any repayment.
     * Collateral is shared, so untouched loans also participate in the
     * required-pool calculation. All loans must use this USD portfolio. */
    v_stage := 'lock active loan portfolio';
    for v_loan in
        select l.* from public.loan as l
        where l.user_id = v_user.id
          and l.status = 'active'::public."LoanStatus"
        order by l.created_at, l.id
        for update
    loop
        if lower(btrim(v_loan.currency_code)) is distinct from v_currency
           or v_loan.country_code is distinct from v_user.country_code
        then
            raise exception 'LOAN_PORTFOLIO_CONTEXT_MISMATCH';
        end if;
        v_portfolio_ids := array_append(v_portfolio_ids, v_loan.id::text);
    end loop;

    /* Debt allocation is unchanged: oldest loan first, with interest
     * before principal within each loan. No collateral is released here. */
    v_stage :=
        'allocate loan repayment';


    for v_loan in
        select
            loan_record.*
        from public.loan
            loan_record
        where loan_record.user_id =
              v_user.id

          and loan_record.status =
              'active'::public."LoanStatus"

          and lower(
              btrim(
                  loan_record.currency_code
              )
          ) =
              v_currency

        order by
            loan_record.created_at asc,
            loan_record.id asc

        for update
    loop
        v_active_loan_found :=
            true;


        exit when
            v_remaining_payment <= 0;


        /*
         * ======================================================
         * CURRENT OUTSTANDING BALANCES
         * ======================================================
         */

        select
            greatest(
                coalesce(
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
                ),
                0
            ),

            greatest(
                coalesce(
                    sum(
                        coalesce(
                            loan_entry_record.debit_interest,
                            0
                        ) -
                        coalesce(
                            loan_entry_record.credit_interest,
                            0
                        )
                    ),
                    0
                ),
                0
            )

        into
            v_principal_outstanding,
            v_interest_outstanding

        from public.loan_entry
            loan_entry_record

        where loan_entry_record.loan_id =
              v_loan.id;


        if v_principal_outstanding::text in ('NaN', 'Infinity', '-Infinity')
           or v_interest_outstanding::text in ('NaN', 'Infinity', '-Infinity')
        then
            raise exception 'INVALID_LOAN_BALANCE';
        end if;

        if v_principal_outstanding <= 0
           and v_interest_outstanding <= 0
        then
            continue;
        end if;


        v_interest_paid :=
            0;

        v_principal_paid :=
            0;


        /*
         * ======================================================
         * PAY INTEREST FIRST
         * ======================================================
         */

        if v_interest_outstanding > 0
           and v_remaining_payment > 0
        then
            v_interest_paid :=
                least(
                    v_interest_outstanding,
                    v_remaining_payment
                );


            v_remaining_payment :=
                v_remaining_payment -
                v_interest_paid;


            v_total_interest_paid :=
                v_total_interest_paid +
                v_interest_paid;
        end if;


        /*
         * ======================================================
         * PAY PRINCIPAL SECOND
         * ======================================================
         */

        if v_principal_outstanding > 0
           and v_remaining_payment > 0
        then
            v_principal_paid :=
                least(
                    v_principal_outstanding,
                    v_remaining_payment
                );


            v_remaining_payment :=
                v_remaining_payment -
                v_principal_paid;


            v_total_principal_paid :=
                v_total_principal_paid +
                v_principal_paid;
        end if;


        if v_interest_paid <= 0
           and v_principal_paid <= 0
        then
            continue;
        end if;


        /*
         * ======================================================
         * CREATE REPAYMENT LOAN ENTRY
         * ======================================================
         */

        v_payments := v_payments || jsonb_build_array(jsonb_build_object(
            'loan_id', v_loan.id::text,
            'payment', v_principal_paid + v_interest_paid
        ));

        v_stage :=
            'create loan repayment entry';


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
            country_code
        )
        values (
            v_loan.id,
            v_fiscal_year,
            v_period,
            v_document_number,
            'repayment'::public."LoanEntryType",
            0,
            v_principal_paid,
            0,
            v_interest_paid,
            v_currency,
            v_user.country_code
        );


        /*
         * ======================================================
         * UPDATE LOAN SNAPSHOT
         * ======================================================
         */

        v_stage :=
            'update loan snapshot';


        perform public.update_loan_snapshot(
            v_loan.id,
            v_user.id,
            v_user.country_code,
            0::numeric,
            v_principal_paid,
            0::numeric,
            v_interest_paid,
            v_fiscal_year,
            v_period
        );


        /*
         * ======================================================
         * POST-REPAYMENT OUTSTANDING BALANCES
         * ======================================================
         */

        v_principal_remaining :=
            greatest(
                v_principal_outstanding -
                v_principal_paid,
                0
            );


        v_interest_remaining :=
            greatest(
                v_interest_outstanding -
                v_interest_paid,
                0
            );


        v_total_debt_remaining :=
            v_principal_remaining +
            v_interest_remaining;


        /*
         * ======================================================
         * CLOSE FULLY SETTLED LOAN
         * ======================================================
         *
         * Both principal AND interest must be zero before a loan
         * can be closed. Shared collateral is handled after allocation.
         */

        if v_principal_remaining <= 0
           and v_interest_remaining <= 0
        then
            v_stage :=
                'close loan';


            update public.loan
            set
                status =
                    'closed'::public."LoanStatus",

                updated_at =
                    now()

            where id =
                  v_loan.id

              and status =
                  'active'::public."LoanStatus";


            if not found then
                raise exception
                    'LOAN_CLOSE_FAILED';
            end if;


            v_closed_loans_count :=
                v_closed_loans_count +
                1;
        end if;

    end loop;


    /*
     * ==========================================================
     * VALIDATE REPAYMENT ALLOCATION
     * ==========================================================
     */

    if not v_active_loan_found then
        raise exception
            'NO_ACTIVE_LOANS';
    end if;


    if v_total_principal_paid <= 0
       and v_total_interest_paid <= 0
    then
        raise exception
            'NOTHING_TO_REPAY';
    end if;


    /*
     * Exact amount actually consumed by the repayment.
     */
    v_total_payment_applied :=
        v_total_principal_paid +
        v_total_interest_paid;


    /* ==========================================================
     * CALCULATE ONE POST-REPAYMENT REQUIRED POOL
     * ==========================================================
     * Read every loan that was active when this operation started,
     * including loans just closed and loans untouched by this payment.
     * Each loan uses its saved normal borrowing LTV, as top-up does.
     */
    v_stage := 'calculate post-repayment required collateral pool';
    foreach v_portfolio_id in array v_portfolio_ids
    loop
        select l.* into strict v_loan
        from public.loan as l where l.id::text = v_portfolio_id;

        select
            greatest(coalesce(sum(coalesce(e.debit_principal, 0) -
                                  coalesce(e.credit_principal, 0)), 0), 0),
            greatest(coalesce(sum(coalesce(e.debit_interest, 0) -
                                  coalesce(e.credit_interest, 0)), 0), 0)
        into v_principal_remaining, v_interest_remaining
        from public.loan_entry as e where e.loan_id = v_loan.id;

        if v_principal_remaining::text in ('NaN', 'Infinity', '-Infinity')
           or v_interest_remaining::text in ('NaN', 'Infinity', '-Infinity')
        then
            raise exception 'INVALID_LOAN_BALANCE';
        end if;
        v_total_debt_remaining := v_principal_remaining + v_interest_remaining;
        v_target_collateral := 0;
        if v_total_debt_remaining > 0 then
            v_target_ltv := v_loan.max_ltv_percent;
            if v_target_ltv is null
               or v_target_ltv::text in ('NaN', 'Infinity', '-Infinity')
               or v_target_ltv <= 0 or v_target_ltv >= 100
            then
                raise exception 'INVALID_LOAN_LTV_CONFIGURATION';
            end if;
            v_target_collateral := ceil(
                v_total_debt_remaining * 100 /
                (v_target_ltv * v_market_price) * 1000000
            ) / 1000000;
        end if;
        v_required_pool := v_required_pool + v_target_collateral;
        v_plan := v_plan || jsonb_build_array(jsonb_build_object(
            'loan_id', v_loan.id::text,
            'debt', v_total_debt_remaining,
            'required', v_target_collateral,
            'liquidation_ltv', v_loan.liquidation_ltv
        ));
    end loop;

    -- A shortfall means no release; repayment does not create collateral.
    v_total_collateral_unlock := trunc(
        greatest(v_previous_locked - v_required_pool, 0), 6
    );
    v_retained_pool := v_previous_locked - v_total_collateral_unlock;

    if v_retained_pool < least(v_previous_locked, v_required_pool)
       or v_total_collateral_unlock < 0
       or v_total_collateral_unlock > v_previous_locked
    then
        raise exception 'INVALID_COLLATERAL_POOL_RELEASE';
    end if;

    /* Current allocations are maintained separately from audit movements,
     * matching top-up's oldest-first redistribution of the actual pool.
     * Reallocation is not newly locked/released GOLD, so it creates no
     * collateral_entry movement. All allocations sum to the retained pool.
     */
    v_stage := 'redistribute retained collateral pool';
    v_remaining_pool := v_retained_pool;
    for v_plan_row in select value from jsonb_array_elements(v_plan)
    loop
        v_allocation := least(
            (v_plan_row ->> 'required')::numeric, v_remaining_pool
        );
        v_liquidation_price := 0;
        if (v_plan_row ->> 'debt')::numeric > 0 and v_allocation > 0 then
            v_target_ltv := (v_plan_row ->> 'liquidation_ltv')::numeric;
            if v_target_ltv is null
               or v_target_ltv::text in ('NaN', 'Infinity', '-Infinity')
               or v_target_ltv <= 0 or v_target_ltv > 100
            then
                raise exception 'INVALID_LIQUIDATION_LTV';
            end if;
            v_liquidation_price := trunc(
                (v_plan_row ->> 'debt')::numeric /
                (v_allocation * v_target_ltv / 100), 6
            );
        end if;
        update public.loan
        set collateral = v_allocation,
            liquidation_price = v_liquidation_price,
            updated_at = now()
        where id::text = v_plan_row ->> 'loan_id';
        if not found then
            raise exception 'LOAN_COLLATERAL_UPDATE_FAILED';
        end if;
        v_remaining_pool := v_remaining_pool - v_allocation;
    end loop;
    if v_remaining_pool <> 0 then
        raise exception 'COLLATERAL_POOL_ALLOCATION_MISMATCH';
    end if;

    /* Audit attribution: distribute the ONE actual pool release across
     * loans repaid by this document, in proportion to the payment applied.
     * These rows record actual release, not the new per-loan allocations.
     * The final row receives any six-decimal rounding remainder.
     */
    v_stage := 'post pooled collateral release entries';
    v_release_remaining := v_total_collateral_unlock;
    v_payment_remaining := v_total_payment_applied;
    for v_payment_row in select value from jsonb_array_elements(v_payments)
    loop
        if (v_payment_row ->> 'payment')::numeric = v_payment_remaining then
            v_release_part := v_release_remaining;
        else
            v_release_part := least(v_release_remaining, trunc(
                v_total_collateral_unlock *
                (v_payment_row ->> 'payment')::numeric /
                v_total_payment_applied, 6
            ));
        end if;
        if v_release_part > 0 then
            insert into public.collateral_entry (
                loan_id, document_number, debit, credit, country_code
            ) values (
                v_payment_row ->> 'loan_id', v_document_number,
                0, v_release_part, v_user.country_code
            );
        end if;
        v_release_sum := v_release_sum + v_release_part;
        v_release_remaining := v_release_remaining - v_release_part;
        v_payment_remaining := v_payment_remaining -
            (v_payment_row ->> 'payment')::numeric;
    end loop;
    if v_release_sum <> v_total_collateral_unlock
       or v_release_remaining <> 0 or v_payment_remaining <> 0
    then
        raise exception 'COLLATERAL_RELEASE_POSTING_MISMATCH';
    end if;

    /*
     * ==========================================================
     * RELEASE CUSTOMER COLLATERAL
     * ==========================================================
     */

    if v_total_collateral_unlock > 0 then
        v_stage :=
            'release collateral';


        update public.collateral
        set
            locked_tokens =
                locked_tokens -
                v_total_collateral_unlock,
            updated_at = now()

        where id = v_collateral.id
          and user_id = v_user.id
          and coalesce(
              locked_tokens,
              0
          ) >=
              v_total_collateral_unlock;


        if not found then
            raise exception
                'COLLATERAL_BALANCE_TOO_LOW';
        end if;


        /*
         * ======================================================
         * UPDATE COLLATERAL SNAPSHOT
         * ======================================================
         */

        v_stage :=
            'update collateral snapshot';


        perform public.update_collateral_snapshot(
            v_user.id,
            v_user.country_code,
            0::numeric,
            v_total_collateral_unlock,
            v_fiscal_year,
            v_period
        );
    end if;


    /*
     * ==========================================================
     * FETCH GL MAPPINGS
     * ==========================================================
     */

    v_stage :=
        'fetch GL mappings';


    select
        array_agg(
            mapping_record
        )
    into
        v_mappings
    from public.fetch_gl_mappings(
        v_transaction_type
    ) as mapping_record;


    if v_mappings is null
       or cardinality(
           v_mappings
       ) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * BUILD POSTING COMPONENTS
     * ==========================================================
     *
     * Total debit is the exact repayment consumed.
     *
     * Credits are split between:
     *
     * principal
     * interest
     */

    v_components :=
        array[
            row(
                'principal'::public."ComponentType",
                v_total_payment_applied,
                v_total_principal_paid
            )::public.posting_component
        ];


    if v_total_interest_paid > 0 then
        v_components :=
            array_append(
                v_components,
                row(
                    'loan_interest'::public."ComponentType",
                    0,
                    v_total_interest_paid
                )::public.posting_component
            );
    end if;


    /*
     * ==========================================================
     * CREATE FINANCIAL TRANSACTION
     * ==========================================================
     */

    v_stage :=
        'create financial transaction';


    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        v_reference,
        v_transaction_type,
        'Loan repayment for user ' ||
            v_user.id,
        v_user.id,
        v_total_payment_applied,
        v_currency,
        v_user.country_code
    )
    returning
        id
    into
        v_financial_transaction_id;


    /*
     * ==========================================================
     * POST FINANCIAL ENTRIES
     * ==========================================================
     */

    v_stage :=
        'post financial entries';


    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_user.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            v_transaction_type,

        p_created_by =>
            v_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_currency,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );


    /*
     * ==========================================================
     * MOVE CUSTOMER FUNDS TO TREASURY
     * ==========================================================
     *
     * Customer wallet debit =
     *
     *     v_total_payment_applied
     *
     * NOT:
     *
     *     v_payment_amount
     *
     * Therefore unused_payment never leaves the customer's
     * wallet.
     */

    v_stage :=
        'post wallet entries';


    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_treasury.id,

        p_sender_id =>
            v_user.id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            v_total_payment_applied,

        p_debit_amount =>
            v_total_payment_applied,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            v_user.country_code,

        p_audit_action_type =>
            'loan_repaid'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            null,

        p_sender_notification =>
            null
    );


    /*
     * ==========================================================
     * RETURN COMMITTED RESULT
     * ==========================================================
     */

    return query
    select
        true,

        v_document_number,

        to_char(
            round(
                v_total_principal_paid,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        to_char(
            round(
                v_total_interest_paid,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        to_char(
            round(
                v_total_collateral_unlock,
                6
            ),
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            round(
                v_remaining_payment,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        v_closed_loans_count,

        v_user.id,

        lower(
            btrim(
                v_user.country_code
            )
        ),

        v_currency,

        /*
         * Total amount actually applied against debt.
         */
        to_char(
            round(
                v_total_payment_applied,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        /*
         * Exact customer wallet debit.
         */
        to_char(
            round(
                v_total_payment_applied,
                2
            ),
            'FM999999999999999999999999990.00'
        );


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
                    'LOAN_REPAYMENT_FAILED at [%s]: %s',
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
                    'Check the Loan Repayment stage reported in the error'
                );

end;
$function$;

COMMIT;
