-- Full replacement of finalise_liquidation_accounting_job().
-- Fixes future collateral reductions to CREDIT, updates snapshots and
-- redistributes the retained user-wide pool. Existing result fields,
-- blockchain validation, saved-price checks, accounting and idempotency
-- are preserved. Adds three informational collateral totals to the JSON.
-- Does not rewrite existing entries or replay a completed liquidation.
-- A retained surplus is reported, not silently unlocked by this function.
BEGIN;

CREATE OR REPLACE FUNCTION public.finalise_liquidation_accounting_job(p_job_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_job public.liquidation_job%rowtype;
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_user public.users%rowtype;
    v_treasury public.users%rowtype;
    v_collateral public.collateral%rowtype;
    v_wallet_owners public.transaction_type_wallet_owner%rowtype;

    v_loan record;

    v_job_id text;
    v_locked_queue_id text;
    v_country_code text;
    v_blockchain_code text;
    v_sub_document_number text;

    v_planned_repayment numeric;
    v_planned_penalty numeric;
    v_planned_total_proceeds numeric;
    v_planned_collateral numeric;
    v_expected_collateral numeric;
    v_capped_repayment numeric;
    v_capped_penalty numeric;

    v_loan_principal numeric;
    v_loan_interest numeric;
    v_loan_debt numeric;

    v_payment numeric;
    v_interest_paid numeric;
    v_principal_paid numeric;
    v_collateral_used numeric;

    v_remaining_repayment numeric;
    v_remaining_collateral numeric;

    v_total_principal_paid numeric := 0;
    v_total_interest_paid numeric := 0;
    v_total_repayment numeric := 0;
    v_total_collateral numeric := 0;

    v_remaining_loan_principal numeric;
    v_remaining_loan_interest numeric;
    v_remaining_loan_debt numeric;
    v_remaining_loan_collateral numeric;
    v_liquidation_price numeric;
    v_portfolio_ids text[] := ARRAY[]::text[];
    v_portfolio_id text;
    v_target_ltv numeric;
    v_required_collateral numeric;
    v_retained_pool numeric;
    v_remaining_pool numeric;
    v_total_allocated numeric := 0;
    v_unallocated_pool numeric := 0;
    v_posted_credit numeric;
    v_posted_debit numeric;

    v_usd_mappings public.transaction_gl_mapping[];
    v_gold_mappings public.transaction_gl_mapping[];

    v_usd_components public.posting_component[] :=
        ARRAY[]::public.posting_component[];

    v_gold_components public.posting_component[];

    v_usd_transaction_id public.financial_transaction.id%type;
    v_gold_transaction_id public.financial_transaction.id%type;

    v_wallet_entry_count integer;
    v_notification_id text;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * AUTHORIZE SERVICE ROLE
     * ==========================================================
     */
    v_stage := 'authorize service role';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_stage := 'validate input';

    v_job_id := nullif(btrim(p_job_id), '');

    IF v_job_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_JOB_ID_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * LOCK JOB AND CHECK IDEMPOTENCY
     * ==========================================================
     */
    /*
     * Lock the linked queue before locking its job, matching claim,
     * submission, failure recording and confirmation.
     * Read the job only to resolve its queue; recheck linkage below
     * after both rows are locked. No linked queue is created here.
     */
    v_stage := 'lock liquidation queue before job';

    SELECT q.id
    INTO v_locked_queue_id
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = (
        SELECT j.blockchain_queue_id
        FROM public.liquidation_job AS j
        WHERE j.id = v_job_id
    )
    FOR UPDATE OF q;

    v_stage := 'lock liquidation job';

    SELECT j.*
    INTO v_job
    FROM public.liquidation_job AS j
    WHERE j.id::text = v_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_JOB_NOT_FOUND';
    END IF;

    IF v_job.status::text = 'completed' THEN
        RETURN jsonb_build_object(
            'success', true,
            'already_completed', true,
            'job_id', v_job.id,
            'document_number', v_job.document_number,
            'status', v_job.status
        );
    END IF;

    IF v_locked_queue_id IS NULL
       OR v_job.blockchain_queue_id IS DISTINCT FROM v_locked_queue_id
    THEN
        RAISE EXCEPTION 'LIQUIDATION_JOB_QUEUE_LINK_CHANGED_OR_MISSING';
    END IF;

    IF v_job.status::text <> 'accounting_processing' THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_NOT_ACCOUNTING_PROCESSING';
    END IF;

    v_country_code :=
        lower(nullif(btrim(v_job.country_code), ''));

    IF v_country_code IS NULL THEN
        RAISE EXCEPTION
            'LIQUIDATION_COUNTRY_CODE_NOT_FOUND';
    END IF;

    v_blockchain_code :=
        nullif(btrim(v_job.blockchain_code), '');

    IF v_blockchain_code IS NULL
       OR v_job.blockchain_code IS DISTINCT FROM
          lower(btrim(v_job.blockchain_code))
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_BLOCKCHAIN_CODE';
    END IF;

    IF nullif(btrim(v_job.document_number), '') IS NULL THEN
        RAISE EXCEPTION
            'LIQUIDATION_DOCUMENT_NUMBER_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * VALIDATE IMMUTABLE CALCULATION
     * ==========================================================
     */
    v_stage := 'validate liquidation amounts';

    IF v_job.gold_price IS NULL
       OR v_job.gold_price::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_job.gold_price <= 0
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_GOLD_PRICE';
    END IF;

    IF v_job.repayment_required IS NULL
       OR v_job.repayment_required::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_job.repayment_required <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_DEBT_REPAYMENT';
    END IF;

    IF v_job.penalty_amount IS NULL
       OR v_job.penalty_amount::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_job.penalty_amount < 0
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_PENALTY';
    END IF;

    IF v_job.total_required IS NULL
       OR v_job.total_required::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_job.total_required <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_TOTAL_PROCEEDS';
    END IF;

    IF v_job.collateral_required IS NULL
       OR v_job.collateral_required::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_job.collateral_required <= 0
    THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_COLLATERAL';
    END IF;

    v_planned_repayment :=
        trunc(v_job.repayment_required, 6);

    v_planned_penalty :=
        trunc(v_job.penalty_amount, 6);

    v_planned_total_proceeds :=
        trunc(v_job.total_required, 6);

    v_planned_collateral :=
        trunc(v_job.collateral_required, 6);

    IF v_planned_repayment <= 0
       OR v_planned_total_proceeds <= 0
       OR v_planned_collateral <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_ROUNDED_AMOUNTS';
    END IF;

    IF abs(
        v_planned_total_proceeds -
        (v_planned_repayment + v_planned_penalty)
    ) > 0.000001 THEN
        RAISE EXCEPTION
            'LIQUIDATION_TOTAL_PROCEEDS_MISMATCH';
    END IF;

    v_expected_collateral :=
        trunc(
            v_planned_total_proceeds / v_job.gold_price,
            6
        );

    IF abs(
        v_expected_collateral - v_planned_collateral
    ) > 0.000001 THEN
        /*
         * A blockchain-limited calculation starts with GOLD quantity.
         * Validate its forward calculation exactly, rather than dividing
         * rounded USD proceeds back into grams. Keep the transferred
         * quantity unchanged and retain the existing proceeds-first check
         * for ordinary, uncapped calculations.
         */
        IF v_job.penalty_rate IS NULL
           OR v_job.penalty_rate::text IN ('NaN', 'Infinity', '-Infinity')
           OR v_job.penalty_rate < 0
        THEN
            RAISE EXCEPTION 'INVALID_LIQUIDATION_PENALTY_RATE';
        END IF;

        v_capped_repayment := trunc(
            least(
                v_job.total_debt,
                trunc(v_planned_collateral * v_job.gold_price, 6) /
                    (1 + v_job.penalty_rate)
            ),
            6
        );
        v_capped_penalty := trunc(
            v_capped_repayment * v_job.penalty_rate, 6
        );

        IF v_planned_repayment IS DISTINCT FROM v_capped_repayment
           OR v_planned_penalty IS DISTINCT FROM v_capped_penalty
           OR v_planned_total_proceeds IS DISTINCT FROM
              trunc(v_capped_repayment + v_capped_penalty, 6)
           OR v_planned_total_proceeds >
              v_planned_collateral * v_job.gold_price
        THEN
            RAISE EXCEPTION 'LIQUIDATION_COLLATERAL_PRICE_MISMATCH';
        END IF;
    END IF;

    /*
     * ==========================================================
     * LOCK AND VALIDATE CONFIRMED BLOCKCHAIN QUEUE
     * ==========================================================
     */
    v_stage := 'validate blockchain confirmation';

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_locked_queue_id
      AND q.liquidation_job_id = v_job.id::text;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF v_queue.status::text <> 'confirmed'
       OR v_queue.tx_hash IS NULL
       OR v_queue.tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
       OR v_queue.confirmed_at IS NULL
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_NOT_CONFIRMED';
    END IF;

    IF v_queue.blockchain_code IS DISTINCT FROM
       v_blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_CODE_MISMATCH';
    END IF;

    IF (v_queue.signed_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    IF v_queue.user_id IS DISTINCT FROM v_job.user_id THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_USER_MISMATCH';
    END IF;

    IF lower(btrim(v_queue.country_code))
       IS DISTINCT FROM v_country_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_COUNTRY_MISMATCH';
    END IF;

    IF v_queue.document_number IS DISTINCT FROM
       v_job.document_number
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_DOCUMENT_MISMATCH';
    END IF;

    IF v_queue.fiscal_year IS DISTINCT FROM v_job.fiscal_year
       OR v_queue.period IS DISTINCT FROM v_job.period
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_FISCAL_PERIOD_MISMATCH';
    END IF;

    IF v_queue.debt_repayment_amount IS NULL
       OR v_queue.penalty_amount IS NULL
       OR v_queue.total_liquidation_proceeds IS NULL
       OR v_queue.collateral IS NULL
       OR v_queue.gold_price IS NULL
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_AMOUNTS_REQUIRED';
    END IF;

    IF v_queue.debt_repayment_amount::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_queue.penalty_amount::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_queue.total_liquidation_proceeds::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_queue.collateral::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_queue.gold_price::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_BLOCKCHAIN_AMOUNTS';
    END IF;

    IF abs(
        trunc(v_queue.debt_repayment_amount, 6) -
        v_planned_repayment
    ) > 0.000001 THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_REPAYMENT_MISMATCH';
    END IF;

    IF abs(
        trunc(v_queue.penalty_amount, 6) -
        v_planned_penalty
    ) > 0.000001 THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_PENALTY_MISMATCH';
    END IF;

    IF abs(
        trunc(v_queue.total_liquidation_proceeds, 6) -
        v_planned_total_proceeds
    ) > 0.000001 THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_PROCEEDS_MISMATCH';
    END IF;

    /*
     * Debit the exact GOLD quantity transferred on-chain.
     */
    IF v_queue.collateral IS DISTINCT FROM
       v_planned_collateral
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_COLLATERAL_MISMATCH';
    END IF;

    IF abs(
        trunc(v_queue.gold_price, 6) -
        trunc(v_job.gold_price, 6)
    ) > 0.000001 THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_GOLD_PRICE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN AUDIT ROW
     * ==========================================================
     */
    v_stage := 'validate blockchain audit transaction';

    PERFORM 1
    FROM public.blockchain_transaction AS bt
    WHERE lower(btrim(bt.tx_hash)) =
          lower(btrim(v_queue.tx_hash))
      AND bt.transaction_type =
          'loan_liquidation'::public."TransactionType"
      AND lower(btrim(bt.country_code)) = v_country_code
      AND bt.chain = v_blockchain_code
      AND bt.document_number = v_job.document_number
      AND bt.reference = v_job.document_number
      AND lower(bt.sender) =
          lower(v_queue.sender_wallet_address)
      AND lower(bt.receiver) =
          lower(v_queue.receiver_wallet_address)
      AND bt.currency_code = 'gold'
      AND bt.quantity = v_planned_collateral
      AND bt.status =
          'completed'::public."BlockchainTxStatus"
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TRANSACTION_NOT_RECORDED';
    END IF;

    /*
     * ==========================================================
     * FETCH USER AND COUNTRY TREASURY
     * ==========================================================
     */
    v_stage := 'fetch liquidation user';

    SELECT u.*
    INTO v_user
    FROM public.users AS u
    WHERE u.id = v_job.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_USER_NOT_FOUND';
    END IF;

    v_stage := 'fetch country treasury';

    SELECT t.*
    INTO v_treasury
    FROM public.fetch_country_treasury(
        v_country_code
    ) AS t;

    IF NOT FOUND OR v_treasury.id IS NULL THEN
        RAISE EXCEPTION 'COUNTRY_TREASURY_NOT_FOUND';
    END IF;

    IF v_queue.treasury_id IS DISTINCT FROM
       v_treasury.id
    THEN
        RAISE EXCEPTION 'LIQUIDATION_TREASURY_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * LOCK USER'S TOTAL COLLATERAL
     * ==========================================================
     */
    v_stage := 'lock collateral balance';

    SELECT c.*
    INTO STRICT v_collateral
    FROM public.collateral AS c
    WHERE c.user_id = v_job.user_id
      AND lower(btrim(c.country_code)) = v_country_code
    FOR UPDATE;

    IF v_collateral.locked_tokens IS NULL
       OR v_collateral.locked_tokens::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_collateral.locked_tokens < v_planned_collateral
    THEN
        RAISE EXCEPTION 'INSUFFICIENT_LOCKED_COLLATERAL';
    END IF;

    /*
     * ==========================================================
     * CHECK ACCOUNTING REPLAY
     * ==========================================================
     */
    v_stage := 'check accounting replay';

    v_sub_document_number :=
        v_job.document_number || '-01';

    PERFORM 1
    FROM public.financial_transaction AS ft
    WHERE ft.document_number IN (
        v_job.document_number,
        v_sub_document_number
    )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_ACCOUNTING_DOCUMENT_ALREADY_EXISTS';
    END IF;

    -- Lock and remember the full active portfolio, including loans that
    -- this liquidation will settle and loans it will leave untouched.
    v_stage := 'lock active loan portfolio';
    FOR v_loan IN
        SELECT l.* FROM public.loan AS l
        WHERE l.user_id = v_job.user_id
          AND l.status = 'active'::public."LoanStatus"
        ORDER BY l.created_at, l.id
        FOR UPDATE
    LOOP
        IF lower(btrim(v_loan.country_code)) IS DISTINCT FROM v_country_code
           OR lower(btrim(v_loan.currency_code)) IS DISTINCT FROM 'usd'
        THEN
            RAISE EXCEPTION 'LIQUIDATION_LOAN_PORTFOLIO_CONTEXT_MISMATCH';
        END IF;
        v_portfolio_ids := array_append(v_portfolio_ids, v_loan.id::text);
    END LOOP;

    v_remaining_repayment := v_planned_repayment;
    v_remaining_collateral := v_planned_collateral;

    /*
     * ==========================================================
     * ALLOCATE REPAYMENT: OLDEST LOAN FIRST
     * INTEREST BEFORE PRINCIPAL
     * ==========================================================
     */
    v_stage := 'allocate loan repayment';

    FOR v_loan IN
        SELECT l.*
        FROM public.loan AS l
        WHERE l.user_id = v_job.user_id
          AND lower(btrim(l.country_code)) = v_country_code
          AND l.status = 'active'::public."LoanStatus"
        ORDER BY l.created_at, l.id
        FOR UPDATE
    LOOP
        EXIT WHEN v_remaining_repayment <= 0;

        SELECT
            greatest(
                coalesce(
                    sum(
                        coalesce(e.debit_principal, 0) -
                        coalesce(e.credit_principal, 0)
                    ),
                    0
                ),
                0
            ),
            greatest(
                coalesce(
                    sum(
                        coalesce(e.debit_interest, 0) -
                        coalesce(e.credit_interest, 0)
                    ),
                    0
                ),
                0
            )
        INTO v_loan_principal, v_loan_interest
        FROM public.loan_entry AS e
        WHERE e.loan_id = v_loan.id;

        IF v_loan_principal::text IN ('NaN', 'Infinity', '-Infinity')
           OR v_loan_interest::text IN ('NaN', 'Infinity', '-Infinity')
        THEN
            RAISE EXCEPTION 'INVALID_LIQUIDATION_LOAN_BALANCE';
        END IF;

        v_loan_principal :=
            trunc(coalesce(v_loan_principal, 0), 6);

        v_loan_interest :=
            trunc(coalesce(v_loan_interest, 0), 6);

        v_loan_debt :=
            trunc(v_loan_principal + v_loan_interest, 6);

        IF v_loan_debt <= 0 THEN
            UPDATE public.loan
            SET
                status = 'liquidated'::public."LoanStatus",
                collateral = 0,
                liquidation_price = 0,
                updated_at = now()
            WHERE id = v_loan.id;

            CONTINUE;
        END IF;

        v_payment :=
            trunc(
                least(v_loan_debt, v_remaining_repayment),
                6
            );

        v_interest_paid :=
            trunc(least(v_loan_interest, v_payment), 6);

        v_principal_paid :=
            trunc(
                least(
                    v_loan_principal,
                    v_payment - v_interest_paid
                ),
                6
            );

        v_payment :=
            trunc(v_interest_paid + v_principal_paid, 6);

        IF v_payment <= 0 THEN
            CONTINUE;
        END IF;

        /*
         * Attribute consumed GOLD, including the penalty portion, to
         * repaid loans in proportion to debt repayment. These audit rows
         * record the real pool reduction, not the current loan allocation.
         */
        IF v_payment = v_remaining_repayment THEN
            v_collateral_used := v_remaining_collateral;
        ELSE
            v_collateral_used :=
                trunc(
                    v_planned_collateral *
                    v_payment /
                    v_planned_repayment,
                    6
                );

            v_collateral_used :=
                least(
                    v_collateral_used,
                    v_remaining_collateral
                );
        END IF;

        INSERT INTO public.loan_entry (
            loan_id,
            fiscal_year,
            period,
            country_code,
            entry_type,
            document_number,
            currency_code,
            debit_principal,
            credit_principal,
            debit_interest,
            credit_interest
        )
        VALUES (
            v_loan.id,
            v_job.fiscal_year,
            v_job.period,
            v_country_code,
            'liquidation'::public."LoanEntryType",
            v_job.document_number,
            'usd',
            0,
            v_principal_paid,
            0,
            v_interest_paid
        );

        PERFORM public.update_loan_snapshot(
            v_loan.id, v_job.user_id, v_country_code,
            0::numeric, v_principal_paid, 0::numeric, v_interest_paid,
            v_job.fiscal_year, v_job.period
        );

        INSERT INTO public.collateral_entry (
            loan_id,
            document_number,
            country_code,
            debit,
            credit
        )
        VALUES (
            v_loan.id,
            v_job.document_number,
            v_country_code,
            0,
            v_collateral_used
        );

        v_total_principal_paid :=
            trunc(v_total_principal_paid + v_principal_paid, 6);

        v_total_interest_paid :=
            trunc(v_total_interest_paid + v_interest_paid, 6);

        v_total_repayment :=
            trunc(v_total_repayment + v_payment, 6);

        v_total_collateral :=
            trunc(v_total_collateral + v_collateral_used, 6);

        v_remaining_repayment :=
            trunc(v_remaining_repayment - v_payment, 6);

        v_remaining_collateral :=
            trunc(v_remaining_collateral - v_collateral_used, 6);

        /*
         * A partially repaid loan remains active.
         */
        IF v_payment = v_loan_debt THEN
            UPDATE public.loan
            SET
                status = 'liquidated'::public."LoanStatus",
                collateral = 0,
                liquidation_price = 0,
                updated_at = now()
            WHERE id = v_loan.id;
        END IF;
    END LOOP;

    /*
     * All amounts are already at six decimals.
     * Require complete allocation, including the final unit.
     */
    IF v_remaining_repayment <> 0 THEN
        RAISE EXCEPTION
            'LIQUIDATION_POSITION_CHANGED_REPAYMENT_REMAINING_%',
            v_remaining_repayment;
    END IF;

    IF v_remaining_collateral <> 0
       OR v_total_collateral <> v_planned_collateral
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_COLLATERAL_TOTAL_MISMATCH';
    END IF;

    IF v_total_repayment <> v_planned_repayment THEN
        RAISE EXCEPTION
            'LIQUIDATION_REPAYMENT_TOTAL_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * USD FINANCIAL POSTING
     * ==========================================================
     */
    v_stage := 'fetch usd liquidation mappings';

    SELECT array_agg(m ORDER BY m.component_type)
    INTO v_usd_mappings
    FROM public.fetch_gl_mappings(
        'loan_liquidation'::public."TransactionType"
    ) AS m;

    IF v_usd_mappings IS NULL
       OR cardinality(v_usd_mappings) = 0
    THEN
        RAISE EXCEPTION
            'LOAN_LIQUIDATION_GL_MAPPINGS_NOT_FOUND';
    END IF;

    v_usd_components :=
        array_append(
            v_usd_components,
            ROW(
                'principal'::public."ComponentType",
                v_planned_total_proceeds,
                v_total_principal_paid
            )::public.posting_component
        );

    IF v_total_interest_paid > 0 THEN
        v_usd_components :=
            array_append(
                v_usd_components,
                ROW(
                    'loan_interest'::public."ComponentType",
                    0,
                    v_total_interest_paid
                )::public.posting_component
            );
    END IF;

    IF v_planned_penalty > 0 THEN
        v_usd_components :=
            array_append(
                v_usd_components,
                ROW(
                    'liquidation_fee'::public."ComponentType",
                    0,
                    v_planned_penalty
                )::public.posting_component
            );
    END IF;

    v_usd_components :=
        public.validate_components(v_usd_components);

    v_stage := 'create usd financial transaction';

    INSERT INTO public.financial_transaction (
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
    VALUES (
        v_job.document_number,
        v_job.document_number,
        v_job.fiscal_year,
        v_job.period,
        'loan_liquidation'::public."TransactionType",
        format(
            'Loan liquidation for user %s',
            v_job.user_id
        ),
        'system',
        v_planned_total_proceeds,
        'usd',
        v_country_code
    )
    RETURNING id INTO v_usd_transaction_id;

    v_stage := 'post usd financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number => v_job.document_number,
        p_country_code => v_country_code,
        p_transaction_id => v_usd_transaction_id,
        p_transaction_type =>
            'loan_liquidation'::public."TransactionType",
        p_created_by => 'system',
        p_components => v_usd_components,
        p_mappings => v_usd_mappings,
        p_currency_code => 'usd',
        p_fiscal_year => v_job.fiscal_year,
        p_period => v_job.period,
        p_reference => v_job.document_number,
        p_deposit_type => NULL
    );

    /*
     * ==========================================================
     * GOLD FINANCIAL POSTING
     * ==========================================================
     */
    v_stage := 'fetch gold liquidation mappings';

    SELECT array_agg(m ORDER BY m.component_type)
    INTO v_gold_mappings
    FROM public.fetch_gl_mappings(
        'loan_liquidation_sub_tx'::public."TransactionType"
    ) AS m;

    IF v_gold_mappings IS NULL
       OR cardinality(v_gold_mappings) = 0
    THEN
        RAISE EXCEPTION
            'LOAN_LIQUIDATION_GOLD_GL_MAPPINGS_NOT_FOUND';
    END IF;

    v_gold_components :=
        public.build_posting_components(
            'loan_liquidation_sub_tx'::public."TransactionType",
            v_total_collateral,
            v_gold_mappings,
            v_country_code,
            'gold',
            false
        );

    IF v_gold_components IS NULL
       OR cardinality(v_gold_components) = 0
    THEN
        RAISE EXCEPTION
            'LOAN_LIQUIDATION_GOLD_COMPONENTS_NOT_FOUND';
    END IF;

    v_gold_components :=
        public.validate_components(v_gold_components);

    v_stage := 'create gold financial transaction';

    INSERT INTO public.financial_transaction (
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
    VALUES (
        v_sub_document_number,
        v_sub_document_number,
        v_job.fiscal_year,
        v_job.period,
        'loan_liquidation_sub_tx'::public."TransactionType",
        format(
            'Confirmed Gold collateral liquidation for user %s on %s',
            v_job.user_id,
            v_blockchain_code
        ),
        'system',
        v_total_collateral,
        'gold',
        v_country_code
    )
    RETURNING id INTO v_gold_transaction_id;

    v_stage := 'post gold financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number => v_sub_document_number,
        p_country_code => v_country_code,
        p_transaction_id => v_gold_transaction_id,
        p_transaction_type =>
            'loan_liquidation_sub_tx'::public."TransactionType",
        p_created_by => 'system',
        p_components => v_gold_components,
        p_mappings => v_gold_mappings,
        p_currency_code => 'gold',
        p_fiscal_year => v_job.fiscal_year,
        p_period => v_job.period,
        p_reference => v_sub_document_number,
        p_deposit_type => NULL
    );

    /*
     * ==========================================================
     * POST WALLETS ON THE SAVED BLOCKCHAIN
     * ==========================================================
     */
    v_stage := 'fetch wallet owner configuration';

    SELECT o.*
    INTO v_wallet_owners
    FROM public.fetch_transaction_type_wallet_owner(
        'loan_liquidation_sub_tx'::public."TransactionType"
    ) AS o;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LOAN_LIQUIDATION_WALLET_OWNER_NOT_FOUND';
    END IF;

    v_stage := 'post gold wallet entries';

    SELECT
        r.wallet_entry_count,
        r.receiver_notification_id
    INTO
        v_wallet_entry_count,
        v_notification_id
    FROM public.post_wallet_entries(
        p_fiscal_year => v_job.fiscal_year,
        p_period => v_job.period,
        p_document_number => v_sub_document_number,
        p_reference => v_sub_document_number,
        p_receiver_id => v_treasury.id,
        p_sender_id => v_job.user_id,
        p_transaction_type =>
            'loan_liquidation_sub_tx'::public."TransactionType",
        p_credit_amount => v_total_collateral,
        p_debit_amount => v_total_collateral,
        p_sender_wallet_owner =>
            v_wallet_owners.sender_wallet_owner,
        p_receiver_wallet_owner =>
            v_wallet_owners.receiver_wallet_owner,
        p_currency_code => 'gold',
        p_country_code => v_country_code,
        p_audit_action_type =>
            v_wallet_owners.audit_action_type,
        p_treasury_id => v_treasury.id,
        p_fee_amount => 0,
        p_ip_address => NULL,
        p_receiver_notification => NULL,
        p_sender_notification => NULL,
        p_blockchain_code => v_blockchain_code
    ) AS r;

    IF coalesce(v_wallet_entry_count, 0) < 2 THEN
        RAISE EXCEPTION
            'LIQUIDATION_GOLD_WALLET_POSTING_FAILED';
    END IF;

    /*
     * ==========================================================
     * REDUCE TOTAL LOCKED COLLATERAL
     * ==========================================================
     */
    v_stage := 'reduce locked collateral';

    UPDATE public.collateral
    SET locked_tokens =
        locked_tokens - v_total_collateral,
        updated_at = now()
    WHERE id = v_collateral.id
      AND user_id = v_job.user_id
      AND lower(btrim(country_code)) = v_country_code
      AND locked_tokens >= v_total_collateral;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'COLLATERAL_BALANCE_UPDATE_FAILED';
    END IF;

    /* Loan and collateral snapshots follow the same debit/credit
     * convention as disbursement, repayment and top-up. */
    v_stage := 'validate collateral release audit';
    SELECT coalesce(sum(e.credit), 0), coalesce(sum(e.debit), 0)
    INTO v_posted_credit, v_posted_debit
    FROM public.collateral_entry AS e
    WHERE e.document_number = v_job.document_number;
    IF v_posted_credit <> v_total_collateral OR v_posted_debit <> 0 THEN
        RAISE EXCEPTION 'LIQUIDATION_COLLATERAL_AUDIT_MISMATCH';
    END IF;

    v_stage := 'update collateral snapshot';
    PERFORM public.update_collateral_snapshot(
        v_job.user_id, v_country_code, 0::numeric, v_total_collateral,
        v_job.fiscal_year, v_job.period
    );

    /* Redistribute only GOLD retained in the actual user-wide pool.
     * Never infer current loan allocations from per-loan collateral-entry
     * sums: historical top-ups redistribute without posting pool movement.
     * Use the saved settlement price, not a later market-price change.
     */
    v_stage := 'redistribute retained collateral pool';
    v_retained_pool := v_collateral.locked_tokens - v_total_collateral;
    v_remaining_pool := v_retained_pool;
    FOREACH v_portfolio_id IN ARRAY v_portfolio_ids
    LOOP
        SELECT l.* INTO STRICT v_loan
        FROM public.loan AS l WHERE l.id::text = v_portfolio_id;

        SELECT
            greatest(coalesce(sum(coalesce(e.debit_principal, 0) -
                                  coalesce(e.credit_principal, 0)), 0), 0),
            greatest(coalesce(sum(coalesce(e.debit_interest, 0) -
                                  coalesce(e.credit_interest, 0)), 0), 0)
        INTO v_remaining_loan_principal, v_remaining_loan_interest
        FROM public.loan_entry AS e WHERE e.loan_id = v_loan.id;

        IF v_remaining_loan_principal::text IN ('NaN', 'Infinity', '-Infinity')
           OR v_remaining_loan_interest::text IN ('NaN', 'Infinity', '-Infinity')
        THEN
            RAISE EXCEPTION 'INVALID_LIQUIDATION_LOAN_BALANCE';
        END IF;
        v_remaining_loan_debt :=
            v_remaining_loan_principal + v_remaining_loan_interest;
        v_required_collateral := 0;
        IF v_remaining_loan_debt > 0 THEN
            IF v_loan.status::text <> 'active' THEN
                RAISE EXCEPTION 'LIQUIDATED_LOAN_STILL_HAS_DEBT';
            END IF;
            v_target_ltv := v_loan.max_ltv_percent;
            IF v_target_ltv IS NULL
               OR v_target_ltv::text IN ('NaN', 'Infinity', '-Infinity')
               OR v_target_ltv <= 0 OR v_target_ltv >= 100
            THEN
                RAISE EXCEPTION 'INVALID_LOAN_LTV_CONFIGURATION';
            END IF;
            v_required_collateral := ceil(
                v_remaining_loan_debt * 100 /
                (v_target_ltv * v_job.gold_price) * 1000000
            ) / 1000000;
        END IF;

        v_remaining_loan_collateral := least(
            v_required_collateral, v_remaining_pool
        );
        v_liquidation_price := 0;
        IF v_remaining_loan_debt > 0 AND v_remaining_loan_collateral > 0 THEN
            IF v_loan.liquidation_ltv IS NULL
               OR v_loan.liquidation_ltv::text IN ('NaN', 'Infinity', '-Infinity')
               OR v_loan.liquidation_ltv <= 0 OR v_loan.liquidation_ltv > 100
            THEN
                RAISE EXCEPTION 'INVALID_LIQUIDATION_LTV';
            END IF;
            v_liquidation_price := trunc(
                v_remaining_loan_debt /
                (v_remaining_loan_collateral * v_loan.liquidation_ltv / 100), 6
            );
        END IF;

        UPDATE public.loan
        SET collateral = v_remaining_loan_collateral,
            liquidation_price = v_liquidation_price,
            updated_at = now()
        WHERE id = v_loan.id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'LOAN_COLLATERAL_UPDATE_FAILED';
        END IF;
        v_total_allocated := v_total_allocated + v_remaining_loan_collateral;
        v_remaining_pool := v_remaining_pool - v_remaining_loan_collateral;
    END LOOP;

    -- Surplus remains in the shared pool; do not silently release more GOLD
    -- than this confirmed liquidation instruction consumed. Report it for
    -- separate release handling rather than assigning it to a settled loan.
    v_unallocated_pool := v_remaining_pool;
    IF v_unallocated_pool < 0
       OR v_total_allocated + v_unallocated_pool <> v_retained_pool
    THEN
        RAISE EXCEPTION 'LIQUIDATION_COLLATERAL_POOL_ALLOCATION_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * COMPLETE AFTER ALL POSTINGS SUCCEED
     * ==========================================================
     */
    v_stage := 'complete liquidation job';

    UPDATE public.liquidation_job
    SET
        status = 'completed'::public."LiquidationJobStatus",
        completed_at = now(),
        accounting_started_at = NULL,
        error_message = NULL
    WHERE id = v_job.id
      AND status::text = 'accounting_processing'
      AND blockchain_code = v_blockchain_code
    RETURNING * INTO v_job;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_COMPLETION_FAILED';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'already_completed', false,
        'job_id', v_job.id,
        'document_number', v_job.document_number,
        'blockchain_code', v_blockchain_code,
        'blockchain_tx_hash', v_queue.tx_hash,
        'principal_paid',
            trim_scale(v_total_principal_paid)::text,
        'interest_paid',
            trim_scale(v_total_interest_paid)::text,
        'debt_repayment',
            trim_scale(v_total_repayment)::text,
        'penalty_amount',
            trim_scale(v_planned_penalty)::text,
        'total_proceeds',
            trim_scale(v_planned_total_proceeds)::text,
        'collateral_transferred',
            trim_scale(v_total_collateral)::text,
        'remaining_locked_collateral', trim_scale(v_retained_pool)::text,
        'allocated_collateral', trim_scale(v_total_allocated)::text,
        'unallocated_locked_collateral', trim_scale(v_unallocated_pool)::text,
        'status', v_job.status
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'LIQUIDATION_ACCOUNTING_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the liquidation accounting stage'
            );
END;
$function$;

COMMIT;
