CREATE OR REPLACE FUNCTION public.execute_my_agent_commission_settlement_batch(p_batch_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_batch public.agent_settlement_batch%rowtype;
    v_item public.agent_settlement_item%rowtype;
    v_agent public.users%rowtype;
    v_treasury public.users%rowtype;
    v_receiver_wallet public.wallet%rowtype;

    v_batch_id text;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_document_prefix text;
    v_document_number text;
    v_reference text;

    v_financial_transaction_id
        public.financial_transaction.id%type;

    v_amount numeric;

    v_commission_rows integer := 0;
    v_commission_total numeric := 0;

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
        btrim(v_user.country_code),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Lock the batch.
     *
     * The row lock prevents two Accounts users from
     * executing the same batch concurrently.
     */
    v_stage :=
        'lock settlement batch';

    select batch_record.*
    into v_batch
    from public.agent_settlement_batch
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
            'AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND';
    end if;

    if v_batch.status::text not in (
        'approved',
        'partial'
    ) then
        raise exception
            'ONLY_APPROVED_OR_PARTIAL_BATCHES_CAN_BE_SETTLED';
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
     * Fetch the country treasury.
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
     * Fetch GL mappings.
     *
     * Expected principal mapping:
     *
     * Dr Agent Commission Payable
     * Cr Cash/Bank Reserve
     */
    v_stage :=
        'fetch gl mappings';

    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_mappings
    from public.fetch_gl_mappings(
        'agent_commission_settlement'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'AGENT_COMMISSION_SETTLEMENT_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Fetch and validate wallet-owner configuration.
     *
     * Commission is paid from Treasury into the
     * facilitator's customer wallet.
     */
    v_stage :=
        'fetch wallet owner configuration';

    select wallet_owner_record.*
    into v_wallet_owners
    from public.fetch_transaction_type_wallet_owner(
        'agent_commission_settlement'::public."TransactionType"
    ) as wallet_owner_record;

    if not found then
        raise exception
            'AGENT_COMMISSION_SETTLEMENT_WALLET_OWNER_NOT_FOUND';
    end if;

    if v_wallet_owners.sender_wallet_owner <>
       'treasury'::public."WalletOwnerType"
    then
        raise exception
            'AGENT_COMMISSION_SETTLEMENT_SENDER_WALLET_MUST_BE_TREASURY';
    end if;

    if v_wallet_owners.receiver_wallet_owner <>
       'customer'::public."WalletOwnerType"
    then
        raise exception
            'AGENT_COMMISSION_SETTLEMENT_RECEIVER_WALLET_MUST_BE_CUSTOMER';
    end if;

    /*
     * Fetch document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'agent_commission_settlement'::public."TransactionType"
        );

    if nullif(
        btrim(v_document_prefix),
        ''
    ) is null
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Count items eligible for this execution.
     *
     * Failed items are included so a partial batch can
     * retry only its failed payments.
     */
    v_stage :=
        'count eligible settlement items';

    select count(*)::integer
    into v_eligible_items
    from public.agent_settlement_item
        item_record
    where item_record.batch_id =
              v_batch.id

      and item_record.status::text in (
          'approved',
          'failed'
      );

    if v_eligible_items = 0 then
        raise exception
            'NO_AGENT_COMMISSION_SETTLEMENT_ITEMS_TO_PROCESS';
    end if;

    /*
     * Mark the batch as processing.
     */
    v_stage :=
        'mark batch processing';

    update public.agent_settlement_batch
    set
        status =
            'processing'::public."SettlementStatus",

        error_message =
            null
    where id =
          v_batch.id;

    if not found then
        raise exception
            'AGENT_COMMISSION_BATCH_PROCESSING_UPDATE_FAILED';
    end if;

    /*
     * Process each approved or previously failed item.
     *
     * The nested begin/exception block is a PostgreSQL
     * subtransaction. Failure rolls back only the
     * current item's accounting and wallet movements.
     */
    for v_item in
        select item_record.*
        from public.agent_settlement_item
            item_record
        where item_record.batch_id =
                  v_batch.id

          and item_record.status::text in (
              'approved',
              'failed'
          )
        order by
            item_record.agent_id,
            item_record.id
        for update
    loop
        begin
            v_item_error :=
                null;

            v_amount :=
                coalesce(
                    v_item.total_commission,
                    0
                );

            if v_amount <= 0 then
                raise exception
                    'INVALID_AGENT_COMMISSION_SETTLEMENT_AMOUNT';
            end if;

    /*
    * Validate the facilitator.
    *
    * Agent, vendor and merchant roles can earn
    * cash-withdrawal commission.
    */
    v_stage :=
        'validate settlement recipient';

    select agent_record.*
    into v_agent
    from public.users
        agent_record
    join public.user_role
        role_record
    on role_record.id =
        agent_record.role_id
    where agent_record.id =
            v_item.agent_id

    and agent_record.status =
            'active'::public."UserStatus"

    and lower(
        btrim(
            agent_record.country_code
        )
    ) =
        lower(
            btrim(
                v_batch.country_code
            )
        )

    and lower(
        role_record.name::text
    ) in (
        'agent',
        'vendor',
        'merchant'
    )
    limit 1;

    if not found then
        raise exception
            'COMMISSION_RECIPIENT_NOT_AUTHORIZED_%',
            v_item.agent_id;
    end if;

    /*
    * Do not require the receiver wallet to exist here.
    *
    * post_wallet_entries creates the customer wallet when
    * it does not exist. Only the sender treasury wallet is
    * required to exist before posting.
    */

    /*
    * Lock and validate the underlying commission records.
    */
    v_stage :=
        'lock underlying commissions';

    perform 1
    from public.agent_commission
        commission_record
    where commission_record.settlement_batch_id =
            v_batch.id

    and commission_record.agent_id =
            v_agent.id

    and lower(
        btrim(
            commission_record.currency_code
        )
    ) =
        lower(
            btrim(
                v_batch.currency_code
            )
        )

    and commission_record.is_settled =
            false
    for update;
            /*
             * Mark this item as processing.
             */
            v_stage :=
                'mark settlement item processing';

            update public.agent_settlement_item
            set
                status =
                    'processing'::public."SettlementStatus",

                error_message =
                    null
            where id =
                  v_item.id;

            /*
             * Build the GL posting components.
             */
            v_stage :=
                'build posting components';

            v_components :=
                public.build_posting_components(
                    'agent_commission_settlement'::public."TransactionType",
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
                    'AGENT_COMMISSION_SETTLEMENT_COMPONENTS_NOT_FOUND';
            end if;

            v_components :=
                public.validate_components(
                    v_components
                );

            /*
             * Generate one financial document for this
             * settlement item.
             */
            v_stage :=
                'generate document number';

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
                    v_agent.id
                );

            /*
             * Create financial transaction header.
             */
            v_stage :=
                'create financial transaction';

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
                'agent_commission_settlement'::public."TransactionType",

                format(
                    'Commission settlement for facilitator %s from batch %s',
                    v_agent.id,
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
             * Dr Agent Commission Payable
             * Cr Cash/Bank Reserve
             */
            v_stage :=
                'post financial entries';

            perform *
            from public.post_financial_entries(
                p_document_number =>
                    v_document_number,

                p_country_code =>
                    v_batch.country_code,

                p_transaction_id =>
                    v_financial_transaction_id,

                p_transaction_type =>
                    'agent_commission_settlement'::public."TransactionType",

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
             * Wallet posting:
             *
             * Dr/outgoing Treasury wallet
             * Cr/incoming Customer wallet
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
                    v_agent.id,

                p_sender_id =>
                    v_treasury.id,

                p_transaction_type =>
                    'agent_commission_settlement'::public."TransactionType",

                p_credit_amount =>
                    v_amount,

                p_debit_amount =>
                    v_amount,

                p_sender_wallet_owner =>
                    'treasury'::public."WalletOwnerType",

                p_receiver_wallet_owner =>
                    'customer'::public."WalletOwnerType",

                p_currency_code =>
                    lower(
                        btrim(
                            v_batch.currency_code
                        )
                    ),

                p_country_code =>
                    v_batch.country_code,

                p_audit_action_type =>
                    v_wallet_owners.audit_action_type,

                p_treasury_id =>
                    v_treasury.id,

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
             * Mark underlying commission records settled.
             */
            v_stage :=
                'settle underlying commissions';

            update public.agent_commission
            set
                is_settled =
                    true,

                settled_at =
                    now(),

                settled_by =
                    v_user.id
            where settlement_batch_id =
                      v_batch.id

              and agent_id =
                      v_agent.id

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
                v_commission_rows =
                    row_count;

            if v_commission_rows = 0 then
                raise exception
                    'AGENT_COMMISSION_ROWS_NOT_UPDATED';
            end if;

            /*
             * Mark the settlement item successful.
             */
            v_stage :=
                'complete settlement item';

            update public.agent_settlement_item
            set
                status =
                    'settled'::public."SettlementStatus",

                paid_at =
                    now(),

                error_message =
                    null
            where id =
                  v_item.id;

            if not found then
                raise exception
                    'AGENT_COMMISSION_SETTLEMENT_ITEM_UPDATE_FAILED';
            end if;

            v_success_count :=
                v_success_count + 1;

        exception
            when others then
                get stacked diagnostics
                    v_item_error =
                        message_text;

                /*
                 * The nested block rollback has removed
                 * any partial GL and wallet movements for
                 * this item. Only the failed status is
                 * stored outside that subtransaction.
                 */
                update public.agent_settlement_item
                set
                    status =
                        'failed'::public."SettlementStatus",

                    error_message =
                        left(
                            coalesce(
                                v_item_error,
                                'UNKNOWN_SETTLEMENT_ERROR'
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
     * Determine whether any item remains unsettled.
     */
    v_stage :=
        'calculate final batch status';

    select count(*)::integer
    into v_remaining_items
    from public.agent_settlement_item
        item_record
    where item_record.batch_id =
              v_batch.id

      and item_record.status::text <>
              'settled';

    if v_remaining_items = 0 then
        v_final_status :=
            'settled'::public."SettlementStatus";
    else
        v_final_status :=
            'partial'::public."SettlementStatus";
    end if;

    /*
     * Complete the batch.
     *
     * paid_at records that payment processing occurred,
     * including partially successful execution.
     */
    v_stage :=
        'complete settlement batch';

    update public.agent_settlement_batch
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
                when v_final_status::text = 'partial'
                then format(
                    '%s settlement item(s) failed',
                    v_failed_count
                )
                else null
            end
    where id =
          v_batch.id
    returning *
    into v_batch;

    /*
     * Audit the execution.
     */
    v_stage :=
        'create audit log';

    insert into public.audit_log (
        user_id,
        country_code,
        fiscal_year,
        period,
        action_type,
        entity_type,
        entity_id,
        document_number,
        metadata,
        ip_address
    )
    values (
        v_user.id,
        v_batch.country_code,
        v_fiscal_year,
        v_period,
        'agent_settlement_settled'::public."AuditActionType",
        'agent_settlement_batch',
        v_batch.id::text,
        v_batch.document_number,

        jsonb_build_object(
            'processed',
            v_success_count +
            v_failed_count,

            'success_count',
            v_success_count,

            'failed_count',
            v_failed_count,

            'remaining_items',
            v_remaining_items,

            'status',
            v_final_status
        ),

        p_ip_address
    );

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
                    'AGENT_COMMISSION_SETTLEMENT_FAILED at [%s]: %s',
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
                    'Check the Agent Commission Settlement stage'
                );
end;
$function$
