-- Configure v10, the disbursement_clerk user_role row, a document prefix,
-- commission -> treasury wallet ownership with an audit action, and an
-- active GL mappings for principal and any configured withdrawal fee or government tax.
-- The existing pricing engine supplies the fee and tax for the country and currency.
begin;

create or replace function public.fetch_my_commission_withdrawal_context(p_user_id text)
returns table(clerk_id text, clerk_wallet_address text, user_wallet_address text, version_time integer)
language sql stable security definer
set search_path = ''
as $function$
    select clerk.id, clerk.wallet_address, holder.wallet_address, public.get_transaction_v('v10')
    from public.users clerk
    join public.user_role clerk_role on clerk_role.id = clerk.role_id
    join public.users holder on holder.id = p_user_id
        and holder.country_code = clerk.country_code and holder.id <> clerk.id
    join public.user_role holder_role on holder_role.id = holder.role_id
    where clerk.id = auth.uid()::text
      and clerk.status = 'active'::public."UserStatus"
      and holder.status = 'active'::public."UserStatus"
      and lower(clerk_role.name::text) = 'disbursement_clerk'
      and lower(holder_role.name::text) in ('agent', 'vendor', 'merchant')
      and nullif(btrim(clerk.country_code), '') is not null
      and nullif(btrim(clerk.wallet_address), '') is not null
      and nullif(btrim(holder.wallet_address), '') is not null;
$function$;

revoke all on function public.fetch_my_commission_withdrawal_context(text)
from public, anon, authenticated;
grant execute on function public.fetch_my_commission_withdrawal_context(text) to authenticated;

