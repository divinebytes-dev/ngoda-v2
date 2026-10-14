ALTER TABLE public.liquidation_job
ADD COLUMN IF NOT EXISTS completed_at timestamptz;

CREATE OR REPLACE FUNCTION public.finalise_liquidation_accounting_job(
    p_job_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_job
        public.liquidation_job%rowtype;

    v_queue
        public.liquidation_blockchain_queue%rowtype;

    v_user
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_collateral
        public.collateral%rowtype;

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_loan record;

    v_job_id text;
    v_sub_document_number text;

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

    v_usd_mappings
        public.transaction_gl_mapping[];

    v_gold_mappings
        public.transaction_gl_mapping[];

    v_usd_components
        public.posting_component[] :=
            array[]::public.posting_component[];

    v_gold_components
        public.posting_component[];

    v_usd_transaction_id
        public.financial_transaction.id%type;

    v_gold_transaction_id
        public.financial_transaction.id%type;

    v_wallet_entry_count integer;
    v_notification_id text;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation cron service may finalise the
     * accounting.
     */
    v_stage :=
        'authorize service role';

    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    /*
     * Validate input.
     */
    v_stage :=
        'validate input';

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

    /*
     * Lock the liquidation job.
     */
    v_stage :=
        'lock liquidation job';

    select job_record.*
    into v_job
    from public.liquidation_job
        job_record
    where job_record.id::text =
          v_job_id
    for update;

    if not found then
        raise exception
            'LIQUIDATION_JOB_NOT_FOUND';
    end if;

    /*
     * Idempotent completion.
     */
    if v_job.status::text =
       'completed'
    then
        return jsonb_build_object(
            'success',
            true,

            'already_completed',
            true,

            'job_id',
            v_job.id,

            'document_number',
            v_job.document_number,

            'status',
            v_job.status
        );
    end if;

    if v_job.status::text <>
       'accounting_processing'
    then
        raise exception
            'LIQUIDATION_JOB_NOT_ACCOUNTING_PROCESSING';
    end if;

    if nullif(
        btrim(
            v_job.document_number
        ),
        ''
    ) is null
    then
        raise exception
            'LIQUIDATION_DOCUMENT_NUMBER_NOT_FOUND';
    end if;

    if v_job.repayment_required is null
       or v_job.repayment_required <= 0
    then
        raise exception
            'INVALID_LIQUIDATION_DEBT_REPAYMENT';
    end if;

    if v_job.penalty_amount is null
       or v_job.penalty_amount < 0
    then
        raise exception
            'INVALID_LIQUIDATION_PENALTY';
    end if;

    if v_job.total_required is null
       or v_job.total_required <= 0
    then
        raise exception
            'INVALID_LIQUIDATION_TOTAL_PROCEEDS';
    end if;

    if v_job.collateral_required is null
       or v_job.collateral_required <= 0
    then
        raise exception
            'INVALID_LIQUIDATION_COLLATERAL';
    end if;

    /*
     * Confirm that the blockchain queue has successfully
     * transferred the Gold.
     */
    v_stage :=
        'validate blockchain confirmation';

    select queue_record.*
    into v_queue
    from public.liquidation_blockchain_queue
        queue_record
    where queue_record.id::text =
              v_job.blockchain_queue_id

      and queue_record.liquidation_job_id =
              v_job.id::text
    for update;

    if not found then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    end if;

    if v_queue.status::text <>
       'confirmed'
       or nullif(
           btrim(
               v_queue.tx_hash
           ),
           ''
       ) is null
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_NOT_CONFIRMED';
    end if;

    if trunc(
        v_queue.collateral,
        6
    ) <>
       trunc(
           v_job.collateral_required,
           6
       )
    then
        raise exception
            'LIQUIDATION_BLOCKCHAIN_COLLATERAL_MISMATCH';
    end if;

    /*
     * Fetch the borrower.
     */
    v_stage :=
        'fetch liquidation user';

    select user_record.*
    into v_user
    from public.users
        user_record
    where user_record.id =
          v_job.user_id
    limit 1;

    if not found then
        raise exception
            'LIQUIDATION_USER_NOT_FOUND';
    end if;

    /*
     * Fetch the country-specific treasury for the
     * database ledger movement.
     *
     * This is separate from the one global blockchain
     * treasury address.
     */
    v_stage :=
        'fetch country treasury';

    select treasury_record.*
    into v_treasury
    from public.fetch_country_treasury(
        v_job.country_code
    ) as treasury_record;

    if not found
       or v_treasury.id is null
    then
        raise exception
            'COUNTRY_TREASURY_NOT_FOUND';
    end if;

    /*
     * Lock the user's collateral balance.
     */
    v_stage :=
        'lock collateral balance';

    select collateral_record.*
    into v_collateral
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_job.user_id
    for update;

    if not found then
        raise exception
            'COLLATERAL_NOT_FOUND';
    end if;

    if coalesce(
        v_collateral.locked_tokens,
        0
    ) <
       v_job.collateral_required
    then
        raise exception
            'INSUFFICIENT_LOCKED_COLLATERAL';
    end if;

    /*
     * Prevent duplicate accounting documents.
     *
     * A partially created document cannot exist because
     * this complete RPC runs inside one database
     * transaction.
     */
    v_stage :=
        'check accounting replay';

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.document_number =
          v_job.document_number
    limit 1;

    if found then
        raise exception
            'LIQUIDATION_ACCOUNTING_DOCUMENT_ALREADY_EXISTS';
    end if;

    v_remaining_repayment :=
        trunc(
            v_job.repayment_required,
            6
        );

    v_remaining_collateral :=
        trunc(
            v_job.collateral_required,
            6
        );

    /*
     * Allocate repayment across active loans from oldest
     * to newest.
     *
     * Within every loan:
     *
     * interest is paid first;
     * principal is paid second.
     */
    v_stage :=
        'allocate loan repayment';

    for v_loan in
        select loan_record.*
        from public.loan
            loan_record

        where loan_record.user_id =
                  v_job.user_id

          and lower(
              btrim(
                  loan_record.country_code
              )
          ) =
                  lower(
                      btrim(
                          v_job.country_code
                      )
                  )

          and loan_record.status =
                  'active'::public."LoanStatus"

        order by
            loan_record.created_at,
            loan_record.id

        for update
    loop
        exit when
            v_remaining_repayment <=
            0.000001;

        select
            greatest(
                coalesce(
                    sum(
                        coalesce(
                            entry_record.debit_principal,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_principal,
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
                            entry_record.debit_interest,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_interest,
                            0
                        )
                    ),
                    0
                ),
                0
            )
        into
            v_loan_principal,
            v_loan_interest
        from public.loan_entry
            entry_record
        where entry_record.loan_id =
              v_loan.id;

        v_loan_principal :=
            trunc(
                coalesce(
                    v_loan_principal,
                    0
                ),
                6
            );

        v_loan_interest :=
            trunc(
                coalesce(
                    v_loan_interest,
                    0
                ),
                6
            );

        v_loan_debt :=
            trunc(
                v_loan_principal +
                v_loan_interest,
                6
            );

        if v_loan_debt <= 0 then
            update public.loan
            set
                status =
                    'liquidated'::public."LoanStatus",

                liquidation_price =
                    0
            where id =
                  v_loan.id;

            continue;
        end if;

        v_payment :=
            trunc(
                least(
                    v_loan_debt,
                    v_remaining_repayment
                ),
                6
            );

        v_interest_paid :=
            trunc(
                least(
                    v_loan_interest,
                    v_payment
                ),
                6
            );

        v_principal_paid :=
            trunc(
                least(
                    v_loan_principal,
                    v_payment -
                    v_interest_paid
                ),
                6
            );

        v_payment :=
            trunc(
                v_interest_paid +
                v_principal_paid,
                6
            );

        if v_payment <= 0 then
            continue;
        end if;

        /*
         * Allocate the Gold, including the penalty
         * portion, proportionally to the debt repayment.
         *
         * The final loan allocation receives the
         * remaining Gold to prevent rounding loss.
         */
        if v_payment >=
           v_remaining_repayment -
           0.000001
        then
            v_collateral_used :=
                v_remaining_collateral;
        else
            v_collateral_used :=
                trunc(
                    (
                        v_job.collateral_required *
                        v_payment
                    ) /
                    v_job.repayment_required,
                    6
                );

            v_collateral_used :=
                least(
                    v_collateral_used,
                    v_remaining_collateral
                );
        end if;

        /*
         * Credit the loan balances.
         */
        insert into public.loan_entry (
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
        values (
            v_loan.id,
            v_job.fiscal_year,
            v_job.period,
            v_job.country_code,
            'liquidation'::public."LoanEntryType",
            v_job.document_number,
            'usd',

            0,
            v_principal_paid,

            0,
            v_interest_paid
        );

        /*
         * Consume the corresponding locked Gold.
         */
        insert into public.collateral_entry (
            loan_id,
            document_number,
            country_code,
            debit,
            credit
        )
        values (
            v_loan.id,
            v_job.document_number,
            v_job.country_code,
            v_collateral_used,
            0
        );

        v_total_principal_paid :=
            trunc(
                v_total_principal_paid +
                v_principal_paid,
                6
            );

        v_total_interest_paid :=
            trunc(
                v_total_interest_paid +
                v_interest_paid,
                6
            );

        v_total_repayment :=
            trunc(
                v_total_repayment +
                v_payment,
                6
            );

        v_total_collateral :=
            trunc(
                v_total_collateral +
                v_collateral_used,
                6
            );

        v_remaining_repayment :=
            trunc(
                v_remaining_repayment -
                v_payment,
                6
            );

        v_remaining_collateral :=
            trunc(
                v_remaining_collateral -
                v_collateral_used,
                6
            );

        /*
         * Close a loan only when both its principal and
         * interest have been fully cleared.
         */
        if v_payment >=
           v_loan_debt -
           0.000001
        then
            update public.loan
            set
                status =
                    'liquidated'::public."LoanStatus",

                liquidation_price =
                    0
            where id =
                  v_loan.id;
        end if;
    end loop;

    /*
     * The blockchain has already transferred this Gold.
     * Therefore, every cent of the planned debt repayment
     * must be allocated.
     */
    if v_remaining_repayment >
       0.000001
    then
        raise exception
            'LIQUIDATION_POSITION_CHANGED_REPAYMENT_REMAINING_%',
            v_remaining_repayment;
    end if;

    /*
     * Assign any final six-decimal Gold rounding
     * difference to the last collateral entry.
     */
    if v_remaining_collateral >
       0.000001
    then
        update public.collateral_entry
        set
            debit =
                debit +
                v_remaining_collateral
        where loan_id =
              (
                  select loan_record.id
                  from public.loan
                      loan_record

                  join public.collateral_entry
                      entry_record
                    on entry_record.loan_id =
                       loan_record.id

                  where entry_record.document_number =
                        v_job.document_number

                  order by
                      loan_record.created_at desc,
                      loan_record.id desc

                  limit 1
              )

          and document_number =
              v_job.document_number;

        if not found then
            raise exception
                'LIQUIDATION_COLLATERAL_ALLOCATION_NOT_FOUND';
        end if;

        v_total_collateral :=
            trunc(
                v_total_collateral +
                v_remaining_collateral,
                6
            );

        v_remaining_collateral :=
            0;
    end if;

    if abs(
        v_total_repayment -
        v_job.repayment_required
    ) >
       0.000001
    then
        raise exception
            'LIQUIDATION_REPAYMENT_TOTAL_MISMATCH';
    end if;

    if abs(
        v_total_collateral -
        v_job.collateral_required
    ) >
       0.000001
    then
        raise exception
            'LIQUIDATION_COLLATERAL_TOTAL_MISMATCH';
    end if;

    /*
     * Fetch USD liquidation mappings.
     */
    v_stage :=
        'fetch usd liquidation mappings';

    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_usd_mappings
    from public.fetch_gl_mappings(
        'loan_liquidation'::public."TransactionType"
    ) as mapping_record;

    if v_usd_mappings is null
       or cardinality(
           v_usd_mappings
       ) = 0
    then
        raise exception
            'LOAN_LIQUIDATION_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * USD posting:
     *
     * debit  = debt repayment + penalty
     * credits:
     *   principal
     *   interest
     *   liquidation penalty
     */
    v_usd_components :=
        array_append(
            v_usd_components,

            row(
                'principal'::public."ComponentType",
                v_total_repayment +
                v_job.penalty_amount,
                v_total_principal_paid
            )::public.posting_component
        );

    if v_total_interest_paid > 0 then
        v_usd_components :=
            array_append(
                v_usd_components,

                row(
                    'loan_interest'::public."ComponentType",
                    0,
                    v_total_interest_paid
                )::public.posting_component
            );
    end if;

    if v_job.penalty_amount > 0 then
        v_usd_components :=
            array_append(
                v_usd_components,

                row(
                    'liquidation_fee'::public."ComponentType",
                    0,
                    v_job.penalty_amount
                )::public.posting_component
            );
    end if;

    v_usd_components :=
        public.validate_components(
            v_usd_components
        );

    /*
     * Create the USD financial header.
     */
    v_stage :=
        'create usd financial transaction';

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
        v_job.total_required,
        'usd',
        v_job.country_code
    )
    returning id
    into v_usd_transaction_id;

    /*
     * Post the USD financial entries.
     */
    v_stage :=
        'post usd financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_job.document_number,

        p_country_code =>
            v_job.country_code,

        p_transaction_id =>
            v_usd_transaction_id,

        p_transaction_type =>
            'loan_liquidation'::public."TransactionType",

        p_created_by =>
            'system',

        p_components =>
            v_usd_components,

        p_mappings =>
            v_usd_mappings,

        p_currency_code =>
            'usd',

        p_fiscal_year =>
            v_job.fiscal_year,

        p_period =>
            v_job.period,

        p_reference =>
            v_job.document_number,

        p_deposit_type =>
            null
    );

    /*
     * The Gold sub-document represents the confirmed
     * blockchain collateral transfer.
     */
    v_sub_document_number :=
        v_job.document_number ||
        '-01';

    v_stage :=
        'check gold accounting replay';

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.document_number =
          v_sub_document_number
    limit 1;

    if found then
        raise exception
            'LIQUIDATION_GOLD_DOCUMENT_ALREADY_EXISTS';
    end if;

    /*
     * Fetch Gold sub-transaction mappings.
     */
    v_stage :=
        'fetch gold liquidation mappings';

    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_gold_mappings
    from public.fetch_gl_mappings(
        'loan_liquidation_sub_tx'::public."TransactionType"
    ) as mapping_record;

    if v_gold_mappings is null
       or cardinality(
           v_gold_mappings
       ) = 0
    then
        raise exception
            'LOAN_LIQUIDATION_GOLD_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Gold is a neutral principal movement:
     *
     * debit Gold collateral
     * credit treasury Gold
     */
    v_gold_components :=
        public.build_posting_components(
            'loan_liquidation_sub_tx'::public."TransactionType",
            v_total_collateral,
            v_gold_mappings,
            v_job.country_code,
            'gold',
            false
        );

    if v_gold_components is null
       or cardinality(
           v_gold_components
       ) = 0
    then
        raise exception
            'LOAN_LIQUIDATION_GOLD_COMPONENTS_NOT_FOUND';
    end if;

    v_gold_components :=
        public.validate_components(
            v_gold_components
        );

    /*
     * Create the Gold financial header.
     */
    v_stage :=
        'create gold financial transaction';

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
        v_sub_document_number,
        v_sub_document_number,
        v_job.fiscal_year,
        v_job.period,
        'loan_liquidation_sub_tx'::public."TransactionType",

        format(
            'Confirmed Gold collateral liquidation for user %s',
            v_job.user_id
        ),

        'system',
        v_total_collateral,
        'gold',
        v_job.country_code
    )
    returning id
    into v_gold_transaction_id;

    /*
     * Post the Gold financial entries.
     */
    v_stage :=
        'post gold financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_sub_document_number,

        p_country_code =>
            v_job.country_code,

        p_transaction_id =>
            v_gold_transaction_id,

        p_transaction_type =>
            'loan_liquidation_sub_tx'::public."TransactionType",

        p_created_by =>
            'system',

        p_components =>
            v_gold_components,

        p_mappings =>
            v_gold_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_job.fiscal_year,

        p_period =>
            v_job.period,

        p_reference =>
            v_sub_document_number,

        p_deposit_type =>
            null
    );

    /*
     * Fetch the configured wallet owners for the Gold
     * sub-transaction.
     */
    v_stage :=
        'fetch wallet owner configuration';

    select wallet_owner_record.*
    into v_wallet_owners
    from public.fetch_transaction_type_wallet_owner(
        'loan_liquidation_sub_tx'::public."TransactionType"
    ) as wallet_owner_record;

    if not found then
        raise exception
            'LOAN_LIQUIDATION_WALLET_OWNER_NOT_FOUND';
    end if;

    /*
     * Database-ledger Gold movement:
     *
     * borrower debit
     * country treasury credit
     *
     * The physical blockchain destination remains the
     * one global Gold treasury address.
     */
    v_stage :=
        'post gold wallet entries';

    select
        wallet_result.wallet_entry_count,
        wallet_result.receiver_notification_id
    into
        v_wallet_entry_count,
        v_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_job.fiscal_year,

        p_period =>
            v_job.period,

        p_document_number =>
            v_sub_document_number,

        p_reference =>
            v_sub_document_number,

        p_receiver_id =>
            v_treasury.id,

        p_sender_id =>
            v_job.user_id,

        p_transaction_type =>
            'loan_liquidation_sub_tx'::public."TransactionType",

        p_credit_amount =>
            v_total_collateral,

        p_debit_amount =>
            v_total_collateral,

        p_sender_wallet_owner =>
            v_wallet_owners.sender_wallet_owner,

        p_receiver_wallet_owner =>
            v_wallet_owners.receiver_wallet_owner,

        p_currency_code =>
            'gold',

        p_country_code =>
            v_job.country_code,

        p_audit_action_type =>
            v_wallet_owners.audit_action_type,

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            0,

        p_ip_address =>
            null,

        p_receiver_notification =>
            null,

        p_sender_notification =>
            null
    ) as wallet_result;

    if coalesce(
        v_wallet_entry_count,
        0
    ) < 2
    then
        raise exception
            'LIQUIDATION_GOLD_WALLET_POSTING_FAILED';
    end if;

    /*
     * Reduce the user's current locked collateral.
     */
    v_stage :=
        'reduce locked collateral';

    update public.collateral
    set
        locked_tokens =
            locked_tokens -
            v_total_collateral
    where user_id =
              v_job.user_id

      and locked_tokens >=
              v_total_collateral;

    if not found then
        raise exception
            'COLLATERAL_BALANCE_UPDATE_FAILED';
    end if;

    /*
     * Recalculate remaining active-loan liquidation
     * prices using six decimal places.
     */
    v_stage :=
        'recalculate liquidation prices';

    for v_loan in
        select
            loan_record.id,
            loan_record.liquidation_ltv

        from public.loan
            loan_record

        where loan_record.user_id =
                  v_job.user_id

          and loan_record.status =
                  'active'::public."LoanStatus"

        order by
            loan_record.created_at,
            loan_record.id

        for update
    loop
        select
            greatest(
                coalesce(
                    sum(
                        coalesce(
                            entry_record.debit_principal,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_principal,
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
                            entry_record.debit_interest,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_interest,
                            0
                        )
                    ),
                    0
                ),
                0
            )
        into
            v_remaining_loan_principal,
            v_remaining_loan_interest
        from public.loan_entry
            entry_record
        where entry_record.loan_id =
              v_loan.id;

        select greatest(
            coalesce(
                sum(
                    coalesce(
                        entry_record.credit,
                        0
                    ) -
                    coalesce(
                        entry_record.debit,
                        0
                    )
                ),
                0
            ),
            0
        )
        into v_remaining_loan_collateral
        from public.collateral_entry
            entry_record
        where entry_record.loan_id =
              v_loan.id;

        v_remaining_loan_debt :=
            trunc(
                coalesce(
                    v_remaining_loan_principal,
                    0
                ) +
                coalesce(
                    v_remaining_loan_interest,
                    0
                ),
                6
            );

        v_remaining_loan_collateral :=
            trunc(
                coalesce(
                    v_remaining_loan_collateral,
                    0
                ),
                6
            );

        if v_remaining_loan_debt <= 0
           or v_remaining_loan_collateral <= 0
           or coalesce(
               v_loan.liquidation_ltv,
               0
           ) <= 0
        then
            v_liquidation_price :=
                0;
        else
            v_liquidation_price :=
                trunc(
                    (
                        v_remaining_loan_debt /
                        v_remaining_loan_collateral
                    ) /
                    (
                        v_loan.liquidation_ltv /
                        100
                    ),
                    6
                );
        end if;

        update public.loan
        set
            liquidation_price =
                v_liquidation_price
        where id =
              v_loan.id;
    end loop;

    /*
     * Complete the liquidation job only after every
     * accounting entry and balance update succeeds.
     */
    v_stage :=
        'complete liquidation job';

    update public.liquidation_job
    set
        status =
            'completed'::public."LiquidationJobStatus",

        completed_at =
            now(),

        accounting_started_at =
            null,

        error_message =
            null
    where id =
          v_job.id
    returning *
    into v_job;

    if not found then
        raise exception
            'LIQUIDATION_JOB_COMPLETION_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'already_completed',
        false,

        'job_id',
        v_job.id,

        'document_number',
        v_job.document_number,

        'blockchain_tx_hash',
        v_queue.tx_hash,

        'principal_paid',
        trim_scale(
            v_total_principal_paid
        )::text,

        'interest_paid',
        trim_scale(
            v_total_interest_paid
        )::text,

        'debt_repayment',
        trim_scale(
            v_total_repayment
        )::text,

        'penalty_amount',
        trim_scale(
            v_job.penalty_amount
        )::text,

        'total_proceeds',
        trim_scale(
            v_job.total_required
        )::text,

        'collateral_transferred',
        trim_scale(
            v_total_collateral
        )::text,

        'status',
        v_job.status
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
                    'LIQUIDATION_ACCOUNTING_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
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

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the liquidation accounting stage'
                );
end;
$function$;