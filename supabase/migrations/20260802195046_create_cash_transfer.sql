/* =========================================================
 * CASH TRANSFER
 * ========================================================= */

create or replace function public.cash_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
    success boolean,
    amount text,
    fee text,
    currency text,
    receiver_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
volatile
as $$
declare
    v_decimals numeric := 100;

    v_amount numeric;
    v_principal numeric;
    v_currency text;
    v_reference text;
    v_receiver_identifier text;

    v_fiscal_year integer;
    v_period integer;

    v_receiver public.users%rowtype;
    v_sender public.users%rowtype;
    v_treasury public.users%rowtype;

    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];
    v_component public.posting_component;

    v_component_totals public.component_totals;
    v_principal_amount numeric;
    v_others_amount numeric;
    v_fee numeric := 0;

    v_sender_notification public.notification_message;
    v_receiver_notification public.notification_message;

    v_device_tokens text[] := array[]::text[];

    v_document_prefix text;
    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;
begin
    /*
     * This stored function only processes cash transfers.
     */
    if p_transaction_type <>
       'cash_transfer'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_TRANSFER_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    /*
     * The Edge Function validates the complete transaction structure
     * before calling this function.
     */
    v_amount :=
        (p_transaction ->> 'a')::numeric /
        v_decimals;

    v_principal := v_amount;
    v_currency := p_transaction ->> 'c';
    v_reference := p_transaction ->> 'r';
    v_receiver_identifier := p_transaction ->> 's';

    /*
     * Fetch active GL mappings.
     */
    select array_agg(m)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as m;

    /*
     * Build the posting components.
     */
    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_principal,
            v_mappings,
            p_country_code,
            v_currency,
            false
        );

    /*
     * Fetch the current fiscal period.
     */
    select
        fp.fiscal_year,
        fp.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        p_country_code
    ) as fp;

    /*
     * Receiver is identified using the email address or phone number
     * contained in transaction.s.
     */
    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    /*
     * Sender is identified using the authenticated user ID supplied
     * by the Edge Function.
     */
    v_sender :=
        public.fetch_user_by_id(
            p_sender_id
        );

    /*
     * Fetch the treasury belonging to this country.
     */
    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception 'RECEIVER_NOT_ACTIVE';
    end if;

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception 'SENDER_NOT_ACTIVE';
    end if;

    /*
     * Prevent transferring to the authenticated sender.
     * Comparing IDs is safer than comparing nullable email addresses.
     */
    if v_sender.id = v_receiver.id then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       v_receiver.country_code
    then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       p_country_code
    then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Extract wallet and posting amounts.
     */
    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );

    v_principal_amount :=
        v_component_totals.principal_amount;

    v_others_amount :=
        v_component_totals.others_amount;

    /*
     * Find the transfer-fee component.
     */
    foreach v_component in array v_components
    loop
        if v_component.component_type =
           'transfer_fee'::public."ComponentType"
        then
            v_fee := v_component.credit_amount;
            exit;
        end if;
    end loop;

    if v_fee <= 0 then
        raise exception 'INVALID_FEE_AMOUNT';
    end if;

    /*
     * Build sender notification.
     */
    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'sender'::public."NotificationAudience",
            v_principal_amount,
            upper(v_currency),
            v_reference || '-01',
            0,
            coalesce(
                v_sender.email,
                v_sender.id
            ),
            v_receiver.email
        );

    /*
     * Build receiver notification.
     */
    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-02',
            0,
            coalesce(
                v_sender.email,
                v_sender.id
            ),
            v_receiver.email
        );

    /*
     * Fetch tokens for use by the Edge Function after this
     * database transaction succeeds.
     */
    v_device_tokens :=
        public.fetch_device_tokens(
            p_country_code,
            v_receiver.id
        );

    /*
     * Fetch the configured document prefix.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    /*
     * Generate the next document number atomically.
     */
    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );

    /*
     * Create the financial transaction header.
     */
    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reference,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        'User transfer from ' ||
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ) ||
            ' to ' ||
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            ),
        p_sender_id,
        v_principal_amount,
        v_currency,
        v_document_number,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post the balanced GL entries and update GL snapshots.
     */
    perform *
    from public.post_financial_entries(
        v_document_number,
        p_country_code,
        v_financial_transaction_id,
        p_transaction_type,
        p_sender_id,
        v_components,
        v_mappings,
        v_currency,
        v_fiscal_year,
        v_period
    );

    /*
     * Post wallet entries, update wallet balances and snapshots,
     * create notifications and write audit records.
     */
    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year => v_fiscal_year,
        p_period => v_period,
        p_document_number => v_document_number,
        p_receiver_id => v_receiver.id,
        p_sender_id => p_sender_id,
        p_transaction_type => p_transaction_type,
        p_credit_amount => v_amount,
        p_debit_amount => v_principal_amount,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_currency_code => v_currency,
        p_country_code => p_country_code,
        p_audit_action_type =>
            'cash_transferred'::public."AuditActionType",
        p_treasury_id => v_treasury.id,
        p_fee_amount => v_fee,
        p_ip_address => p_ip_address,
        p_receiver_notification =>
            v_receiver_notification,
        p_sender_notification =>
            v_sender_notification
    ) as result;

    /*
     * Mark the transaction state as successful.
     */
    update public.transaction_state
    set
        status =
            'success'::public."TransactionStatus",
        updated_at = now()
    where id = p_transaction_state_id;

    if not found then
        raise exception 'TRANSACTION_STATE_NOT_FOUND';
    end if;

    /*
     * Return the financial result and the information required
     * for the Edge Function push notification.
     */
    return query
    select
        true,
        v_amount::text,
        v_others_amount::text,
        v_currency,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload ->> 'reference';
end;
$$;