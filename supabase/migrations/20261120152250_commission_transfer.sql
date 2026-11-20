-- Before enabling the Edge Function, configure v9, a document prefix,
-- commission -> customer wallet ownership with an audit action, and one
-- active principal GL mapping for commission_transfer. The GL mapping
-- reclassifies commission-wallet funds into the personal-wallet liability.
-- Confirm the actual accounts against the chart of accounts.
begin;

create or replace function public.fetch_my_commission_transfer_context()
returns table(sender_id text, country_code text, wallet_address text, version_time integer)
language sql stable security definer
set search_path = ''
as $function$
    select u.id, u.country_code, u.wallet_address, public.get_transaction_v('v9')
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) in ('agent', 'vendor')
      and nullif(btrim(u.country_code), '') is not null
      and nullif(btrim(u.wallet_address), '') is not null;
$function$;

revoke all on function public.fetch_my_commission_transfer_context()
from public, anon, authenticated;
grant execute on function public.fetch_my_commission_transfer_context() to authenticated;

create or replace function public.commission_transfer(
    p_sender_id text,
    p_verified_wallet_address text,
    p_transaction jsonb,
    p_ip_address text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $function$
declare
    v_type constant public."TransactionType" := 'commission_transfer';
    v_user public.users%rowtype;
    v_config public.transaction_type_wallet_owner%rowtype;
    v_mapping public.transaction_gl_mapping%rowtype;
    v_reference text := p_transaction ->> 'r';
    v_currency text := lower(btrim(p_transaction ->> 'c'));
    v_minor text := p_transaction ->> 'a';
    v_amount numeric;
    v_amount_usd numeric;
    v_rate numeric;
    v_fiscal record;
    v_prefix text;
    v_document text;
    v_state_id text;
    v_financial_id bigint;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;

    select u.* into v_user
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = p_sender_id
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) in ('agent', 'vendor')
      and nullif(btrim(u.country_code), '') is not null
      and nullif(btrim(u.wallet_address), '') is not null
      and u.wallet_address = p_verified_wallet_address
    for share of u, r;

    if not found then
        raise exception using errcode = '42501', message = 'COMMISSION_TRANSFER_NOT_AUTHORIZED';
    end if;

    if jsonb_typeof(p_transaction) is distinct from 'object'
       or p_transaction ->> 'v' is distinct from 'v9'
       or p_transaction ->> 's' is distinct from v_user.id
       or nullif(btrim(v_reference), '') is null
       or v_reference <> btrim(v_reference) then
        raise exception using errcode = '22023', message = 'INVALID_COMMISSION_TRANSFER';
    end if;

    if v_minor is null or v_minor !~ '^[0-9]{1,18}$' or v_minor::numeric <= 0 then
        raise exception using errcode = '22023', message = 'INVALID_COMMISSION_TRANSFER_AMOUNT';
    end if;

    if coalesce(p_transaction ->> 'f', '') !~ '^0+(\.0+)?$' then
        raise exception using errcode = '22023', message = 'COMMISSION_TRANSFER_FEE_NOT_SUPPORTED';
    end if;

    v_amount := v_minor::numeric / 100;

    if not exists (
        select 1
        from public.country_currencies cc
        join public.supported_currency sc on sc.currency_code = cc.currency_code
        where cc.country_code = v_user.country_code
          and cc.currency_code = v_currency
          and cc.is_active and sc.is_active
          and sc.currency_category = 'fiat'::public."CurrencyCategory"
    ) then
        raise exception using errcode = '22023', message = 'COMMISSION_TRANSFER_CURRENCY_NOT_SUPPORTED';
    end if;

    -- Serialize requests for the same reference, including retries after timeouts.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('ngoda:commission-transfer:' || v_reference, 0)
    );
    if exists (select 1 from public.transaction_state s where s.reference = v_reference) then
        raise exception using errcode = '23505', message = 'TRANSACTION_REPLAY';
    end if;

    select config.* into strict v_config
    from public.fetch_transaction_type_wallet_owner(v_type) config;

    if v_config.sender_wallet_owner is distinct from 'commission'::public."WalletOwnerType"
       or v_config.receiver_wallet_owner is distinct from 'customer'::public."WalletOwnerType"
       or v_config.audit_action_type is null then
        raise exception 'INVALID_COMMISSION_TRANSFER_WALLET_CONFIGURATION';
    end if;

    select mapping.* into strict v_mapping
    from public.fetch_gl_mappings(v_type) mapping
    where mapping.component_type = 'principal';

    v_prefix := public.fetch_transaction_doc_num_prefix(v_type);
    if nullif(btrim(v_prefix), '') is null then
        raise exception 'COMMISSION_TRANSFER_DOCUMENT_PREFIX_NOT_CONFIGURED';
    end if;

    if v_currency = 'usd' then
        v_rate := 1;
    else
        select cr.rate_to_usd into strict v_rate
        from public.current_rates cr
        where lower(btrim(cr.code)) = v_currency;

        if v_rate is null or v_rate <= 0 or v_rate::text in ('NaN', 'Infinity') then
            raise exception 'INVALID_COMMISSION_TRANSFER_EXCHANGE_RATE';
        end if;
    end if;
    v_amount_usd := round(v_amount / v_rate, 6);

    select fiscal.* into strict v_fiscal
    from public.fetch_fiscal_period(
        v_user.country_code, statement_timestamp() at time zone 'UTC'
    ) fiscal;

    v_state_id := gen_random_uuid()::text;
    insert into public.transaction_state (
        id, reference, status, transaction_type, country_code,
        transaction_data, created_by, user_id, updated_at
    ) values (
        v_state_id, v_reference, 'processing', v_type, v_user.country_code,
        p_transaction, v_user.id, v_user.id, now()
    );

    v_document := public.generate_document_number(
        v_prefix, v_fiscal.fiscal_year, v_fiscal.period, v_user.country_code
    );

    insert into public.financial_transaction (
        document_number, fiscal_year, period, transaction_type, description,
        created_by, gross_amount, currency_code, reference, country_code
    ) values (
        v_document, v_fiscal.fiscal_year, v_fiscal.period, v_type,
        'Commission Earned', v_user.id, v_amount, v_currency, v_reference,
        v_user.country_code
    ) returning id into v_financial_id;

    perform public.post_financial_entries(
        p_document_number => v_document,
        p_country_code => v_user.country_code,
        p_transaction_id => v_financial_id,
        p_transaction_type => v_type,
        p_created_by => v_user.id,
        p_components => array[row(
            'principal'::public."ComponentType", v_amount, v_amount
        )::public.posting_component],
        p_mappings => array[v_mapping],
        p_currency_code => v_currency,
        p_fiscal_year => v_fiscal.fiscal_year,
        p_period => v_fiscal.period,
        p_reference => v_reference
    );

    perform public.post_wallet_entries(
        p_fiscal_year => v_fiscal.fiscal_year,
        p_period => v_fiscal.period,
        p_document_number => v_document,
        p_reference => v_reference,
        p_receiver_id => v_user.id,
        p_sender_id => v_user.id,
        p_transaction_type => v_type,
        p_credit_amount => v_amount,
        p_debit_amount => v_amount,
        p_sender_wallet_owner => v_config.sender_wallet_owner,
        p_receiver_wallet_owner => v_config.receiver_wallet_owner,
        p_currency_code => v_currency,
        p_country_code => v_user.country_code,
        p_audit_action_type => v_config.audit_action_type,
        p_ip_address => p_ip_address
    );

    update public.transaction_state
    set status = 'success', updated_at = now()
    where id = v_state_id;

    return jsonb_build_object(
        'success', true, 'reference', v_reference, 'currency', v_currency,
        'amount', trim_scale(v_amount)::text, 'amount_usd', v_amount_usd::text,
        'fee', '0', 'financial_transaction_id', v_financial_id::text
    );
end;
$function$;

revoke all on function public.commission_transfer(text, text, jsonb, text)
from public, anon, authenticated;
grant execute on function public.commission_transfer(text, text, jsonb, text)
to service_role;

commit;
