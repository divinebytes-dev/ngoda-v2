/*
 * ============================================================
 * CUSTOMER LOAN REPAYMENT
 * ============================================================
 */

create or replace function public.execute_my_loan_repayment(
    p_amount text,
    p_reference text,
    p_currency_code text default 'usd',
    p_ip_address text default null
)
returns table (
    success boolean,
    document_number text,
    principal_paid text,
    interest_paid text,
    collateral_unlocked text,
    unused_payment text,
    loans_closed integer
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_transaction_type
        public."TransactionType" :=
            'loan_repayment'::public."TransactionType";

    v_stage text := 'initialization';

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;
    v_collateral public.collateral%rowtype;
    v_loan public.loan%rowtype;

    v_reference text;
    v_currency text;
    v_payment_amount numeric;
    v_remaining_payment numeric;

    v_principal_outstanding numeric;
    v_interest_outstanding numeric;

    v_principal_paid numeric;
    v_interest_paid numeric;

    v_total_principal_paid numeric := 0;
    v_total_interest_paid numeric := 0;
    v_total_payment_applied numeric := 0;

    v_prior_collateral_unlocked numeric;
    v_loan_collateral_remaining numeric;
    v_collateral_unlock numeric;
    v_total_collateral_unlock numeric := 0;

    v_principal_remaining numeric;
    v_interest_remaining numeric;

    v_closed_loans_count integer := 0;
    v_active_loan_found boolean := false;

    v_fiscal_year integer;
    v_period integer;

    v_document_prefix text;
    v_document_number text;
    v_financial_transaction_id bigint;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * ========================================================
     * AUTHORIZE CUSTOMER
     * ========================================================
     */

    v_stage := 'authorize customer';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
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
       or btrim(v_user.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * ========================================================
     * PARSE INPUT
     * ========================================================
     */

    v_stage := 'parse repayment amount';

    begin
        v_payment_amount :=
            nullif(
                btrim(p_amount),
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
       or v_payment_amount <= 0
    then
        raise exception
            'INVALID_REPAYMENT_AMOUNT';
    end if;

    v_remaining_payment :=
        v_payment_amount;

    v_stage := 'parse reference';

    v_reference :=
        nullif(
            btrim(p_reference),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    v_stage := 'parse currency';

    v_currency :=
        lower(
            nullif(
                btrim(p_currency_code),
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
     * ========================================================
     * PREVENT REPLAY AND CONCURRENT REPAYMENT
     * ========================================================
     */

    v_stage := 'lock repayment reference';

    perform pg_catalog.pg_advisory_xact_lock(
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
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
    end if;

    /*
     * Serialize all repayments for this customer.
     */
    v_stage := 'lock customer loans';

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'loan-repayment:' ||
            v_user.id,
            0
        )
    );

    /*
     * ========================================================
     * FETCH TREASURY
     * ========================================================
     */

    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;

    /*
     * ========================================================
     * LOCK CUSTOMER COLLATERAL
     * ========================================================
     */

    v_stage := 'lock collateral';

    select collateral_record.*
    into v_collateral
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_user.id
    for update;

    if not found then
        raise exception
            'COLLATERAL_NOT_FOUND';
    end if;

    if v_collateral.country_code is distinct from
       v_user.country_code
    then
        raise exception
            'COLLATERAL_COUNTRY_MISMATCH';
    end if;

    /*
     * ========================================================
     * FETCH FISCAL PERIOD
     * ========================================================
     */

    v_stage := 'fetch fiscal period';

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
     * ========================================================
     * FETCH DOCUMENT PREFIX
     * ========================================================
     */

    v_stage := 'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
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
            v_user.country_code
        );

    /*
     * ========================================================
     * ALLOCATE REPAYMENT TO ACTIVE LOANS
     * ========================================================
     */

    v_stage := 'allocate loan repayment';

    for v_loan in
        select loan_record.*
        from public.loan loan_record
        where loan_record.user_id =
              v_user.id
          and loan_record.status =
              'active'::public."LoanStatus"
          and lower(
              btrim(loan_record.currency_code)
          ) = v_currency
        order by
            loan_record.created_at asc,
            loan_record.id asc
        for update
    loop
        v_active_loan_found := true;

        exit when
            v_remaining_payment <= 0;

        /*
         * Calculate current outstanding balances.
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

        if v_principal_outstanding <= 0
           and v_interest_outstanding <= 0
        then
            continue;
        end if;

        v_interest_paid := 0;
        v_principal_paid := 0;
        v_collateral_unlock := 0;

        /*
         * Pay accrued interest first.
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
         * Pay principal after interest.
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
         * Create one repayment entry per affected loan.
         */
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
         * Update the loan snapshot using the existing exact
         * function signature.
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

        /*
         * Calculate collateral already unlocked for this loan.
         *
         * Credits represent collateral releases.
         */
        select coalesce(
            sum(
                coalesce(
                    collateral_entry_record.credit,
                    0
                )
            ),
            0
        )
        into v_prior_collateral_unlocked
        from public.collateral_entry
            collateral_entry_record
        where collateral_entry_record.loan_id =
              v_loan.id;

        v_loan_collateral_remaining :=
            greatest(
                coalesce(
                    v_loan.collateral,
                    0
                ) -
                v_prior_collateral_unlocked,
                0
            );

        /*
         * Release collateral only when principal is repaid.
         */
        if v_principal_paid > 0
           and v_loan_collateral_remaining > 0
        then
            if v_principal_remaining <= 0 then
                /*
                 * Final principal repayment releases all
                 * remaining collateral and removes rounding
                 * dust.
                 */
                v_collateral_unlock :=
                    v_loan_collateral_remaining;
            else
                /*
                 * Partial repayment releases proportional
                 * collateral, rounded down to six decimals.
                 */
                v_collateral_unlock :=
                    trunc(
                        (
                            coalesce(
                                v_loan.collateral,
                                0
                            ) *
                            v_principal_paid
                        ) /
                        nullif(
                            v_loan.principal,
                            0
                        ),
                        6
                    );

                v_collateral_unlock :=
                    least(
                        v_collateral_unlock,
                        v_loan_collateral_remaining
                    );
            end if;
        end if;

        if v_collateral_unlock > 0 then
            v_stage :=
                'create collateral release entry';

            insert into public.collateral_entry (
                loan_id,
                document_number,
                debit,
                credit,
                country_code
            )
            values (
                v_loan.id,
                v_document_number,
                0,
                v_collateral_unlock,
                v_user.country_code
            );

            v_total_collateral_unlock :=
                v_total_collateral_unlock +
                v_collateral_unlock;
        end if;

        /*
         * Close the loan only when both principal and interest
         * are fully settled.
         */
        if v_principal_remaining <= 0
           and v_interest_remaining <= 0
        then
            v_stage := 'close loan';

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

    v_total_payment_applied :=
        v_total_principal_paid +
        v_total_interest_paid;

    /*
     * ========================================================
     * RELEASE CUSTOMER COLLATERAL
     * ========================================================
     */

    if v_total_collateral_unlock > 0 then
        v_stage := 'release collateral';

        update public.collateral
        set
            locked_tokens =
                locked_tokens -
                v_total_collateral_unlock
        where user_id =
              v_user.id
          and coalesce(
              locked_tokens,
              0
          ) >=
              v_total_collateral_unlock;

        if not found then
            raise exception
                'COLLATERAL_BALANCE_TOO_LOW';
        end if;

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
     * ========================================================
     * BUILD FINANCIAL POSTING COMPONENTS
     * ========================================================
     */

    v_stage := 'fetch GL mappings';

    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        v_transaction_type
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Debit is the total amount received.
     * Principal and interest are credited separately.
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
     * ========================================================
     * CREATE FINANCIAL TRANSACTION
     * ========================================================
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
    returning id
    into v_financial_transaction_id;

    /*
     * ========================================================
     * POST FINANCIAL ENTRIES
     * ========================================================
     */

    v_stage := 'post financial entries';

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
     * ========================================================
     * MOVE CUSTOMER FUNDS TO TREASURY
     * ========================================================
     */

    v_stage := 'post wallet entries';

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
     * ========================================================
     * RETURN RESULT
     * ========================================================
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

        v_closed_loans_count;

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


/*
 * ============================================================
 * PRIVILEGES
 * ============================================================
 */

revoke all on function
    public.execute_my_loan_repayment(
        text,
        text,
        text,
        text
    )
from public;

revoke execute on function
    public.execute_my_loan_repayment(
        text,
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_loan_repayment(
        text,
        text,
        text,
        text
    )
to authenticated;