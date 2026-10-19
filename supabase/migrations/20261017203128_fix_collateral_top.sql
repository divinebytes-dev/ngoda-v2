BEGIN;
CREATE OR REPLACE FUNCTION public.execute_additional_collateral(p_user_id text, p_requested_collateral text, p_token_balance text, p_reference text)
 RETURNS TABLE(success boolean, collateral_required boolean, requested_collateral text, collateral_added text, unused_collateral text, remaining_required_collateral text, previous_locked_collateral text, new_locked_collateral text, loans_adjusted integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text :=
        'initialization';

    v_user
        public.users%rowtype;

    v_collateral
        public.collateral%rowtype;

    v_loan
        public.loan%rowtype;

    v_reference text;

    /*
     * Maximum amount authorised by the user for this
     * collateral top-up.
     */
    v_requested_collateral numeric;

    /*
     * Current blockchain gold balance supplied by the
     * authenticated Edge Function.
     */
    v_total_tokens numeric;

    /*
     * Gold currently available outside the locked pool.
     */
    v_available_tokens numeric := 0;

    /*
     * Current USD gold price.
     */
    v_gold_price numeric := 0;

    /*
     * Per-loan outstanding exposure.
     */
    v_principal numeric := 0;
    v_interest numeric := 0;
    v_exposure numeric := 0;

    /*
     * Target LTV configured on each loan.
     *
     * Stored as:
     *
     * 60.00
     *
     * and converted to:
     *
     * 0.60
     *
     * during the collateral calculation.
     */
    v_target_ltv numeric := 0;

    /*
     * Current required collateral for one loan at:
     *
     * - current outstanding exposure;
     * - current gold price;
     * - configured target LTV.
     */
    v_target_collateral numeric := 0;

    /*
     * Total gold currently required to cover every
     * active loan at its target LTV.
     *
     * IMPORTANT:
     *
     * This is the required SIZE OF THE POOL.
     *
     * It is not the additional collateral shortage.
     */
    v_total_required_pool numeric := 0;

    /*
     * Additional gold required before and after this
     * operation.
     */
    v_collateral_shortage numeric := 0;
    v_remaining_required numeric := 0;

    /*
     * Actual collateral added by this operation.
     *
     * This can be less than the amount authorised by
     * the user when the complete authorised amount is
     * not required.
     */
    v_collateral_added numeric := 0;

    /*
     * Consolidated collateral balances.
     */
    v_previous_locked numeric := 0;
    v_new_locked numeric := 0;

    /*
     * Allocation of the actual consolidated pool across
     * individual active loans.
     */
    v_remaining_pool numeric := 0;
    v_allocation numeric := 0;

    /*
     * When reallocating the pool, distinguish gold that
     * already existed in the pool from NEW gold added by
     * this operation.
     *
     * Only the new portion creates collateral_entry rows.
     */
    v_existing_pool_remaining numeric := 0;
    v_new_gold_remaining numeric := 0;
    v_existing_allocation numeric := 0;
    v_new_allocation numeric := 0;

    /*
     * Existing loan.collateral value before synchronising
     * the current allocation.
     */
    v_previous_loan_allocation numeric := 0;

    v_loans_adjusted integer := 0;
    v_posted_debits numeric := 0;
    v_liquidation_price numeric := 0;

    /*
     * Snapshot period.
     */
    v_fiscal_year integer;
    v_period integer;

    /*
     * Error diagnostics.
     */
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;

begin
    /*
     * ==========================================================
     * AUTHENTICATION / AUTHORIZATION
     * ==========================================================
     */
    v_stage :=
        'authorize customer';

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
    end if;
    if nullif(btrim(p_user_id), '') is null then
        raise exception 'USER_ID_REQUIRED';
    end if;


    if not public.user_has_role(
        p_user_id,
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
          p_user_id
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
     * PARSE REQUESTED COLLATERAL
     * ==========================================================
     */
    v_stage :=
        'parse requested collateral';


    begin
        v_requested_collateral :=
            nullif(
                btrim(
                    p_requested_collateral
                ),
                ''
            )::numeric;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_COLLATERAL_AMOUNT';
    end;


    if v_requested_collateral is null
       or v_requested_collateral::text in ('NaN', 'Infinity', '-Infinity')
       or v_requested_collateral <= 0
    then
        raise exception
            'INVALID_COLLATERAL_AMOUNT';
    end if;


    /*
     * collateral_entry supports six decimal places.
     *
     * Do not silently modify the quantity authorised by
     * the user's signed request.
     */
    if v_requested_collateral <>
       trunc(
           v_requested_collateral,
           6
       )
    then
        raise exception
            'INVALID_COLLATERAL_PRECISION';
    end if;


    /*
     * ==========================================================
     * PARSE BLOCKCHAIN TOKEN BALANCE
     * ==========================================================
     */
    v_stage :=
        'parse token balance';


    begin
        v_total_tokens :=
            coalesce(
                nullif(
                    btrim(
                        p_token_balance
                    ),
                    ''
                ),
                '0'
            )::numeric;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end;


    if v_total_tokens::text in ('NaN', 'Infinity', '-Infinity')
       or v_total_tokens < 0 then
        raise exception
            'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end if;


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
     * REPLAY PROTECTION
     * ==========================================================
     */
    v_stage :=
        'lock collateral reference';


    perform
        pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                v_reference,
                0
            )
        );


    perform 1
    from public.collateral_entry
        collateral_entry_record
    join public.loan
        loan_record
      on loan_record.id =
         collateral_entry_record.loan_id
    where collateral_entry_record.reference =
          v_reference
      and loan_record.user_id =
          v_user.id
    limit 1;


    if found then
        raise exception using
            errcode =
                '23505',
            message =
                'TRANSACTION_REPLAY';
    end if;


    /*
     * ==========================================================
     * ENSURE CONSOLIDATED COLLATERAL ROW EXISTS
     * ==========================================================
     */
    v_stage := 'lock loan position';
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('loan-position:' || v_user.id, 0)
    );
    if exists (
        select 1 from public.liquidation_job as j
        where j.user_id = v_user.id
          and j.status::text not in ('completed', 'cancelled')
    ) then
        raise exception 'LOAN_POSITION_LIQUIDATION_IN_PROGRESS';
    end if;

    v_stage :=
        'create collateral row';


    insert into public.collateral (
        user_id,
        locked_tokens,
        country_code
    )
    values (
        v_user.id,
        0,
        v_user.country_code
    )
    on conflict (
        user_id
    )
    do nothing;


    /*
     * ==========================================================
     * LOCK CONSOLIDATED COLLATERAL
     * ==========================================================
     *
     * collateral.locked_tokens is the authoritative quantity
     * of gold currently locked for the user's loan portfolio.
     * ==========================================================
     */
    v_stage :=
        'lock collateral row';


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


    v_previous_locked := v_collateral.locked_tokens;
    if v_previous_locked is null
       or v_previous_locked::text in ('NaN', 'Infinity', '-Infinity')
       or v_previous_locked < 0
       or v_previous_locked <> trunc(v_previous_locked, 6)
    then
        raise exception 'INVALID_LOCKED_COLLATERAL';
    end if;

    /*
     * ==========================================================
     * LOCK ACTIVE LOANS
     * ==========================================================
     *
     * The portfolio must remain stable while:
     *
     * - exposure is calculated;
     * - pooled collateral is increased;
     * - the pool is redistributed across loans.
     *
     * Oldest loan first is also the allocation order.
     * ==========================================================
     */
    v_stage :=
        'lock active loans';


    perform
        loan_record.id
    from public.loan
        loan_record
    where loan_record.user_id =
          v_user.id
      and loan_record.status =
          'active'::public."LoanStatus"
    order by
        loan_record.created_at asc,
        loan_record.id asc
    for update;


    /*
     * ==========================================================
     * FETCH CURRENT GOLD PRICE
     * ==========================================================
     */
    v_stage :=
        'fetch gold price';


    select
        coalesce(
            rate_record.rate_to_usd,
            0
        )
    into
        v_gold_price
    from public.current_rates
        rate_record
    where lower(
        rate_record.code
    ) = 'gold'
    limit 1;


    v_gold_price :=
        coalesce(
            v_gold_price,
            0
        );


    if v_gold_price is null
       or v_gold_price::text in ('NaN', 'Infinity', '-Infinity')
       or v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * CALCULATE REQUIRED COLLATERAL POOL
     * ==========================================================
     *
     * The collateral model is pooled.
     *
     * Therefore loan.collateral MUST NOT be subtracted here.
     *
     * For every active loan:
     *
     * exposure =
     *     outstanding principal
     *     +
     *     outstanding interest
     *
     * required collateral USD =
     *     exposure /
     *     target LTV
     *
     * required collateral gold =
     *     required collateral USD /
     *     current gold price
     *
     * The required pool is the SUM of the current requirements
     * of all active loans.
     *
     * loan.collateral is only the current DISTRIBUTION of that
     * shared pool across individual loans.
     * ==========================================================
     */
    v_stage :=
        'calculate required collateral pool';


    v_total_required_pool := 0;


    for v_loan in
        select
            loan_record.*
        from public.loan
            loan_record
        where loan_record.user_id =
              v_user.id
          and loan_record.status =
              'active'::public."LoanStatus"
        order by
            loan_record.created_at asc,
            loan_record.id asc
    loop
        select
            greatest(
                coalesce(
                    sum(
                        entry_record.debit_principal
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_principal
                    ),
                    0
                ),
                0
            ),

            greatest(
                coalesce(
                    sum(
                        entry_record.debit_interest
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_interest
                    ),
                    0
                ),
                0
            )
        into
            v_principal,
            v_interest
        from public.loan_entry
            entry_record
        where entry_record.loan_id =
              v_loan.id;


        if v_loan.country_code is distinct from v_user.country_code
           or lower(btrim(v_loan.currency_code)) is distinct from 'usd'
        then
            raise exception 'LOAN_PORTFOLIO_CONTEXT_MISMATCH';
        end if;
        if v_principal::text in ('NaN', 'Infinity', '-Infinity')
           or v_interest::text in ('NaN', 'Infinity', '-Infinity')
        then
            raise exception 'INVALID_LOAN_BALANCE';
        end if;

        v_exposure :=
            v_principal +
            v_interest;


        if v_exposure <= 0 then
            continue;
        end if;


        v_target_ltv :=
            coalesce(
                v_loan.max_ltv_percent,
                0
            );


        if v_target_ltv::text in ('NaN', 'Infinity', '-Infinity')
           or v_target_ltv <= 0
           or v_target_ltv >= 100
        then
            raise exception
                'INVALID_LOAN_LTV_CONFIGURATION';
        end if;


        /*
         * Example:
         *
         * max_ltv_percent = 60.00
         *
         * target LTV =
         *
         * 60.00 / 100
         * =
         * 0.60
         */
        v_target_collateral := ceil(
            v_exposure * 100 / (v_target_ltv * v_gold_price) * 1000000
        ) / 1000000;


        v_total_required_pool :=
            v_total_required_pool +
            v_target_collateral;
    end loop;


    /*
     * Keep the portfolio requirement itself at six decimals,
     * matching the sum of its individual loan allocations.
     */
    v_total_required_pool :=
        round(
            v_total_required_pool,
            6
        );


    /*
     * ==========================================================
     * CALCULATE CURRENT POOL SHORTAGE
     * ==========================================================
     *
     * This is the fundamental pooled-collateral calculation:
     *
     * shortage =
     *
     *     current collateral required by all active loans
     *
     *     MINUS
     *
     *     actual consolidated gold currently locked
     * ==========================================================
     */
    v_collateral_shortage :=
        greatest(
            v_total_required_pool -
            v_previous_locked,
            0
        );


    /*
     * ==========================================================
     * NOTHING NEEDS TO BE ADDED
     * ==========================================================
     *
     * The actual pooled collateral is already sufficient to
     * cover all current active loan exposure at the configured
     * target LTVs.
     *
     * Do not lock additional gold merely because the user
     * authorised an amount.
     * ==========================================================
     */
    if v_collateral_shortage <= 0 then
        return query
        select
            true,

            false,

            to_char(
                v_requested_collateral,
                'FM999999999999999999999999990.000000'
            ),

            '0.000000'::text,

            to_char(
                v_requested_collateral,
                'FM999999999999999999999999990.000000'
            ),

            '0.000000'::text,

            to_char(
                round(
                    v_previous_locked,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            to_char(
                round(
                    v_previous_locked,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            0;

        return;
    end if;


    /*
     * ==========================================================
     * DETERMINE ACTUAL GOLD TO ADD
     * ==========================================================
     *
     * The signed requested amount is a MAXIMUM authorization.
     *
     * Example:
     *
     * requested = 0.100000
     * shortage  = 0.050000
     *
     * add only:
     *
     * 0.050000
     *
     * The remaining 0.050000 remains available to the user.
     * ==========================================================
     */
    v_collateral_added :=
        least(
            v_requested_collateral,
            v_collateral_shortage
        );


    /*
     * collateral_entry can persist only six decimal places.
     */
    v_collateral_added :=
        trunc(
            v_collateral_added,
            6
        );


    if v_collateral_added <= 0 then
        return query
        select
            true,

            true,

            to_char(
                v_requested_collateral,
                'FM999999999999999999999999990.000000'
            ),

            '0.000000'::text,

            to_char(
                v_requested_collateral,
                'FM999999999999999999999999990.000000'
            ),

            to_char(
                v_collateral_shortage,
                'FM999999999999999999999999990.000000'
            ),

            to_char(
                round(
                    v_previous_locked,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            to_char(
                round(
                    v_previous_locked,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            0;

        return;
    end if;


    /*
     * ==========================================================
     * CHECK AVAILABLE BLOCKCHAIN GOLD
     * ==========================================================
     *
     * IMPORTANT:
     *
     * Validate the amount ACTUALLY being locked.
     *
     * Do not reject a request merely because the user authorised
     * more than is necessary.
     *
     * Example:
     *
     * requested       = 0.100000
     * required        = 0.050000
     * available       = 0.060000
     *
     * This is valid because only 0.050000 will be locked.
     * ==========================================================
     */
    v_stage :=
        'validate available collateral';


    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_previous_locked,
            0
        );


    if v_collateral_added >
       v_available_tokens
    then
        raise exception
            'INSUFFICIENT_AVAILABLE_GOLD';
    end if;


    /*
     * ==========================================================
     * UPDATE CONSOLIDATED COLLATERAL POOL
     * ==========================================================
     *
     * The pool is updated BEFORE its distribution across active
     * loans.
     *
     * Only the amount actually required and authorised is added.
     * ==========================================================
     */
    v_stage :=
        'update consolidated collateral';


    update public.collateral
    set
        locked_tokens =
            coalesce(
                locked_tokens,
                0
            ) +
            v_collateral_added,
        updated_at = now()
    where id = v_collateral.id
      and user_id = v_user.id
    returning
        locked_tokens
    into
        v_new_locked;


    if not found then
        raise exception
            'COLLATERAL_UPDATE_FAILED';
    end if;

    if v_new_locked <> v_previous_locked + v_collateral_added then
        raise exception 'COLLATERAL_POOL_UPDATE_MISMATCH';
    end if;


    /*
     * ==========================================================
     * REDISTRIBUTE ACTUAL POOL ACROSS ACTIVE LOANS
     * ==========================================================
     *
     * loan.collateral represents the CURRENT allocation of the
     * shared collateral pool to that individual loan.
     *
     * It is therefore recalculated rather than incremented.
     *
     * Allocation order:
     *
     * oldest active loan
     *     ↓
     * next oldest
     *     ↓
     * until the actual pool is exhausted.
     *
     * If the pool is sufficient, every loan receives its full
     * target collateral.
     *
     * If the top-up was only partial, later loans may remain
     * partially covered or uncovered.
     *
     * Existing pool gold is allocated first.
     *
     * Only allocation originating from v_collateral_added
     * creates new collateral_entry debit rows.
     * ==========================================================
     */
    v_stage :=
        'redistribute collateral pool';


    v_remaining_pool :=
        v_new_locked;

    v_existing_pool_remaining :=
        v_previous_locked;

    v_new_gold_remaining :=
        v_collateral_added;

    v_loans_adjusted :=
        0;


    for v_loan in
        select
            loan_record.*
        from public.loan
            loan_record
        where loan_record.user_id =
              v_user.id
          and loan_record.status =
              'active'::public."LoanStatus"
        order by
            loan_record.created_at asc,
            loan_record.id asc
    loop
        /*
         * ------------------------------------------------------
         * CURRENT OUTSTANDING EXPOSURE
         * ------------------------------------------------------
         */
        select
            greatest(
                coalesce(
                    sum(
                        entry_record.debit_principal
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_principal
                    ),
                    0
                ),
                0
            ),

            greatest(
                coalesce(
                    sum(
                        entry_record.debit_interest
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_interest
                    ),
                    0
                ),
                0
            )
        into
            v_principal,
            v_interest
        from public.loan_entry
            entry_record
        where entry_record.loan_id =
              v_loan.id;


        if v_loan.country_code is distinct from v_user.country_code
           or lower(btrim(v_loan.currency_code)) is distinct from 'usd'
        then
            raise exception 'LOAN_PORTFOLIO_CONTEXT_MISMATCH';
        end if;
        if v_principal::text in ('NaN', 'Infinity', '-Infinity')
           or v_interest::text in ('NaN', 'Infinity', '-Infinity')
        then
            raise exception 'INVALID_LOAN_BALANCE';
        end if;

        v_exposure :=
            v_principal +
            v_interest;


        /*
         * An active loan with no remaining exposure receives no
         * collateral allocation.
         */
        if v_exposure <= 0 then
            v_target_collateral := 0;
        else
            v_target_ltv :=
                coalesce(
                    v_loan.max_ltv_percent,
                    0
                );


            if v_target_ltv::text in ('NaN', 'Infinity', '-Infinity')
               or v_target_ltv <= 0
               or v_target_ltv >= 100
            then
                raise exception
                    'INVALID_LOAN_LTV_CONFIGURATION';
            end if;


            v_target_collateral := ceil(
                v_exposure * 100 / (v_target_ltv * v_gold_price) * 1000000
            ) / 1000000;
        end if;


        /*
         * Allocate only gold that actually exists in the pool.
         */
        v_allocation :=
            least(
                v_target_collateral,
                greatest(
                    v_remaining_pool,
                    0
                )
            );


        v_allocation :=
            trunc(
                v_allocation,
                6
            );


        /*
         * ------------------------------------------------------
         * IDENTIFY EXISTING POOL VS NEW TOP-UP
         * ------------------------------------------------------
         *
         * Existing pool collateral is consumed first during the
         * redistribution.
         *
         * Any portion beyond that is newly locked gold belonging
         * to this operation and therefore receives a new
         * collateral_entry.
         * ------------------------------------------------------
         */
        v_existing_allocation :=
            least(
                v_allocation,
                greatest(
                    v_existing_pool_remaining,
                    0
                )
            );


        v_existing_allocation :=
            trunc(
                v_existing_allocation,
                6
            );


        v_new_allocation :=
            greatest(
                v_allocation -
                v_existing_allocation,
                0
            );


        v_new_allocation :=
            least(
                v_new_allocation,
                greatest(
                    v_new_gold_remaining,
                    0
                )
            );


        v_new_allocation :=
            trunc(
                v_new_allocation,
                6
            );


        /*
         * ------------------------------------------------------
         * SYNCHRONISE INDIVIDUAL LOAN ALLOCATION
         * ------------------------------------------------------
         *
         * DO NOT:
         *
         *     loan.collateral += top_up
         *
         * The old value may represent a position calculated at
         * a different:
         *
         * - gold price;
         * - principal balance;
         * - interest balance;
         * - liquidation state;
         * - repayment state.
         *
         * Instead loan.collateral becomes the amount of today's
         * actual pooled collateral allocated to that loan.
         * ------------------------------------------------------
         */
        v_previous_loan_allocation :=
            greatest(
                coalesce(
                    v_loan.collateral,
                    0
                ),
                0
            );


        if v_previous_loan_allocation
           is distinct from
           v_allocation
        then
            v_stage :=
                'update loan collateral allocation';


            update public.loan
            set
                collateral =
                    v_allocation,
                updated_at = now()
            where id =
                  v_loan.id;


            if not found then
                raise exception
                    'LOAN_COLLATERAL_UPDATE_FAILED';
            end if;


            v_loans_adjusted :=
                v_loans_adjusted +
                1;
        end if;


        v_liquidation_price := 0;
        if v_exposure > 0 and v_allocation > 0 then
            if v_loan.liquidation_ltv is null
               or v_loan.liquidation_ltv::text in ('NaN', 'Infinity', '-Infinity')
               or v_loan.liquidation_ltv <= 0
               or v_loan.liquidation_ltv > 100
            then
                raise exception 'INVALID_LIQUIDATION_LTV';
            end if;
            v_liquidation_price := trunc(
                v_exposure / (v_allocation * v_loan.liquidation_ltv / 100), 6
            );
        end if;
        update public.loan
        set liquidation_price = v_liquidation_price,
            updated_at = now()
        where id = v_loan.id;

        /*
         * ------------------------------------------------------
         * CREATE LEDGER ENTRY FOR NEW GOLD ONLY
         * ------------------------------------------------------
         *
         * Existing pooled gold is merely being redistributed.
         * It must not be posted again.
         *
         * Only newly locked gold from this request creates a
         * collateral_entry debit.
         * ------------------------------------------------------
         */
        if v_new_allocation > 0 then
            v_stage :=
                'create collateral entry';


            insert into public.collateral_entry (
                loan_id,
                document_number,
                reference,
                debit,
                credit,
                country_code
            )
            values (
                v_loan.id,
                v_reference,
                v_reference,
                v_new_allocation,
                0,
                v_user.country_code
            );
            v_posted_debits := v_posted_debits + v_new_allocation;
        end if;


        /*
         * ------------------------------------------------------
         * REDUCE REMAINING POOL
         * ------------------------------------------------------
         */
        v_remaining_pool :=
            greatest(
                v_remaining_pool -
                v_allocation,
                0
            );


        v_existing_pool_remaining :=
            greatest(
                v_existing_pool_remaining -
                v_existing_allocation,
                0
            );


        v_new_gold_remaining :=
            greatest(
                v_new_gold_remaining -
                v_new_allocation,
                0
            );
    end loop;


    /*
     * ==========================================================
     * SAFETY CHECK: NEW GOLD MUST BE ACCOUNTED FOR
     * ==========================================================
     *
     * Because the new pool cannot exceed the calculated required
     * pool, all newly added gold should have been assigned to an
     * active loan.
     *
     * A remaining new amount indicates that the portfolio changed
     * unexpectedly or the allocation calculation is inconsistent.
     * ==========================================================
     */
    if v_new_gold_remaining <> 0
       or v_existing_pool_remaining <> 0
       or v_remaining_pool <> 0
       or v_posted_debits <> v_collateral_added
    then
        raise exception
            'COLLATERAL_ALLOCATION_MISMATCH';
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


    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * UPDATE COLLATERAL SNAPSHOT
     * ==========================================================
     *
     * Only newly locked collateral changes the consolidated
     * balance snapshot.
     *
     * Redistributing existing pooled collateral across loans
     * does not change the user's total locked gold.
     * ==========================================================
     */
    v_stage :=
        'update collateral snapshot';


    perform public.update_collateral_snapshot(
        v_user.id,
        v_user.country_code,
        v_collateral_added,
        0::numeric,
        v_fiscal_year,
        v_period
    );


    /*
     * ==========================================================
     * CALCULATE REMAINING PORTFOLIO SHORTAGE
     * ==========================================================
     */
    v_remaining_required :=
        greatest(
            v_total_required_pool -
            v_new_locked,
            0
        );


    /*
     * Keep the externally reported requirement at six decimal
     * places.
     */
    v_remaining_required :=
        ceil(
            v_remaining_required *
            1000000
        ) /
        1000000;


    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     */
    return query
    select
        true,

        /*
         * true means the pool is STILL below target after this
         * operation.
         */
        v_remaining_required > 0,

        to_char(
            v_requested_collateral,
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            v_collateral_added,
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            greatest(
                v_requested_collateral -
                v_collateral_added,
                0
            ),
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            v_remaining_required,
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            round(
                v_previous_locked,
                6
            ),
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            round(
                v_new_locked,
                6
            ),
            'FM999999999999999999999999990.000000'
        ),

        v_loans_adjusted;


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
                    'ADDITIONAL_COLLATERAL_FAILED at [%s]: %s',
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
                    'Check the Additional Collateral stage reported in the error'
                );
end;
$function$;
REVOKE ALL ON FUNCTION public.execute_additional_collateral(text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_additional_collateral(text,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.execute_my_additional_collateral(text,text,text) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
