CREATE OR REPLACE FUNCTION public.post_wallet_entries(p_fiscal_year integer, p_period integer, p_document_number text, p_reference text, p_receiver_id text, p_sender_id text, p_transaction_type "TransactionType", p_credit_amount numeric, p_debit_amount numeric, p_sender_wallet_owner "WalletOwnerType", p_receiver_wallet_owner "WalletOwnerType", p_currency_code text, p_country_code text, p_audit_action_type "AuditActionType", p_treasury_id text DEFAULT NULL::text, p_fee_amount numeric DEFAULT 0, p_ip_address text DEFAULT NULL::text, p_receiver_notification notification_message DEFAULT NULL::notification_message, p_sender_notification notification_message DEFAULT NULL::notification_message)
 RETURNS TABLE(wallet_entry_count integer, receiver_notification_id text)
 LANGUAGE plpgsql
AS $function$
declare
    v_sender_wallet public.wallet%rowtype;
    v_receiver_wallet public.wallet%rowtype;
    v_treasury_wallet public.wallet%rowtype;

    v_sender_balance_before numeric;
    v_sender_balance_after numeric;

    v_receiver_balance_before numeric;
    v_receiver_balance_after numeric;

    v_entry_count integer := 0;
    v_receiver_notification_id text := null;
begin
    /*
     * Lock and validate sender wallet.
     */
    select w.*
    into v_sender_wallet
    from public.wallet w
    where w.country_code = p_country_code
      and w.user_id = p_sender_id
      and w.currency_code = p_currency_code
      and w.owner_type = p_sender_wallet_owner
    limit 1
    for update;

    if not found then
        raise exception 'SENDER_WALLET_NOT_FOUND';
    end if;

    if not v_sender_wallet.is_active then
        raise exception 'SENDER_WALLET_FROZEN';
    end if;

    v_sender_balance_before :=
        v_sender_wallet.balance;

    /*
     * Create receiver wallet when it does not exist.
     */
    insert into public.wallet (
        user_id,
        currency_code,
        country_code,
        owner_type,
        balance,
        is_active
    )
    values (
        p_receiver_id,
        p_currency_code,
        p_country_code,
        p_receiver_wallet_owner,
        0,
        true
    )
    on conflict (
        country_code,
        user_id,
        currency_code,
        owner_type
    )
    do nothing;

    /*
     * Lock and validate receiver wallet.
     */
    select w.*
    into v_receiver_wallet
    from public.wallet w
    where w.country_code = p_country_code
      and w.user_id = p_receiver_id
      and w.currency_code = p_currency_code
      and w.owner_type = p_receiver_wallet_owner
    limit 1
    for update;

    if not v_receiver_wallet.is_active then
        raise exception 'RECEIVER_WALLET_FROZEN';
    end if;

    v_receiver_balance_before :=
        v_receiver_wallet.balance;

    /*
     * Validate and lock treasury wallet when fees exist.
     */
    if coalesce(p_fee_amount, 0) > 0 then
        if p_treasury_id is null then
            raise exception 'TREASURY_REQUIRED_FOR_FEE';
        end if;

        select w.*
        into v_treasury_wallet
        from public.wallet w
        where w.country_code = p_country_code
          and w.user_id = p_treasury_id
          and w.currency_code = p_currency_code
          and w.owner_type =
              'treasury'::public."WalletOwnerType"
        limit 1
        for update;

        if not found then
            raise exception 'TREASURY_WALLET_NOT_FOUND';
        end if;
    end if;

    /*
     * Debit sender wallet.
     */
    if p_debit_amount > 0 then
        update public.wallet
        set balance = balance - p_debit_amount
        where id = v_sender_wallet.id
          and is_active = true
          and balance >= p_debit_amount
        returning balance
        into v_sender_balance_after;

        if not found then
            raise exception 'INSUFFICIENT_BALANCE';
        end if;

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
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_sender_wallet.id,
            p_currency_code,
            p_country_code,
            p_debit_amount,
            0,
            p_sender_id
        );

        v_entry_count := v_entry_count + 1;
    else
        v_sender_balance_after :=
            v_sender_balance_before;
    end if;

    /*
     * Credit receiver wallet.
     */
    if p_credit_amount > 0 then
        update public.wallet
        set balance = balance + p_credit_amount
        where id = v_receiver_wallet.id
        returning balance
        into v_receiver_balance_after;

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
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_receiver_wallet.id,
            p_currency_code,
            p_country_code,
            0,
            p_credit_amount,
            p_receiver_id
        );

        v_entry_count := v_entry_count + 1;
    else
        v_receiver_balance_after :=
            v_receiver_balance_before;
    end if;

    /*
     * Credit treasury fee wallet.
     */
    if coalesce(p_fee_amount, 0) > 0 then
        update public.wallet
        set balance = balance + p_fee_amount
        where id = v_treasury_wallet.id;

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
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_treasury_wallet.id,
            p_currency_code,
            p_country_code,
            0,
            p_fee_amount,
            p_treasury_id
        );

        v_entry_count := v_entry_count + 1;
    end if;

    if v_entry_count = 0 then
        raise exception 'NO_WALLET_ENTRIES_TO_POST';
    end if;

    /*
     * Update wallet balance snapshots.
     */
    perform public.update_wallet_balance_snapshot(
        p_transaction_type,
        p_sender_id,
        p_receiver_id,
        p_treasury_id,
        p_currency_code,
        v_sender_wallet.owner_type,
        v_receiver_wallet.owner_type,
        p_debit_amount,
        p_credit_amount,
        p_fiscal_year,
        p_period,
        p_country_code,
        coalesce(p_fee_amount, 0)
    );

    /*
     * Receiver notification.
     */
    if p_receiver_notification is distinct from null then
        insert into public.notifications (
            country_code,
            reference,
            user_id,
            payload,
            title,
            body,
            notification_type,
            transaction_type
        )
        values (
            p_country_code,
            p_receiver_notification.payload ->> 'reference',
            p_receiver_id,
            p_receiver_notification.payload,
            p_receiver_notification.title,
            p_receiver_notification.body,
            p_receiver_notification.notification_type,
            p_transaction_type
        )
        returning id::text
        into v_receiver_notification_id;
    end if;

    /*
     * Sender notification.
     */
    if p_sender_notification is distinct from null then
        insert into public.notifications (
            country_code,
            reference,
            user_id,
            payload,
            title,
            body,
            notification_type,
            transaction_type
        )
        values (
            p_country_code,
            p_sender_notification.payload ->> 'reference',
            p_sender_id,
            p_sender_notification.payload,
            p_sender_notification.title,
            p_sender_notification.body,
            p_sender_notification.notification_type,
            p_transaction_type
        );
    end if;

    /*
     * Audit sender and receiver balance changes.
     */
    insert into public.audit_log (
        fiscal_year,
        period,
        user_id,
        country_code,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata,
        ip_address,
        document_number
    )
    values
    (
        p_fiscal_year,
        p_period,
        p_sender_id,
        p_country_code,
        p_audit_action_type,
        'wallet',
        v_sender_wallet.id,
        jsonb_build_object(
            'balance_before',
            v_sender_balance_before::text
        ),
        jsonb_build_object(
            'balance_after',
            v_sender_balance_after::text
        ),
        jsonb_build_object(
            'receiver_id', p_receiver_id,
            'amount', p_credit_amount::text,
            'fee', coalesce(p_fee_amount, 0)::text,
            'currency', p_currency_code
        ),
        p_ip_address,
        p_document_number
    ),
    (
        p_fiscal_year,
        p_period,
        p_receiver_id,
        p_country_code,
        p_audit_action_type,
        'wallet',
        v_receiver_wallet.id,
        jsonb_build_object(
            'balance_before',
            v_receiver_balance_before::text
        ),
        jsonb_build_object(
            'balance_after',
            v_receiver_balance_after::text
        ),
        jsonb_build_object(
            'sender_id', p_sender_id,
            'amount', p_credit_amount::text,
            'fee', coalesce(p_fee_amount, 0)::text,
            'currency', p_currency_code
        ),
        p_ip_address,
        p_document_number
    );

    return query
    select
        v_entry_count,
        v_receiver_notification_id;
end;
$function$
