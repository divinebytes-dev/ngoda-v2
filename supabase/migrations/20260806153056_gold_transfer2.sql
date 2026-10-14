/*
 * ============================================================
 * GOLD TOKEN TRANSFER
 *
 * Blockchain recording and accounting completion.
 * ============================================================
 */


/*
 * ============================================================
 * 1. RECORD CONFIRMED BLOCKCHAIN TRANSACTION AS PENDING
 * ============================================================
 */

create or replace function public.record_gold_transfer_blockchain_transaction(
    p_sender_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_tx_hash text,
    p_explorer_url text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_preparation record;

    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;

    v_blockchain_transaction_id text;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_tx_hash is null
       or btrim(p_tx_hash) = ''
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_HASH_IS_REQUIRED';
    end if;

    if p_explorer_url is null
       or btrim(p_explorer_url) = ''
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_IS_REQUIRED';
    end if;

    /*
     * Rebuild and validate all trusted transfer values.
     */
    select preparation_record.*
    into v_preparation
    from public.prepare_gold_transfer(
        p_sender_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation_record;

    if not found then
        raise exception
            'GOLD_TRANSFER_PREPARATION_NOT_FOUND';
    end if;

    v_sender :=
        public.fetch_user_by_id(
            v_preparation.sender_id
        );

    v_receiver :=
        public.fetch_user_by_id(
            v_preparation.receiver_id
        );

    if v_sender.id is null then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_receiver.id is null then
        raise exception
            'RECEIVER_NOT_FOUND';
    end if;

    /*
     * The blockchain transaction has already been confirmed,
     * but it remains pending until database accounting commits.
     */
    begin
        insert into public.blockchain_transaction (
            tx_hash,
            fiscal_year,
            period,
            transaction_type,
            chain,
            sender,
            receiver,
            quantity,
            gross_amount,
            net_amount,
            fee_amount,
            currency_code,
            explorer_url,
            status,
            created_by,
            country_code,
            reference,
            description
        )
        values (
            btrim(p_tx_hash),
            v_preparation.fiscal_year,
            v_preparation.period,
            'gold_token_transfer'::public."TransactionType",
            'chiado',
            v_preparation.sender_wallet_address,
            v_preparation.receiver_wallet_address,
            v_preparation.amount::numeric,
            0,
            0,
            v_preparation.fee::numeric,
            'gold',
            btrim(p_explorer_url),
            'pending'::public."BlockchainTxStatus",
            v_preparation.sender_id,
            v_preparation.country_code,
            p_transaction ->> 'r',
            'User ' ||
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ) ||
            ' transferred ' ||
            v_preparation.amount ||
            'g Gold tokens to user ' ||
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        )
        returning id::text
        into v_blockchain_transaction_id;

    exception
        when unique_violation then
            raise exception
                'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    end;

    if v_blockchain_transaction_id is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    end if;

    return v_blockchain_transaction_id;
end;
$function$;


/*
 * ============================================================
 * 2. COMPLETE GOLD TRANSFER ACCOUNTING
 * ============================================================
 */

create or replace function public.complete_gold_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_transaction_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    document_number text,
    amount text,
    fee text,
    explorer_url text,

    receiver_notification_id text,
    device_tokens text[],

    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_preparation record;

    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_sender_notification
        public.notification_message;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;

    v_reference text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
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
     * Recalculate and validate all trusted values.
     *
     * prepare_gold_transfer also locks the processing
     * transaction state.
     */
    v_stage :=
        'prepare gold transfer';

    select preparation_record.*
    into v_preparation
    from public.prepare_gold_transfer(
        p_sender_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation_record;

    if not found then
        raise exception
            'GOLD_TRANSFER_PREPARATION_NOT_FOUND';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    /*
     * Lock the pending blockchain transaction.
     */
    v_stage :=
        'lock blockchain transaction';

    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction blockchain_record
    where blockchain_record.id::text =
          p_blockchain_transaction_id
      and blockchain_record.created_by =
          p_sender_id
      and blockchain_record.reference =
          v_reference
      and blockchain_record.transaction_type =
          'gold_token_transfer'::public."TransactionType"
      and blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    for update;

    if not found then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION';
    end if;

    /*
     * Ensure the pending blockchain record contains the
     * same values recalculated by the database.
     */
    v_stage :=
        'validate blockchain transaction';

    if lower(
        v_blockchain_transaction.sender
    ) is distinct from lower(
        v_preparation.sender_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_SENDER_MISMATCH';
    end if;

    if lower(
        v_blockchain_transaction.receiver
    ) is distinct from lower(
        v_preparation.receiver_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_RECEIVER_MISMATCH';
    end if;

    if v_blockchain_transaction.quantity
       is distinct from
       v_preparation.amount::numeric
    then
        raise exception
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    end if;

    if coalesce(
        v_blockchain_transaction.fee_amount,
        0
    ) is distinct from
       v_preparation.fee::numeric
    then
        raise exception
            'BLOCKCHAIN_FEE_MISMATCH';
    end if;

    if lower(
        btrim(
            v_blockchain_transaction.currency_code
        )
    ) is distinct from 'gold'
    then
        raise exception
            'INVALID_BLOCKCHAIN_CURRENCY';
    end if;

    /*
     * Fetch users for descriptions and notifications.
     */
    v_stage :=
        'fetch transfer users';

    v_sender :=
        public.fetch_user_by_id(
            v_preparation.sender_id
        );

    v_receiver :=
        public.fetch_user_by_id(
            v_preparation.receiver_id
        );

    if v_sender.id is null then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_receiver.id is null then
        raise exception
            'RECEIVER_NOT_FOUND';
    end if;

    /*
     * Build notification messages.
     */
    v_stage :=
        'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_transfer'::public."TransactionType",
            'sender'::public."NotificationAudience",
            v_preparation.amount::numeric,
            'GOLD',
            v_reference || '-01',
            v_preparation.amount::numeric,
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    v_stage :=
        'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_transfer'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.amount::numeric,
            'GOLD',
            v_reference || '-02',
            v_preparation.amount::numeric,
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    v_stage :=
        'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_receiver.id
            ),
            array[]::text[]
        );

    /*
     * Generate the accounting document number.
     */
    v_stage :=
        'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    if v_document_number is null
       or btrim(v_document_number) = ''
    then
        raise exception
            'DOCUMENT_NUMBER_GENERATION_FAILED';
    end if;

    /*
     * Create financial transaction header.
     */
    v_stage :=
        'insert financial transaction';

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
        v_reference,
        v_preparation.period,
        'gold_token_transfer'::public."TransactionType",
        'User ' ||
        coalesce(
            v_sender.email,
            v_sender.phone,
            v_sender.id
        ) ||
        ' transferred ' ||
        v_preparation.amount ||
        'g Gold tokens to user ' ||
        coalesce(
            v_receiver.email,
            v_receiver.phone,
            v_receiver.id
        ),
        v_sender.id,
        v_preparation.total_amount::numeric,
        'gold',
        v_preparation.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post Gold GL entries.
     */
    v_stage :=
        'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",

        p_created_by =>
            v_sender.id,

        p_components =>
            v_preparation.components,

        p_mappings =>
            v_preparation.mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );

    /*
     * Correct wallet movement:
     *
     * Sender customer Gold wallet:
     *   debit amount + fee
     *
     * Receiver customer Gold wallet:
     *   credit amount
     *
     * Treasury Gold wallet:
     *   credit fee
     */
    v_stage :=
        'post wallet entries';

    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_receiver.id,

        p_sender_id =>
            v_sender.id,

        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",

        p_credit_amount =>
            v_preparation.amount::numeric,

        p_debit_amount =>
            v_preparation.total_amount::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            'gold',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_transferred'::public."AuditActionType",

        p_treasury_id =>
            v_preparation.treasury_id,

        p_fee_amount =>
            v_preparation.fee::numeric,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification
    ) as result;

    /*
     * Mark the blockchain transaction completed.
     */
    v_stage :=
        'complete blockchain transaction';

    update public.blockchain_transaction
    set
        document_number =
            v_document_number,

        status =
            'completed'::public."BlockchainTxStatus",

        updated_at =
            now()
    where id::text =
          p_blockchain_transaction_id
      and status =
          'pending'::public."BlockchainTxStatus";

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    end if;

    /*
     * Mark the application transaction successful.
     */
    v_stage :=
        'complete transaction state';

    update public.transaction_state
    set
        user_id =
            v_receiver.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_sender_id
      and transaction_type =
          'gold_token_transfer'::public."TransactionType"
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    /*
     * Return only the information required by the Edge
     * Function for its response and push notification.
     */
    v_stage :=
        'return gold transfer result';

    return query
    select
        true,
        v_document_number,
        v_preparation.amount,
        v_preparation.fee,
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
                    'GOLD_TRANSFER_FAILED at [%s]: %s',
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
                    'Check the Gold Transfer stage reported in the error'
                );
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.record_gold_transfer_blockchain_transaction(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
owner to postgres;

alter function public.complete_gold_transfer(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
owner to postgres;


revoke all
on function public.record_gold_transfer_blockchain_transaction(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
from public, anon, authenticated, service_role;

revoke all
on function public.complete_gold_transfer(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
from public, anon, authenticated, service_role;


grant execute
on function public.record_gold_transfer_blockchain_transaction(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
to service_role;

grant execute
on function public.complete_gold_transfer(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
to service_role;