create or replace function public.commission_withdrawal(
    p_clerk_id text,
    p_verified_clerk_address text,
    p_verified_user_address text,
    p_transaction jsonb,
    p_approval jsonb,
    p_ip_address text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $function$
declare
    v_type constant public."TransactionType" := 'commission_withdrawal';
    v_clerk public.users%rowtype;
    v_user public.users%rowtype;
    v_treasury public.users%rowtype;
    v_config public.transaction_type_wallet_owner%rowtype;
    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];
    v_pricing public.pricing_result;
    v_fee numeric;
    v_tax numeric;
    v_tax_rate numeric;
    v_debit numeric;
    v_reference text := p_transaction ->> 'r';
    v_currency text := lower(btrim(p_transaction ->> 'c'));
    v_minor text := p_transaction ->> 'a';
    v_amount numeric;
    v_fiscal record;
    v_prefix text;
    v_document text;
    v_state_id text;
    v_financial_id bigint;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;

    select u.* into v_clerk
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = p_clerk_id
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) = 'disbursement_clerk'
      and nullif(btrim(u.country_code), '') is not null
      and nullif(btrim(u.wallet_address), '') is not null
      and u.wallet_address = p_verified_clerk_address
    for share of u, r;

    if not found then
        raise exception using errcode = '42501', message = 'COMMISSION_WITHDRAWAL_NOT_AUTHORIZED';
    end if;

    if jsonb_typeof(p_transaction) is distinct from 'object'
       or jsonb_typeof(p_approval) is distinct from 'object'
       or p_transaction ->> 'v' is distinct from 'v10'
       or p_approval ->> 'v' is distinct from 'v10'
       or p_approval ->> 'b' is distinct from v_clerk.id
       or p_approval ->> 'r' is distinct from v_reference
       or p_approval ->> 'a' is distinct from v_minor
       or p_approval ->> 'c' is distinct from p_transaction ->> 'c'
       or nullif(btrim(v_reference), '') is null
       or v_reference <> btrim(v_reference) then
        raise exception using errcode = '22023', message = 'INVALID_COMMISSION_WITHDRAWAL';
    end if;

    select u.* into v_user
    from public.users u
    join public.user_role r on r.id = u.role_id
    where u.id = p_transaction ->> 's'
      and u.id <> v_clerk.id
      and u.country_code = v_clerk.country_code
      and u.status = 'active'::public."UserStatus"
      and lower(r.name::text) in ('agent', 'vendor', 'merchant')
      and nullif(btrim(u.wallet_address), '') is not null
      and u.wallet_address = p_verified_user_address
    for share of u, r;

    if not found then
        raise exception using errcode = '42501', message = 'COMMISSION_WALLET_OWNER_NOT_AUTHORIZED';
    end if;

    if v_minor is null or v_minor !~ '^[0-9]{1,18}$' or v_minor::numeric <= 0 then
        raise exception using errcode = '22023', message = 'INVALID_COMMISSION_WITHDRAWAL_AMOUNT';
    end if;

    if coalesce(p_transaction ->> 'f', '') !~ '^[0-9]{1,18}$'
       or coalesce(p_transaction ->> 'g', '') !~ '^[0-9]{1,18}$' then
        raise exception using errcode = '22023', message = 'INVALID_COMMISSION_WITHDRAWAL_CHARGES';
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
        raise exception using errcode = '22023', message = 'COMMISSION_WITHDRAWAL_CURRENCY_NOT_SUPPORTED';
    end if;

    -- Serialize requests for the same reference, including retries after timeouts.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('ngoda:commission-withdrawal:' || v_reference, 0)
    );
    if exists (select 1 from public.transaction_state s where s.reference = v_reference) then
        raise exception using errcode = '23505', message = 'TRANSACTION_REPLAY';
    end if;

    select config.* into strict v_config
    from public.fetch_transaction_type_wallet_owner(v_type) config;

    if v_config.sender_wallet_owner is distinct from 'commission'::public."WalletOwnerType"
       or v_config.receiver_wallet_owner is distinct from 'treasury'::public."WalletOwnerType"
       or v_config.audit_action_type is null then
        raise exception 'INVALID_COMMISSION_WITHDRAWAL_WALLET_CONFIGURATION';
    end if;

    v_pricing := public.calculate_transaction_pricing(
        v_type, v_amount, v_user.country_code, v_currency
    );
    v_fee := public.round_down(v_pricing.fee);
    v_tax := public.round_down(v_pricing.tax);

    if v_fee is null or v_tax is null
       or v_fee < 0 or v_tax < 0
       or v_fee::text in ('NaN', 'Infinity') or v_tax::text in ('NaN', 'Infinity') then
        raise exception 'INVALID_COMMISSION_WITHDRAWAL_PRICING';
    end if;

    if (p_transaction ->> 'f')::numeric <> v_fee * 100
       or (p_transaction ->> 'g')::numeric <> v_tax * 100 then
        raise exception using errcode = '22023', message = 'COMMISSION_WITHDRAWAL_QUOTE_MISMATCH';
    end if;

    v_debit := v_amount + v_fee + v_tax;

    select array_agg(mapping) into v_mappings
    from public.fetch_gl_mappings(v_type) mapping;

    v_components := public.build_posting_components(
        v_type, v_amount, v_mappings, v_user.country_code, v_currency, false
    );

    -- Check gross-mode posting and that each calculated charge has its GL mapping.
    if not exists (
        select 1 from unnest(v_components) component
        where component.component_type = 'principal'
          and component.debit_amount = v_debit and component.credit_amount = v_amount
    ) or exists (
        select 1 from unnest(v_components) component
        where component.component_type not in ('principal', 'withdrawal_fee', 'government_tax')
           or (component.component_type <> 'principal' and component.debit_amount <> 0)
    ) or (
        select coalesce(sum(component.credit_amount), 0) from unnest(v_components) component
        where component.component_type = 'withdrawal_fee'
    ) <> v_fee or (
        select coalesce(sum(component.credit_amount), 0) from unnest(v_components) component
        where component.component_type = 'government_tax'
    ) <> v_tax then
        raise exception 'INVALID_COMMISSION_WITHDRAWAL_POSTING_COMPONENTS';
    end if;

    v_prefix := public.fetch_transaction_doc_num_prefix(v_type);
    if nullif(btrim(v_prefix), '') is null then
        raise exception 'COMMISSION_WITHDRAWAL_DOCUMENT_PREFIX_NOT_CONFIGURED';
    end if;

    select t.* into v_treasury
    from public.fetch_country_treasury(v_user.country_code) t;

    if v_treasury.id is null or v_treasury.id in (v_user.id, v_clerk.id)
       or v_treasury.country_code is distinct from v_user.country_code
       or v_treasury.status is distinct from 'active'::public."UserStatus" then
        raise exception 'COMMISSION_WITHDRAWAL_TREASURY_NOT_CONFIGURED';
    end if;

    select fiscal.* into strict v_fiscal
    from public.fetch_fiscal_period(
        v_user.country_code, statement_timestamp() at time zone 'UTC'
    ) fiscal;

    v_state_id := gen_random_uuid()::text;
    insert into public.transaction_state (
        id, reference, status, transaction_type, country_code,
        transaction_data, sender_approval, created_by, user_id, updated_at
    ) values (
        v_state_id, v_reference, 'processing', v_type, v_user.country_code,
        p_transaction, p_approval, v_clerk.id, v_user.id, now()
    );

    v_document := public.generate_document_number(
        v_prefix, v_fiscal.fiscal_year, v_fiscal.period, v_user.country_code
    );

    insert into public.financial_transaction (
        document_number, fiscal_year, period, transaction_type, description,
        created_by, gross_amount, currency_code, reference, country_code
    ) values (
        v_document, v_fiscal.fiscal_year, v_fiscal.period, v_type,
        'Commission withdrawal', v_clerk.id, v_amount, v_currency, v_reference,
        v_user.country_code
    ) returning id into v_financial_id;

    perform public.post_financial_entries(
        p_document_number => v_document,
        p_country_code => v_user.country_code,
        p_transaction_id => v_financial_id,
        p_transaction_type => v_type,
        p_created_by => v_clerk.id,
        p_components => v_components,
        p_mappings => v_mappings,
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
        p_receiver_id => v_treasury.id,
        p_sender_id => v_user.id,
        p_transaction_type => v_type,
        -- Treasury receives both the principal and the configured charges.
        p_credit_amount => v_debit,
        p_debit_amount => v_debit,
        p_sender_wallet_owner => v_config.sender_wallet_owner,
        p_receiver_wallet_owner => v_config.receiver_wallet_owner,
        p_currency_code => v_currency,
        p_country_code => v_user.country_code,
        p_audit_action_type => v_config.audit_action_type,
        p_ip_address => p_ip_address
    );

    if v_tax > 0 then
        v_tax_rate := public.fetch_government_tax_rate(
            v_type, v_currency, v_user.country_code
        );

        insert into public.government_tax_payable (
            document_number, fiscal_year, period, transaction_type,
            currency_code, gross_amount, tax_amount, tax_rate, is_settled, country_code
        ) values (
            v_document, v_fiscal.fiscal_year, v_fiscal.period, v_type,
            v_currency, v_amount, v_tax, coalesce(v_tax_rate, 0), false, v_user.country_code
        );
    end if;

    update public.transaction_state
    set status = 'success', updated_at = now()
    where id = v_state_id;

    return jsonb_build_object(
        'success', true, 'reference', v_reference, 'currency', v_currency,
        'amount', trim_scale(v_amount)::text,
        'fee', trim_scale(v_fee)::text,
        'tax', trim_scale(v_tax)::text,
        'total_debit', trim_scale(v_debit)::text,
        'financial_transaction_id', v_financial_id::text
    );
end;
$function$;

revoke all on function public.commission_withdrawal(text, text, text, jsonb, jsonb, text)
from public, anon, authenticated;
grant execute on function public.commission_withdrawal(text, text, text, jsonb, jsonb, text)
to service_role;

commit;
