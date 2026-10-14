-- Replace all overloads of these three helpers with one signature each.
-- DEFAULT NULL keeps existing fiat callers compatible.
-- GOLD callers must supply p_blockchain_code.
-- RESTRICT is intentional: dependent objects are never removed with CASCADE.
BEGIN;

CREATE TEMP TABLE wallet_helper_permissions ON COMMIT DROP AS
SELECT DISTINCT p.proname,
       pg_get_userbyid(p.proowner) AS owner_name,
       a.grantee,
       a.privilege_type,
       a.is_grantable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(
    coalesce(p.proacl, acldefault('f', p.proowner))
) a
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
      'post_wallet_entries',
      'update_wallet_balance_snapshot',
      'apply_wallet_snapshot_update'
  );

DO $migration$
DECLARE
    v_function record;
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY ARRAY[
        'post_wallet_entries',
        'update_wallet_balance_snapshot',
        'apply_wallet_snapshot_update'
    ] LOOP
        FOR v_function IN
            SELECT p.oid, n.nspname, p.proname,
                   pg_get_function_identity_arguments(p.oid) AS arguments
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = v_name
              AND p.prokind = 'f'
        LOOP
            EXECUTE format(
                'DROP FUNCTION %I.%I(%s) RESTRICT',
                v_function.nspname,
                v_function.proname,
                v_function.arguments
            );
        END LOOP;
    END LOOP;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.apply_wallet_snapshot_update(p_user_id text, p_country_code text, p_currency_code text, p_wallet_owner "WalletOwnerType", p_debit numeric, p_credit numeric, p_fiscal_year integer, p_period integer, p_blockchain_code text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
    v_opening numeric := 0;
    v_delta numeric;
    v_blockchain_code text;
begin
    v_blockchain_code := nullif(btrim(p_blockchain_code), '');

    if lower(btrim(p_currency_code)) = 'gold'
       and v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    if coalesce(p_debit, 0) = 0
       and coalesce(p_credit, 0) = 0
    then
        return;
    end if;

    v_delta :=
        coalesce(p_credit, 0) -
        coalesce(p_debit, 0);

    /*
     * First: exact current snapshot.
     */
    select s.closing_balance
    into v_opening
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and s.currency_code = p_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.blockchain_code is not distinct from v_blockchain_code
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period;

    /*
     * Second: earlier period in the same fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and s.currency_code = p_currency_code
          and s.wallet_owner = p_wallet_owner
      and s.blockchain_code is not distinct from v_blockchain_code
          and s.fiscal_year = p_fiscal_year
          and s.period < p_period
        order by s.period desc
        limit 1;
    end if;

    /*
     * Third: latest earlier fiscal year.
     */
    if not found then
        select s.closing_balance
        into v_opening
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and s.currency_code = p_currency_code
          and s.wallet_owner = p_wallet_owner
      and s.blockchain_code is not distinct from v_blockchain_code
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;
    end if;

    v_opening := coalesce(v_opening, 0);

    if v_blockchain_code is null then
    insert into public.wallet_balance_snapshot as current_snapshot (
        user_id,
        country_code,
        currency_code,
        wallet_owner,
        blockchain_code,
        fiscal_year,
        period,
        opening_balance,
        debit,
        credit,
        closing_balance,
        created_at,
        updated_at
    )
    values (
        p_user_id,
        p_country_code,
        p_currency_code,
        p_wallet_owner,
        v_blockchain_code,
        p_fiscal_year,
        p_period,
        v_opening,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        v_opening + v_delta,
        now(),
        now()
    )
    on conflict (
        user_id,
        currency_code,
        wallet_owner,
        fiscal_year,
        period
    )
    where blockchain_code is null
    do update
    set
        debit =
            current_snapshot.debit +
            excluded.debit,

        credit =
            current_snapshot.credit +
            excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.credit -
            excluded.debit,

        updated_at = now();
    else
    insert into public.wallet_balance_snapshot as current_snapshot (
        user_id,
        country_code,
        currency_code,
        wallet_owner,
        blockchain_code,
        fiscal_year,
        period,
        opening_balance,
        debit,
        credit,
        closing_balance,
        created_at,
        updated_at
    )
    values (
        p_user_id,
        p_country_code,
        p_currency_code,
        p_wallet_owner,
        v_blockchain_code,
        p_fiscal_year,
        p_period,
        v_opening,
        coalesce(p_debit, 0),
        coalesce(p_credit, 0),
        v_opening + v_delta,
        now(),
        now()
    )
    on conflict (
        user_id,
        currency_code,
        wallet_owner,
        blockchain_code,
        fiscal_year,
        period
    )
    where blockchain_code is not null
    do update
    set
        debit =
            current_snapshot.debit +
            excluded.debit,

        credit =
            current_snapshot.credit +
            excluded.credit,

        closing_balance =
            current_snapshot.closing_balance +
            excluded.credit -
            excluded.debit,

        updated_at = now();
    end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_wallet_balance_snapshot(
    p_transaction_type public."TransactionType",
    p_sender_id text,
    p_receiver_id text,
    p_treasury_id text,
    p_currency_code text,
    p_sender_wallet_owner public."WalletOwnerType",
    p_receiver_wallet_owner public."WalletOwnerType",
    p_sender_amount numeric,
    p_receiver_amount numeric,
    p_fiscal_year integer,
    p_period integer,
    p_country_code text,
    p_fee_amount numeric DEFAULT 0,
    p_blockchain_code text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
begin
    if p_sender_amount = 0
       and p_receiver_amount = 0
       and coalesce(p_fee_amount, 0) = 0 then
        return;
    end if;

    if p_transaction_type = 'treasury_funding'::public."TransactionType" then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id, p_country_code, p_currency_code,
            p_receiver_wallet_owner, 0, p_receiver_amount,
            p_fiscal_year, p_period, p_blockchain_code
        );
        return;
    end if;

    if p_transaction_type = 'treasury_funding_reversal'::public."TransactionType" then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id, p_country_code, p_currency_code,
            p_receiver_wallet_owner, p_receiver_amount, 0,
            p_fiscal_year, p_period, p_blockchain_code
        );
        return;
    end if;

    if p_sender_id is null then
        raise exception 'SENDER_REQUIRED_FOR_WALLET_SNAPSHOT';
    end if;

    if p_sender_amount > 0 then
        perform public.apply_wallet_snapshot_update(
            p_sender_id, p_country_code, p_currency_code,
            p_sender_wallet_owner, p_sender_amount, 0,
            p_fiscal_year, p_period, p_blockchain_code
        );
    end if;

    if p_receiver_amount > 0 then
        if p_transaction_type <> 'government_tax_clearing'::public."TransactionType" then
            perform public.apply_wallet_snapshot_update(
                p_receiver_id, p_country_code, p_currency_code,
                p_receiver_wallet_owner, 0, p_receiver_amount,
                p_fiscal_year, p_period, p_blockchain_code
            );
        end if;
    end if;

    if coalesce(p_fee_amount, 0) > 0 and p_treasury_id is not null then
        perform public.apply_wallet_snapshot_update(
            p_treasury_id, p_country_code, p_currency_code,
            'treasury'::public."WalletOwnerType", 0, p_fee_amount,
            p_fiscal_year, p_period, p_blockchain_code
        );
    end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_wallet_entries(p_fiscal_year integer, p_period integer, p_document_number text, p_reference text, p_receiver_id text, p_sender_id text, p_transaction_type "TransactionType", p_credit_amount numeric, p_debit_amount numeric, p_sender_wallet_owner "WalletOwnerType", p_receiver_wallet_owner "WalletOwnerType", p_currency_code text, p_country_code text, p_audit_action_type "AuditActionType", p_treasury_id text DEFAULT NULL::text, p_fee_amount numeric DEFAULT 0, p_ip_address text DEFAULT NULL::text, p_receiver_notification notification_message DEFAULT NULL::notification_message, p_sender_notification notification_message DEFAULT NULL::notification_message, p_blockchain_code text DEFAULT NULL::text)
 RETURNS TABLE(wallet_entry_count integer, receiver_notification_id text)
 LANGUAGE plpgsql
