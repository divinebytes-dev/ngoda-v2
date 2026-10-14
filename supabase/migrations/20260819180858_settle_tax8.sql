CREATE OR REPLACE FUNCTION public.execute_my_government_tax_settlement_batch(
    p_batch_id text,
    p_ip_address text DEFAULT null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_batch
        public.government_tax_settlement_batch%rowtype;

    v_item
        public.government_tax_settlement_item%rowtype;

    v_treasury public.users%rowtype;
    v_treasury_wallet public.wallet%rowtype;

    v_batch_id text;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;
    v_reference text;

    v_financial_transaction_id
        public.financial_transaction.id%type;

    v_amount numeric;
    v_execution_total numeric := 0;

    v_payable_count integer := 0;
    v_updated_payables integer := 0;
    v_payable_total numeric := 0;

    v_eligible_items integer := 0;
    v_remaining_items integer := 0;

    v_success_count integer := 0;
    v_failed_count integer := 0;

    v_final_status
        public."SettlementStatus";

    v_item_error text;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication and Accounts authorization.
     */
    v_stage :=
        'authorize accounts user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    v_stage :=
        'validate input';

    v_batch_id :=
        nullif(
            btrim(p_batch_id),
            ''
        );

    if v_batch_id is null then
        raise exception
            'SETTLEMENT_BATCH_ID_REQUIRED';
    end if;

    /*
     * Fetch trusted Accounts user.
     */
    v_stage :=
        'fetch accounts user';

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'ACCOUNTS_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'ACCOUNTS_USER_NOT_ACTIVE';
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
     * Lock the batch.
     *
     * This prevents two Accounts users from executing
     * the same batch simultaneously.
     */
    v_stage :=
        'lock tax settlement batch';

    select batch_record.*
    into v_batch
    from public.government_tax_settlement_batch
        batch_record
    where batch_record.id::text =
              v_batch_id

      and lower(
          btrim(
              batch_record.country_code
          )
      ) =
          lower(
              btrim(
                  v_user.country_code
              )
          )
    for update;

    if not found then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_BATCH_NOT_FOUND';
    end if;

    /*
     * Approved batches can be settled.
     * Partial and failed batches can retry failed items.
     */
    if v_batch.status::text not in (
        'approved',
        'partial',
        'failed'
    ) then
        raise exception
            'ONLY_APPROVED_PARTIAL_OR_FAILED_TAX_BATCHES_CAN_BE_SETTLED';
    end if;

    /*
     * Fetch current fiscal period.
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
        v_batch.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch country treasury.
     */
    v_stage :=
        'fetch country treasury';

    select treasury_record.*
    into v_treasury
    from public.fetch_country_treasury(
        v_batch.country_code
    ) as treasury_record;

    if not found
       or v_treasury.id is null
    then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Lock the sender Treasury wallet.
     *
     * Unlike a receiver wallet, a sender wallet must
     * already exist.
     */
    v_stage :=
        'lock treasury wallet';

    select wallet_record.*
    into v_treasury_wallet
    from public.wallet
        wallet_record
    where wallet_record.user_id =
              v_treasury.id

      and lower(
          btrim(
              wallet_record.country_code
          )
      ) =
          lower(
              btrim(
                  v_batch.country_code
              )
          )

      and lower(
          btrim(
              wallet_record.currency_code
          )
      ) =
          lower(
              btrim(
                  v_batch.currency_code
              )
          )

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"
    for update;

    if not found then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;

    if not v_treasury_wallet.is_active then
        raise exception
            'TREASURY_WALLET_NOT_ACTIVE';
    end if;

    /*
     * Lock settlement items eligible for processing.
     */
    v_stage :=
        'lock eligible tax settlement items';

    perform 1
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
              v_batch.id

      and item_record.status::text in (
          'approved',
          'failed'
      )
    for update;

    /*
     * Count eligible items and calculate the amount that
     * will be paid during this execution.
     */
    select
        count(*)::integer,

        coalesce(
            sum(
                item_record.tax_amount
            ),
            0
        )
    into
        v_eligible_items,
        v_execution_total
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
              v_batch.id

      and item_record.status::text in (
          'approved',
          'failed'
      );

    if v_eligible_items = 0 then
        raise exception
            'NO_GOVERNMENT_TAX_SETTLEMENT_ITEMS_TO_PROCESS';
    end if;

    if v_execution_total <= 0 then
        raise exception
            'INVALID_GOVERNMENT_TAX_SETTLEMENT_TOTAL';
    end if;

    /*
     * Validate Treasury funds before paying any item.
     *
     * This prevents some items from succeeding merely
     * because the Treasury wallet ran out of funds
     * halfway through the batch.
     */
    if coalesce(
        v_treasury_wallet.balance,
        0
    ) <
       v_execution_total
    then
        raise exception
            'INSUFFICIENT_TREASURY_WALLET_BALANCE_AVAILABLE_%_REQUIRED_%',
            coalesce(
                v_treasury_wallet.balance,
                0
            ),
            v_execution_total;
    end if;

    /*
     * Fetch Government Tax clearing GL mappings.
     *
     * Expected posting:
     *
     * Dr Government Tax Payable
     * Cr Cash/Bank Reserve
     */
    v_stage :=
        'fetch government tax clearing mappings';

    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_mappings
    from public.fetch_gl_mappings(
        'government_tax_clearing'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GOVERNMENT_TAX_CLEARING_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Fetch document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'government_tax_clearing'::public."TransactionType"
        );

    if nullif(
        btrim(
            v_document_prefix
        ),
        ''
    ) is null
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Mark batch processing.
     */
    v_stage :=
        'mark tax batch processing';

    update public.government_tax_settlement_batch
    set
        status =
            'processing',

        error_message =
            null
    where id =
          v_batch.id;

    if not found then
        raise exception
            'GOVERNMENT_TAX_BATCH_PROCESSING_UPDATE_FAILED';
    end if;

    /*
     * Process approved and previously failed items.
     *
     * Each nested block is a PostgreSQL subtransaction.
     * If one item fails, its own GL and wallet posting is
     * rolled back while other successful items remain.
     */
    for v_item in
        select item_record.*
        from public.government_tax_settlement_item
            item_record
        where item_record.batch_id =
                  v_batch.id

          and item_record.status::text in (
              'approved',
              'failed'
          )
        order by
            item_record.transaction_type,
            item_record.id
        for update
    loop
        begin
            v_item_error :=
                null;

            v_amount :=
                coalesce(
                    v_item.tax_amount,
                    0
                );

            if v_amount <= 0 then
                raise exception
                    'INVALID_GOVERNMENT_TAX_ITEM_AMOUNT';
            end if;

            /*
             * Lock underlying tax payable rows for this
             * transaction type.
             */
            v_stage :=
                'lock underlying tax payables';

            perform 1
            from public.government_tax_payable
                payable_record
            where payable_record.settlement_batch_id =
                      v_batch.id

              and payable_record.transaction_type =
                      v_item.transaction_type

              and lower(
                  btrim(
                      payable_record.currency_code
                  )
              ) =
                  lower(
                      btrim(
                          v_batch.currency_code
                      )
                  )

              and payable_record.is_settled =
                      false
            for update;

            /*
             * Validate that the underlying payable total
             * matches the settlement item.
             */
            select
                count(*)::integer,

                coalesce(
                    sum(
                        payable_record.tax_amount
                    ),
                    0
                )
            into
                v_payable_count,
                v_payable_total
            from public.government_tax_payable
                payable_record
            where payable_record.settlement_batch_id =
                      v_batch.id

              and payable_record.transaction_type =
                      v_item.transaction_type

              and lower(
                  btrim(
                      payable_record.currency_code
                  )
              ) =
                  lower(
                      btrim(
                          v_batch.currency_code
                      )
                  )

              and payable_record.is_settled =
                      false;

            if v_payable_count = 0 then
                raise exception
                    'UNSETTLED_GOVERNMENT_TAX_PAYABLES_NOT_FOUND_FOR_%',
                    v_item.transaction_type::text;
            end if;

            if v_payable_total <>
               v_amount
            then
                raise exception
                    'GOVERNMENT_TAX_AMOUNT_MISMATCH_EXPECTED_%_FOUND_%',
                    v_amount,
                    v_payable_total;
            end if;

            /*
             * Mark the current item processing.
             */
            v_stage :=
                'mark tax settlement item processing';

            update public.government_tax_settlement_item
            set
                status =
                    'processing',

                error_message =
                    null
            where id =
                  v_item.id;

            /*
             * Build GL components for the tax amount.
             */
            v_stage :=
                'build tax clearing components';

            v_components :=
                public.build_posting_components(
                    'government_tax_clearing'::public."TransactionType",
                    v_amount,
                    v_mappings,
                    v_batch.country_code,
                    lower(
                        btrim(
                            v_batch.currency_code
                        )
                    ),
                    false
                );

            if v_components is null
               or cardinality(v_components) = 0
            then
                raise exception
                    'GOVERNMENT_TAX_CLEARING_COMPONENTS_NOT_FOUND';
            end if;

            v_components :=
                public.validate_components(
                    v_components
                );

            /*
             * Generate one financial document per
             * transaction-type settlement item.
             */
            v_stage :=
                'generate tax clearing document number';

            v_document_number :=
                public.generate_document_number(
                    v_document_prefix,
                    v_fiscal_year,
                    v_period,
                    v_batch.country_code
                );

            v_reference :=
                format(
                    '%s_%s',
                    v_batch.document_number,
                    v_item.transaction_type::text
                );

            /*
             * Create financial transaction header.
             */
            v_stage :=
                'create tax clearing transaction';

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
                v_reference,
                v_fiscal_year,
                v_period,
                'government_tax_clearing'::public."TransactionType",

                format(
                    'Government Tax settlement for %s from batch %s',
                    v_item.transaction_type::text,
                    v_batch.document_number
                ),

                v_user.id,
                v_amount,
                lower(
                    btrim(
                        v_batch.currency_code
                    )
                ),
                v_batch.country_code
            )
            returning id
            into v_financial_transaction_id;

            /*
             * Post:
             *
             * Dr Government Tax Payable
             * Cr Cash/Bank Reserve
             */
            v_stage :=
                'post tax clearing financial entries';

            perform *
            from public.post_financial_entries(
                p_document_number =>
                    v_document_number,

                p_country_code =>
                    v_batch.country_code,

                p_transaction_id =>
                    v_financial_transaction_id,

                p_transaction_type =>
                    'government_tax_clearing'::public."TransactionType",

                p_created_by =>
                    v_user.id,

                p_components =>
                    v_components,

                p_mappings =>
                    v_mappings,

                p_currency_code =>
                    lower(
                        btrim(
                            v_batch.currency_code
                        )
                    ),

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
             * Debit only the Treasury wallet.
             *
             * Government does not have an application
             * user wallet, therefore post_wallet_entries
             * is not used for this transaction.
             */
            v_stage :=
                'debit treasury wallet';

            update public.wallet
            set
                balance =
                    balance -
                    v_amount
            where id =
                      v_treasury_wallet.id

              and is_active =
                      true

              and balance >=
                      v_amount;

            if not found then
                raise exception
                    'TREASURY_WALLET_DEBIT_FAILED';
            end if;

            /*
             * Record the outgoing Treasury wallet entry.
             */
            v_stage :=
                'create treasury wallet entry';

            insert into public.wallet_entry (
                document_number,
                reference,
                fiscal_year,
                period,
                transaction_type,
                wallet_id,
                currency_code,
                country_code,
                debit,
                credit,
                created_by
            )
            values (
                v_document_number,
                v_reference,
                v_fiscal_year,
                v_period,
                'government_tax_clearing'::public."TransactionType",
                v_treasury_wallet.id,
                lower(
                    btrim(
                        v_batch.currency_code
                    )
                ),
                v_batch.country_code,
                v_amount,
                0,
                v_user.id
            );

            /*
             * Update Treasury wallet snapshot.
             *
             * The first amount is debit/outgoing.
             * The second amount is credit/incoming.
             */
            v_stage :=
                'update treasury wallet snapshot';

            perform public.update_wallet_balance_snapshot(
                'government_tax_clearing'::public."TransactionType",
                v_treasury.id,
                v_treasury.id,
                null,
                lower(
                    btrim(
                        v_batch.currency_code
                    )
                ),
                'treasury'::public."WalletOwnerType",
                'treasury'::public."WalletOwnerType",
                v_amount,
                0,
                v_fiscal_year,
                v_period,
                v_batch.country_code,
                0
            );

            /*
             * Mark the underlying tax payables settled.
             */
            v_stage :=
                'settle government tax payables';

            update public.government_tax_payable
            set
                is_settled =
                    true,

                settled_at =
                    now(),

                settled_by =
                    v_user.id
            where settlement_batch_id =
                      v_batch.id

              and transaction_type =
                      v_item.transaction_type

              and lower(
                  btrim(
                      currency_code
                  )
              ) =
                  lower(
                      btrim(
                          v_batch.currency_code
                      )
                  )

              and is_settled =
                      false;

            get diagnostics
                v_updated_payables =
                    row_count;

            if v_updated_payables <>
               v_payable_count
            then
                raise exception
                    'GOVERNMENT_TAX_PAYABLE_UPDATE_COUNT_MISMATCH_EXPECTED_%_UPDATED_%',
                    v_payable_count,
                    v_updated_payables;
            end if;

            /*
             * Mark the settlement item successful.
             */
            v_stage :=
                'complete tax settlement item';

            update public.government_tax_settlement_item
            set
                status =
                    'settled',

                paid_at =
                    now(),

                error_message =
                    null
            where id =
                  v_item.id;

            if not found then
                raise exception
                    'GOVERNMENT_TAX_SETTLEMENT_ITEM_UPDATE_FAILED';
            end if;

            v_success_count :=
                v_success_count + 1;

        exception
            when others then
                get stacked diagnostics
                    v_item_error =
                        message_text;

                /*
                 * Any GL, wallet, payable, and item
                 * changes made inside this nested block
                 * have been rolled back.
                 */
                update public.government_tax_settlement_item
                set
                    status =
                        'failed',

                    error_message =
                        left(
                            coalesce(
                                v_item_error,
                                'UNKNOWN_TAX_SETTLEMENT_ERROR'
                            ),
                            1000
                        )
                where id =
                      v_item.id;

                v_failed_count :=
                    v_failed_count + 1;
        end;
    end loop;

    /*
     * Check whether any item remains unsettled.
     */
    v_stage :=
        'calculate final tax batch status';

    select count(*)::integer
    into v_remaining_items
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
              v_batch.id

      and item_record.status::text <>
              'settled';

    if v_remaining_items = 0 then
        v_final_status :=
            'settled'::public."SettlementStatus";

    elsif v_success_count = 0
          and v_failed_count > 0
    then
        v_final_status :=
            'failed'::public."SettlementStatus";

    else
        v_final_status :=
            'partial'::public."SettlementStatus";
    end if;

    /*
     * Complete the batch.
     *
     * paid_at is only populated when at least one tax
     * item was paid successfully.
     */
    v_stage :=
        'complete tax settlement batch';

    update public.government_tax_settlement_batch
    set
        status =
            v_final_status,

        paid_at =
            case
                when v_success_count > 0
                then coalesce(
                    paid_at,
                    now()
                )
                else paid_at
            end,

        error_message =
            case
                when v_final_status::text = 'failed'
                then format(
                    'All %s tax settlement item(s) failed',
                    v_failed_count
                )

                when v_final_status::text = 'partial'
                then format(
                    '%s tax settlement item(s) failed',
                    v_failed_count
                )

                else null
            end
    where id =
          v_batch.id
    returning *
    into v_batch;

    if not found then
        raise exception
            'GOVERNMENT_TAX_BATCH_FINAL_UPDATE_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'batch_id',
        v_batch.id,

        'document_number',
        v_batch.document_number,

        'currency_code',
        v_batch.currency_code,

        'status',
        v_final_status,

        'processed',
        v_success_count +
        v_failed_count,

        'success_count',
        v_success_count,

        'failed_count',
        v_failed_count,

        'remaining_items',
        v_remaining_items
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
                    'GOVERNMENT_TAX_SETTLEMENT_FAILED at [%s]: %s',
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
                    'Check the Government Tax Settlement stage'
                );
end;
$function$;



REVOKE ALL ON FUNCTION
    public.execute_my_government_tax_settlement_batch(
        text,
        text
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.execute_my_government_tax_settlement_batch(
        text,
        text
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.execute_my_government_tax_settlement_batch(
        text,
        text
    )
TO authenticated;

NOTIFY pgrst, 'reload schema';
