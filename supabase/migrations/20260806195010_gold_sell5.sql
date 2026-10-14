create or replace function public.complete_gold_sell(
    p_seller_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_transaction_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    document_number text,
    token_document_number text,
    quantity text,
    gross_amount text,
    net_amount text,
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

    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_number text;
    v_token_document_number text;

    v_financial_transaction_id bigint;
    v_token_financial_transaction_id bigint;

    v_receiver_notification_id text;

    v_reference text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the Edge Function's service-role client may
     * execute the privileged accounting function.
     */
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
     * Recalculate all trusted Gold Sell values.
     *
     * prepare_gold_sell also locks and validates the
     * processing transaction state.
     */
    v_stage :=
        'prepare gold sell';

    select preparation_record.*
    into v_preparation
    from public.prepare_gold_sell(
        p_seller_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation_record;

    if not found then
        raise exception
            'GOLD_SELL_PREPARATION_NOT_FOUND';
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
          p_seller_id
      and blockchain_record.reference =
          v_reference
      and blockchain_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      and blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    for update;

    if not found then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION';
    end if;

    /*
     * Validate blockchain values against the database
     * recalculation.
     */
    v_stage :=
        'validate blockchain transaction';

    if lower(
        v_blockchain_transaction.sender
    ) is distinct from lower(
        v_preparation.seller_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_SELLER_MISMATCH';
    end if;

    if lower(
        v_blockchain_transaction.receiver
    ) is distinct from lower(
        v_preparation.treasury_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_TREASURY_MISMATCH';
    end if;

    if v_blockchain_transaction.quantity
       is distinct from
       v_preparation.token_quantity::numeric
    then
        raise exception
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    end if;

    if coalesce(
        v_blockchain_transaction.gross_amount,
        0
    ) is distinct from
       v_preparation.gross_amount::numeric
    then
        raise exception
            'BLOCKCHAIN_GROSS_AMOUNT_MISMATCH';
    end if;

    if coalesce(
        v_blockchain_transaction.net_amount,
        0
    ) is distinct from
       v_preparation.net_amount::numeric
    then
        raise exception
            'BLOCKCHAIN_NET_AMOUNT_MISMATCH';
    end if;

    if coalesce(
        v_blockchain_transaction.fee_amount,
        0
    ) is distinct from
       v_preparation.token_fee_equivalent::numeric
    then
        raise exception
            'BLOCKCHAIN_FEE_AMOUNT_MISMATCH';
    end if;

    /*
     * Fetch the trusted seller and treasury records.
     */
    v_stage :=
        'fetch seller and treasury';

    v_seller :=
        public.fetch_user_by_id(
            v_preparation.seller_id
        );

    v_treasury :=
        public.fetch_user_by_id(
            v_preparation.treasury_id
        );

    if v_seller.id is null then
        raise exception
            'SELLER_NOT_FOUND';
    end if;

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * The seller is the receiver of the fiat wallet
     * movement, so the seller notification belongs to
     * that wallet posting.
     */
    v_stage :=
        'create seller notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_sell'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.net_amount::numeric,
            'USD',
            v_reference,
            v_preparation.token_quantity::numeric,
            coalesce(
                v_treasury.email,
                v_treasury.phone,
                v_treasury.id
            ),
            coalesce(
                v_seller.email,
                v_seller.phone,
                v_seller.id
            )
        );

    v_stage :=
        'fetch seller device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_seller.id
            ),
            array[]::text[]
        );

    /*
     * Generate the main fiat document number.
     */
    v_stage :=
        'generate main document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    if v_document_number is null
       or btrim(
           v_document_number
       ) = ''
    then
        raise exception
            'DOCUMENT_NUMBER_GENERATION_FAILED';
    end if;

    v_token_document_number :=
        v_document_number || '-01';

    /*
     * ========================================================
     * FIAT ACCOUNTING
     * ========================================================
     */

    v_stage :=
        'insert fiat financial transaction';

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
        v_preparation.fiscal_year,
        v_preparation.period,
        v_reference,
        'gold_token_sell'::public."TransactionType",
        'User ' ||
        coalesce(
            v_seller.email,
            v_seller.phone,
            v_seller.id
        ) ||
        ' sold ' ||
        v_preparation.token_quantity ||
        'g Gold tokens',
        v_seller.id,
        v_preparation.gross_amount::numeric,
        'usd',
        v_preparation.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post fiat-side GL entries.
     */
    v_stage :=
        'post fiat financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_created_by =>
            v_seller.id,

        p_components =>
            v_preparation.sell_components,

        p_mappings =>
            v_preparation.sell_mappings,

        p_currency_code =>
            'usd',

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
     * Treasury pays the seller the calculated net fiat
     * amount.
     *
     * The configured fee, spread and tax remain represented
     * by the financial components.
     */
    v_stage :=
        'post fiat wallet entries';

    select wallet_result.receiver_notification_id
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
            v_seller.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_credit_amount =>
            v_preparation.net_amount::numeric,

        p_debit_amount =>
            v_preparation.net_amount::numeric,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            'usd',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_sold'::public."AuditActionType",

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
    ) as wallet_result;

    /*
     * ========================================================
     * GOLD TOKEN ACCOUNTING
     * ========================================================
     */

    v_stage :=
        'insert token financial transaction';

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
        v_token_document_number,
        v_preparation.fiscal_year,
        v_preparation.period,
        v_reference || '-01',
        'gold_token_sell_sub_tx'::public."TransactionType",
        'User ' ||
        coalesce(
            v_seller.email,
            v_seller.phone,
            v_seller.id
        ) ||
        ' transferred ' ||
        v_preparation.token_quantity ||
        'g Gold tokens to treasury',
        v_seller.id,
        v_preparation.token_quantity::numeric,
        'gold',
        v_preparation.country_code
    )
    returning id
    into v_token_financial_transaction_id;

    /*
     * Use the token document's own financial transaction ID.
     */
    v_stage :=
        'post token financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_token_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_token_financial_transaction_id,

        p_transaction_type =>
            'gold_token_sell_sub_tx'::public."TransactionType",

        p_created_by =>
            v_seller.id,

        p_components =>
            v_preparation.token_components,

        p_mappings =>
            v_preparation.token_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference || '-01',

        p_deposit_type =>
            null
    );

    /*
     * Move the sold Gold quantity from the seller's customer
     * wallet to the treasury Gold wallet.
     *
     * No additional Gold fee is transferred.
     */
    v_stage :=
        'post token wallet entries';

    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_token_document_number,

        p_reference =>
            v_reference || '-01',

        p_receiver_id =>
            v_treasury.id,

        p_sender_id =>
            v_seller.id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_credit_amount =>
            v_preparation.token_quantity::numeric,

        p_debit_amount =>
            v_preparation.token_quantity::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_currency_code =>
            'gold',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_sold'::public."AuditActionType",

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
     * Mark blockchain transaction completed.
     *
     * blockchain_transaction does not have updated_at.
     */
    v_stage :=
        'complete blockchain transaction';

    update public.blockchain_transaction
    set
        document_number =
            v_token_document_number,

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
     * Mark the transaction state successful.
     */
    v_stage :=
        'complete transaction state';

    update public.transaction_state
    set
        user_id =
            v_seller.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()

    where id =
          p_transaction_state_id
      and created_by =
          p_seller_id
      and transaction_type =
          'gold_token_sell'::public."TransactionType"
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    /*
     * Return accounting and notification information.
     */
    v_stage :=
        'return gold sell result';

    return query
    select
        true,
        v_document_number,
        v_token_document_number,
        v_preparation.token_quantity,
        v_preparation.gross_amount,
        v_preparation.net_amount,
        v_preparation.fiat_fee,
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
                    'GOLD_SELL_FAILED at [%s]: %s',
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
                    'Check the Gold Sell stage reported in the error'
                );
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.complete_gold_sell(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
owner to postgres;

revoke all
on function public.complete_gold_sell(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
from public, anon, authenticated, service_role;

grant execute
on function public.complete_gold_sell(
    text,
    jsonb,
    text,
    text,
    text,
    text
)
to service_role;