AS $function$
declare
    v_blockchain_code text;
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
    v_blockchain_code := nullif(btrim(p_blockchain_code), '');

    if lower(btrim(p_currency_code)) = 'gold'
       and v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    /*
     * Lock and validate sender wallet.
     */
    select w.*
    into v_sender_wallet
    from public.wallet w
    where w.country_code = p_country_code
      and w.user_id = p_sender_id
      and w.currency_code = p_currency_code
      and w.blockchain_code is not distinct from v_blockchain_code
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
    if v_blockchain_code is null then
    insert into public.wallet (
        user_id,
        currency_code,
        country_code,
        owner_type,
        blockchain_code,
        balance,
        is_active
    )
    values (
        p_receiver_id,
        p_currency_code,
        p_country_code,
        p_receiver_wallet_owner,
        v_blockchain_code,
        0,
        true
    )
    on conflict (
        country_code,
        user_id,
        currency_code,
        owner_type
    )
    where blockchain_code is null
    do nothing;
    else
    insert into public.wallet (
        user_id,
        currency_code,
        country_code,
        owner_type,
        blockchain_code,
        balance,
        is_active
    )
    values (
        p_receiver_id,
        p_currency_code,
        p_country_code,
        p_receiver_wallet_owner,
        v_blockchain_code,
        0,
        true
    )
    on conflict (
        country_code,
        user_id,
        currency_code,
        owner_type,
        blockchain_code
    )
    where blockchain_code is not null
    do nothing;
    end if;

    /*
     * Lock and validate receiver wallet.
     */
    select w.*
    into v_receiver_wallet
    from public.wallet w
    where w.country_code = p_country_code
      and w.user_id = p_receiver_id
      and w.currency_code = p_currency_code
      and w.blockchain_code is not distinct from v_blockchain_code
      and w.owner_type = p_receiver_wallet_owner
    limit 1
    for update;

    if not found then
        raise exception 'RECEIVER_WALLET_NOT_FOUND';
    end if;

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
      and w.blockchain_code is not distinct from v_blockchain_code
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
            blockchain_code,
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
            v_blockchain_code,
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
            blockchain_code,
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
            v_blockchain_code,
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
            blockchain_code,
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
            v_blockchain_code,
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
        coalesce(p_fee_amount, 0),
        v_blockchain_code
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
            'currency', p_currency_code,
            'blockchain_code', v_blockchain_code
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
            'currency', p_currency_code,
            'blockchain_code', v_blockchain_code
        ),
        p_ip_address,
        p_document_number
    );

    return query
    select
        v_entry_count,
        v_receiver_notification_id;
