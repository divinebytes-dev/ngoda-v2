CREATE OR REPLACE FUNCTION public.execute_my_additional_collateral(
    p_requested_collateral text,
    p_token_balance text,
    p_reference text
)
RETURNS TABLE(
    success boolean,
    collateral_required boolean,
    requested_collateral text,
    collateral_added text,
    unused_collateral text,
    remaining_required_collateral text,
    previous_locked_collateral text,
    new_locked_collateral text,
    loans_adjusted integer
)
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
     * Maximum amount the user has requested to add.
     */
    v_requested_collateral numeric;

    /*
     * Current blockchain gold balance supplied by the
     * authenticated Edge Function.
     */
    v_total_tokens numeric;

    /*
     * Gold which is not currently locked as collateral.
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
     * Current collateral allocated to the loan.
     */
    v_current_loan_collateral numeric := 0;

    /*
     * Target LTV stored on the loan.
     *
     * Existing loans are created using the LTV calculated
     * during loan disbursement.
     */
    v_target_ltv numeric := 0;

    /*
     * Gold required for one loan to return to its
     * configured target LTV.
     */
    v_target_collateral numeric := 0;
    v_required_for_loan numeric := 0;

    /*
     * Allocation values.
     */
    v_remaining_requested numeric := 0;
    v_allocation numeric := 0;
    v_collateral_added numeric := 0;

    /*
     * Total collateral shortage before this operation.
     */
    v_total_required numeric := 0;

    /*
     * Remaining shortage after the operation.
     */
    v_remaining_required numeric := 0;

    v_previous_locked numeric := 0;
    v_new_locked numeric := 0;

    v_loans_adjusted integer := 0;

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


    if v_user.status <>
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
       or v_requested_collateral <= 0
    then
        raise exception
            'INVALID_COLLATERAL_AMOUNT';
    end if;


    /*
     * collateral_entry stores gold with six decimal places.
     *
     * Do not silently round a user's requested quantity.
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


    if v_total_tokens < 0 then
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
     *
     * One collateral operation may create several
     * collateral_entry rows because the amount can be
     * distributed across several active loans.
     *
     * Therefore the operation reference is shared by all
     * entries created during this execution.
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
     * ENSURE COLLATERAL ROW EXISTS
     * ==========================================================
     */
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


    v_previous_locked :=
        coalesce(
            v_collateral.locked_tokens,
            0
        );


    /*
     * ==========================================================
     * LOCK ACTIVE LOANS
     * ==========================================================
     *
     * Additional collateral and repayment must not modify
     * the same active facilities concurrently.
     *
     * Oldest loans are locked first, which is also the
     * allocation order used below.
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
     * FETCH GOLD PRICE
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


    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * CALCULATE TOTAL COLLATERAL CURRENTLY REQUIRED
     * ==========================================================
     *
     * This calculation is performed again at execution time.
     *
     * We deliberately do not trust the required_collateral
     * value previously returned to Flutter because:
     *
     * - gold price can change;
     * - interest can accrue;
     * - repayments can occur;
     * - another collateral operation can occur.
     *
     * Each active loan is assessed independently.
     */
    v_stage :=
        'calculate collateral requirement';


    v_total_required := 0;


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


        if v_target_ltv <= 0
           or v_target_ltv > 100
        then
            raise exception
                'INVALID_LOAN_LTV_CONFIGURATION';
        end if;


        v_current_loan_collateral :=
            greatest(
                coalesce(
                    v_loan.collateral,
                    0
                ),
                0
            );


        /*
         * Required collateral:
         *
         * LTV =
         *     exposure /
         *     collateral value
         *
         * therefore:
         *
         * target collateral USD =
         *     exposure /
         *     target LTV
         *
         * target collateral grams =
         *     target collateral USD /
         *     gold price
         */
        v_target_collateral :=
            (
                v_exposure /
                (
                    v_target_ltv /
                    100
                )
            ) /
            v_gold_price;


        v_required_for_loan :=
            greatest(
                v_target_collateral -
                v_current_loan_collateral,
                0
            );


        /*
         * collateral_entry is six decimal places.
         *
         * Round upward so the required amount cannot leave
         * the loan fractionally above the target because of
         * quantity rounding.
         */
        if v_required_for_loan > 0 then
            v_required_for_loan :=
                ceil(
                    v_required_for_loan *
                    1000000
                ) /
                1000000;


            v_total_required :=
                v_total_required +
                v_required_for_loan;
        end if;
    end loop;


    /*
     * ==========================================================
     * NOTHING TO ADD
     * ==========================================================
     *
     * All active loans are already at or below their
     * target LTV.
     *
     * This is a successful business result, not a failed
     * database operation.
     */
    if v_total_required <= 0 then
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
     * CHECK AVAILABLE GOLD
     * ==========================================================
     *
     * Blockchain total minus consolidated locked collateral
     * is the quantity currently available to lock.
     */
    v_stage :=
        'validate available collateral';


    v_available_tokens :=
        greatest(
            v_total_tokens -
            v_previous_locked,
            0
        );


    /*
     * The requested amount is the amount the user explicitly
     * authorised us to lock.
     *
     * We can use less when less is required, but we must not
     * silently replace an unavailable requested amount with
     * another amount.
     */
    if v_requested_collateral >
       v_available_tokens
    then
        raise exception
            'INSUFFICIENT_AVAILABLE_GOLD';
    end if;


    /*
     * ==========================================================
     * ALLOCATE COLLATERAL
     * ==========================================================
     *
     * Allocation order:
     *
     * oldest active loan
     *     ↓
     * next oldest active loan
     *     ↓
     * continue until:
     *
     * - requested collateral is exhausted; or
     * - every loan has reached its target LTV.
     *
     * Excess requested collateral is NOT locked.
     */
    v_stage :=
        'allocate collateral';


    v_remaining_requested :=
        v_requested_collateral;

    v_collateral_added := 0;

    v_loans_adjusted := 0;


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
        exit when
            v_remaining_requested <= 0;


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


        if v_target_ltv <= 0
           or v_target_ltv > 100
        then
            raise exception
                'INVALID_LOAN_LTV_CONFIGURATION';
        end if;


        v_current_loan_collateral :=
            greatest(
                coalesce(
                    v_loan.collateral,
                    0
                ),
                0
            );


        v_target_collateral :=
            (
                v_exposure /
                (
                    v_target_ltv /
                    100
                )
            ) /
            v_gold_price;


        v_required_for_loan :=
            greatest(
                v_target_collateral -
                v_current_loan_collateral,
                0
            );


        if v_required_for_loan <= 0 then
            continue;
        end if;


        v_required_for_loan :=
            ceil(
                v_required_for_loan *
                1000000
            ) /
            1000000;


        /*
         * Never allocate more than:
         *
         * - the loan requires; or
         * - the user requested.
         */
        v_allocation :=
            least(
                v_required_for_loan,
                v_remaining_requested
            );


        /*
         * Keep collateral entries at six decimal places.
         */
        v_allocation :=
            trunc(
                v_allocation,
                6
            );


        if v_allocation <= 0 then
            continue;
        end if;


        /*
         * ------------------------------------------------------
         * UPDATE INDIVIDUAL LOAN COLLATERAL
         * ------------------------------------------------------
         */
        v_stage :=
            'update loan collateral';


        update public.loan
        set
            collateral =
                coalesce(
                    collateral,
                    0
                ) +
                v_allocation
        where id =
              v_loan.id;


        if not found then
            raise exception
                'LOAN_COLLATERAL_UPDATE_FAILED';
        end if;


        /*
         * ------------------------------------------------------
         * CREATE COLLATERAL LEDGER ENTRY
         * ------------------------------------------------------
         *
         * Same direction as loan disbursement:
         *
         * debit  = collateral locked
         * credit = collateral released
         *
         * There is no financial transaction for this operation,
         * therefore the operation reference is also used as its
         * collateral document identifier.
         */
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
            v_allocation,
            0,
            v_user.country_code
        );


        v_collateral_added :=
            v_collateral_added +
            v_allocation;


        v_remaining_requested :=
            v_remaining_requested -
            v_allocation;


        v_loans_adjusted :=
            v_loans_adjusted +
            1;
    end loop;


    /*
     * ==========================================================
     * SAFETY CHECK
     * ==========================================================
     */
    if v_collateral_added <= 0 then
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

            to_char(
                v_total_required,
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
     * UPDATE CONSOLIDATED COLLATERAL
     * ==========================================================
     *
     * IMPORTANT:
     *
     * Add only the amount actually allocated.
     *
     * If user requested 0.100000 but the active loans only
     * required 0.050000:
     *
     * collateral.locked_tokens += 0.050000
     *
     * NOT 0.100000.
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
            v_collateral_added
    where user_id =
          v_user.id
    returning
        locked_tokens
    into
        v_new_locked;


    if not found then
        raise exception
            'COLLATERAL_UPDATE_FAILED';
    end if;


    /*
     * ==========================================================
     * FETCH FISCAL PERIOD
     * ==========================================================
     *
     * Needed only for the collateral balance snapshot.
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
     * Same direction used by loan disbursement:
     *
     * debit = newly locked collateral
     * credit = 0
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
     * CALCULATE REMAINING REQUIREMENT
     * ==========================================================
     */
    v_remaining_required :=
        greatest(
            v_total_required -
            v_collateral_added,
            0
        );


    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     */
    return query
    select
        true,

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