CREATE OR REPLACE FUNCTION public.complete_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_transaction_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, quantity text, total_spent text, explorer_url text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_preparation record;

    v_transaction_state
        public.transaction_state%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_fiat_mappings
        public.transaction_gl_mapping[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_fiat_components
        public.posting_component[];

    v_token_components
        public.posting_component[];

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_number text;
    v_sub_document_number text;

    v_fiat_transaction_id bigint;
    v_token_transaction_id bigint;

    v_receiver_notification_id text;

    v_sub_transaction_type
        public."TransactionType" :=
            'gold_token_buy_sub_tx'::public."TransactionType";

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Lock the processing transaction state.
     */
    v_stage :=
        'validate and lock transaction state';

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state
        transaction_state_record
    where transaction_state_record.id =
          p_transaction_state_id
      and transaction_state_record.created_by =
          p_user_id
      and transaction_state_record.user_id =
          p_user_id
      and transaction_state_record.country_code =
          p_country_code
      and transaction_state_record.transaction_type =
          'gold_token_buy'::public."TransactionType"
      and transaction_state_record.status =
          'processing'::public."TransactionStatus"
    limit 1
    for update;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    if v_transaction_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;

    /*
     * Lock and validate the pending blockchain row.
     */
    v_stage :=
        'validate and lock blockchain transaction';

    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          p_blockchain_transaction_id
      and blockchain_record.created_by =
          p_user_id
      and blockchain_record.country_code =
          p_country_code
      and blockchain_record.reference =
          p_transaction ->> 'r'
      and blockchain_record.transaction_type =
          'gold_token_buy'::public."TransactionType"
      and blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    limit 1
    for update;

    if not found then
        raise exception
            'PENDING_BLOCKCHAIN_TRANSACTION_NOT_FOUND';
    end if;

    /*
     * Recalculate trusted pricing and quantities.
     */
    v_stage := 'prepare gold buy';

    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation;

    if not found then
        raise exception
            'GOLD_BUY_PREPARATION_NOT_FOUND';
    end if;

    /*
     * Validate the transaction Gold price carried forward
     * from prepare_gold_buy.
     *
     * Do not fetch the current Gold market price again here.
     */
    if coalesce(
        v_preparation.gold_price::numeric,
        0
    ) <= 0
    then
        raise exception
            'INVALID_GOLD_PRICE';
    end if;

    /*
     * Confirm the blockchain row matches the trusted
     * preparation result.
     */
    v_stage :=
        'validate blockchain transaction values';

    if v_blockchain_transaction.quantity
       is distinct from
       v_preparation.token_quantity::numeric
    then
        raise exception
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    end if;

    if v_blockchain_transaction.gross_amount
       is distinct from
       v_preparation.input_amount::numeric
    then
        raise exception
            'BLOCKCHAIN_GROSS_AMOUNT_MISMATCH';
    end if;

    if v_blockchain_transaction.fee_amount
       is distinct from
       v_preparation.token_fee::numeric
    then
        raise exception
            'BLOCKCHAIN_FEE_MISMATCH';
    end if;

    if lower(
        v_blockchain_transaction.sender
    ) is distinct from lower(
        v_preparation.treasury_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_SENDER_MISMATCH';
    end if;

    if lower(
        v_blockchain_transaction.receiver
    ) is distinct from lower(
        v_preparation.user_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_RECEIVER_MISMATCH';
    end if;

    /*
     * Fetch participants.
     */
    v_stage := 'fetch participants';

    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    /*
     * Rebuild fiat and token components for posting.
     */
    v_stage := 'fetch fiat mappings';

    select array_agg(mapping_record)
    into v_fiat_mappings
    from public.fetch_gl_mappings(
        'gold_token_buy'::public."TransactionType"
    ) as mapping_record;

    if v_fiat_mappings is null
       or cardinality(v_fiat_mappings) = 0
    then
        raise exception
            'GOLD_BUY_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'fetch token mappings';

    select array_agg(mapping_record)
    into v_token_mappings
    from public.fetch_gl_mappings(
        v_sub_transaction_type
    ) as mapping_record;

    if v_token_mappings is null
       or cardinality(v_token_mappings) = 0
    then
        raise exception
            'GOLD_BUY_TOKEN_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'build fiat components';

    v_fiat_components :=
        public.build_posting_components(
            'gold_token_buy'::public."TransactionType",
            v_preparation.input_amount::numeric,
            v_fiat_mappings,
            p_country_code,
            v_preparation.input_currency,
            false
        );

    v_stage := 'build token components';

    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_preparation.input_amount::numeric,
            v_token_mappings,
            p_country_code,
            v_preparation.input_currency,
            true
        );

    if v_fiat_components is null
       or cardinality(v_fiat_components) = 0
    then
        raise exception
            'GOLD_BUY_COMPONENTS_NOT_FOUND';
    end if;

    if v_token_components is null
       or cardinality(v_token_components) = 0
    then
        raise exception
            'GOLD_BUY_TOKEN_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Build buyer notification.
     */
    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            'gold_token_buy'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.gross_amount::numeric,
            'USD',
            p_transaction ->> 'r',
            v_preparation.token_quantity::numeric,
            coalesce(
                v_treasury.email,
                v_treasury.phone,
                v_treasury.id
            ),
            coalesce(
                v_user.email,
                v_user.phone,
                v_user.id
            )
        );

    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_user.id
            ),
            array[]::text[]
        );

    /*
     * Generate the main accounting document.
     */
    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            p_country_code
        );

    /*
     * Fiat financial transaction.
     */
    v_stage :=
        'insert fiat financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        reference,
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
        v_preparation.fiscal_year,
        p_transaction ->> 'r',
        v_preparation.period,
        'gold_token_buy'::public."TransactionType",
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.token_quantity ||
        'g Gold tokens at USD ' ||
        v_preparation.gold_price ||
        '/g',
        p_user_id,
        v_preparation.gross_amount::numeric,
        'usd',
        p_country_code
    )
    returning id
    into v_fiat_transaction_id;

    v_stage := 'post fiat financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            p_country_code,

        p_transaction_id =>
            v_fiat_transaction_id,

        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",

        p_created_by =>
            p_user_id,

        p_components =>
            v_fiat_components,

        p_mappings =>
            v_fiat_mappings,

        p_currency_code =>
            'usd',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            p_transaction ->> 'r',

        p_deposit_type =>
            null
    );

    /*
     * Move fiat from the buyer's customer wallet to
     * the treasury USD wallet.
     */
    v_stage := 'post fiat wallet entries';

    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_document_number,

        p_reference =>
            p_transaction ->> 'r',

        p_receiver_id =>
            v_treasury.id,

        p_sender_id =>
            v_user.id,

        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",

        p_credit_amount =>
            v_preparation.gross_amount::numeric,

        p_debit_amount =>
            v_preparation.gross_amount::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_currency_code =>
            'usd',

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            'token_bought'::public."AuditActionType",

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
     * Gold-token sub-document.
     */
    v_sub_document_number :=
        v_document_number || '-01';

    v_stage :=
        'insert token financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        reference,
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
        v_preparation.fiscal_year,
        (p_transaction ->> 'r') || '-01',
        v_preparation.period,
        v_sub_transaction_type,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.gross_amount ||
        ' USD Gold tokens',
        p_user_id,
        v_preparation.gross_token_quantity::numeric,
        'gold',
        p_country_code
    )
    returning id
    into v_token_transaction_id;

    v_stage := 'post token financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_sub_document_number,

        p_country_code =>
            p_country_code,

        p_transaction_id =>
            v_token_transaction_id,

        p_transaction_type =>
            v_sub_transaction_type,

        p_created_by =>
            p_user_id,

        p_components =>
            v_token_components,

        p_mappings =>
            v_token_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            (p_transaction ->> 'r') || '-01',

        p_deposit_type =>
            null
    );

    /*
     * Move the net token quantity from treasury to buyer.
     */
    v_stage := 'post token wallet entries';

    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_sub_document_number,

        p_reference =>
            (p_transaction ->> 'r') || '-01',

        p_receiver_id =>
            v_user.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",

        p_credit_amount =>
            v_preparation.token_quantity::numeric,

        p_debit_amount =>
            v_preparation.token_quantity::numeric,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            'gold',

        p_country_code =>
            p_country_code,

        p_audit_action_type =>
            'token_bought'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    ) as result;

    /*
     * Complete the blockchain row.
     */
    v_stage :=
        'complete blockchain transaction';

    update public.blockchain_transaction
    set
        document_number =
            v_sub_document_number,

        status =
            'completed'::public."BlockchainTxStatus"
    where id::text =
          p_blockchain_transaction_id
      and status =
          'pending'::public."BlockchainTxStatus";

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    end if;

    /*
     * Mark transaction state successful.
     */
    v_stage := 'update transaction state';

    update public.transaction_state
    set
        user_id =
            v_user.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_user_id
      and transaction_type =
          'gold_token_buy'::public."TransactionType"
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    return query
    select
        true,
        v_document_number,
        v_preparation.token_quantity,
        v_preparation.gross_amount,
        v_blockchain_transaction.explorer_url,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload
            ->> 'reference';

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
                    'GOLD_BUY_FAILED at [%s]: %s',
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
                    'Check the gold-buy stage reported in the error'
                );
end;
$function$