end;
$function$;

DO $permissions$
DECLARE
    v_function record;
    v_permission record;
    v_role text;
BEGIN
    FOR v_function IN
        SELECT p.proname, p.oid::regprocedure AS signature
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.proname IN (
              'post_wallet_entries',
              'update_wallet_balance_snapshot',
              'apply_wallet_snapshot_update'
          )
    LOOP
        -- Remove creation-time grants before restoring the former grants.
        FOR v_permission IN
            SELECT DISTINCT a.grantee
            FROM pg_proc p
            CROSS JOIN LATERAL aclexplode(
                coalesce(p.proacl, acldefault('f', p.proowner))
            ) a
            WHERE p.oid = v_function.signature::oid
              AND a.grantee <> p.proowner
        LOOP
            v_role := CASE WHEN v_permission.grantee = 0
                THEN 'PUBLIC'
                ELSE quote_ident(pg_get_userbyid(v_permission.grantee)) END;
            EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',
                v_function.signature, v_role);
        END LOOP;

        FOR v_permission IN
            SELECT * FROM wallet_helper_permissions
            WHERE proname = v_function.proname
        LOOP
            v_role := CASE WHEN v_permission.grantee = 0
                THEN 'PUBLIC'
                ELSE quote_ident(pg_get_userbyid(v_permission.grantee)) END;
            EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',
                v_permission.privilege_type,
                v_function.signature,
                v_role,
                CASE WHEN v_permission.is_grantable
                    THEN ' WITH GRANT OPTION' ELSE '' END);
        END LOOP;

        SELECT owner_name INTO v_role
        FROM wallet_helper_permissions
        WHERE proname = v_function.proname
        LIMIT 1;
        IF v_role IS NOT NULL THEN
            EXECUTE format('ALTER FUNCTION %s OWNER TO %I',
                v_function.signature, v_role);
        END IF;
    END LOOP;
END;
$permissions$;

COMMIT;

-- Each function must have exactly one signature.
SELECT p.proname AS function_name,
       pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
      'apply_wallet_snapshot_update',
      'update_wallet_balance_snapshot',
      'post_wallet_entries'
  )
ORDER BY p.proname;
