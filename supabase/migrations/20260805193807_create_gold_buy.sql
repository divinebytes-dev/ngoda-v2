/* =========================================================
 * FETCH MY GOLD-BUY CONTEXT
 * ========================================================= */

create or replace function public.fetch_my_gold_buy_context(
    p_v text
)
returns table (
    user_id text,
    country_code text,
    wallet_address text,
    version_time integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Gold buy remains on v7.
     */
    if p_v is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Users with customer-owned wallets may buy gold.
     */
    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    return query
    select
        user_record.id,
        user_record.country_code,
        user_record.wallet_address,
        public.get_transaction_v(p_v)
    from public.users user_record
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'GOLD_BUY_CONTEXT_NOT_FOUND';
    end if;
end;
$function$;


/* =========================================================
 * CREATE MY GOLD-BUY TRANSACTION STATE
 * ========================================================= */

create or replace function public.create_my_gold_buy_state(
    p_transaction jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
    v_country_code text;
    v_reference text;
    v_version text;

    v_transaction_state_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_transaction is null
       or jsonb_typeof(p_transaction) <>
          'object'
    then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    if v_version is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_user_id :=
        auth.uid()::text;

    select user_record.country_code
    into v_country_code
    from public.users user_record
    where user_record.id =
          v_user_id
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'USER_NOT_AUTHORIZED';
    end if;

    /*
     * The authenticated buyer is stored as the state
     * participant. transaction.s remains part of the
     * signed canonical transaction but is not trusted
     * as the authenticated user ID.
     */
    insert into public.transaction_state (
        reference,
        status,
        transaction_type,
        country_code,
        transaction_data,
        created_by,
        user_id
    )
    values (
        v_reference,
        'processing'::public."TransactionStatus",
        'gold_token_buy'::public."TransactionType",
        v_country_code,
        p_transaction,
        v_user_id,
        v_user_id
    )
    returning id::text
    into v_transaction_state_id;

    return v_transaction_state_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$function$;


/* =========================================================
 * PREPARE GOLD BUY
 * ========================================================= */

create or replace function public.prepare_gold_buy(
    p_user_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text
)
returns table (
    user_id text,
    country_code text,
    user_wallet_address text,

    treasury_id text,
    treasury_wallet_address text,
    treasury_wallet_index integer,

    fiscal_year integer,
    period integer,
    document_prefix text,

    input_amount text,
    input_currency text,

    token_quantity text,
    gross_token_quantity text,
    token_fee text,

    gross_amount text,
    spread text
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_amount numeric;
    v_currency text;

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_fiscal_year integer;
    v_period integer;

    v_transaction_state
        public.transaction_state%rowtype;

    v_fiat_mappings
        public.transaction_gl_mapping[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_fiat_components
        public.posting_component[];

    v_token_components
        public.posting_component[];

    v_token_quantity numeric := 0;
    v_gross_token_quantity numeric := 0;
    v_token_fee numeric := 0;

    v_gross_amount numeric := 0;
    v_spread numeric := 0;

    v_document_prefix text;

    v_sub_transaction_type
        public."TransactionType" :=
            'gold_token_buy_sub_tx'::public."TransactionType";
begin
    /*
     * Validate and read the processing transaction.
     */
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
    limit 1;

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

    if p_transaction ->> 'v' is distinct from
       'v7'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Validate the buyer role.
     */
    if not public.user_has_role(
        p_user_id,
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Parse signed transaction fields.
     */
    v_amount :=
        (p_transaction ->> 'a')::numeric /
        100;

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    /*
     * Fetch buyer and treasury.
     */
    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_user.wallet_address is null
       or btrim(v_user.wallet_address) = ''
    then
        raise exception
            'USER_WALLET_NOT_CONFIGURED';
    end if;

    if v_treasury.wallet_address is null
       or btrim(v_treasury.wallet_address) = ''
       or v_treasury.wallet_index is null
    then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;

    if v_user.country_code is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Fetch fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        p_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch fiat mappings.
     */
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

    /*
     * Fetch gold-token mappings.
     */
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

    /*
     * Build fiat components.
     */
    v_fiat_components :=
        public.build_posting_components(
            'gold_token_buy'::public."TransactionType",
            v_amount,
            v_fiat_mappings,
            p_country_code,
            v_currency,
            false
        );

    /*
     * Build reversed gold-token components.
     */
    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_amount,
            v_token_mappings,
            p_country_code,
            v_currency,
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
     * Extract net and gross token quantities.
     */
    select
        coalesce(
            component.debit_amount,
            0
        ),
        coalesce(
            component.credit_amount,
            0
        )
    into
        v_token_quantity,
        v_gross_token_quantity
    from unnest(v_token_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'principal'::public."ComponentType"
    limit 1;

    v_token_quantity :=
        public.round_down(
            coalesce(
                v_token_quantity,
                0
            )
        );

    v_gross_token_quantity :=
        public.round_down(
            coalesce(
                v_gross_token_quantity,
                0
            )
        );

    if v_token_quantity <= 0 then
        raise exception
            'INVALID_QUANTITY';
    end if;

    /*
     * Extract the token-denominated transaction fee.
     */
    select coalesce(
        component.debit_amount,
        0
    )
    into v_token_fee
    from unnest(v_token_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_token_fee :=
        public.round_down(
            coalesce(
                v_token_fee,
                0
            )
        );

    /*
     * Extract the fiat gross amount.
     */
    select coalesce(
        component.debit_amount,
        0
    )
    into v_gross_amount
    from unnest(v_fiat_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'principal'::public."ComponentType"
    limit 1;

    v_gross_amount :=
        coalesce(
            v_gross_amount,
            0
        );

    if v_gross_amount <= 0 then
        raise exception
            'INVALID_GROSS_AMOUNT';
    end if;

    /*
     * Extract trading spread.
     */
    select coalesce(
        component.credit_amount,
        0
    )
    into v_spread
    from unnest(v_fiat_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'trading_spread'::public."ComponentType"
    limit 1;

    v_spread :=
        coalesce(
            v_spread,
            0
        );

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_buy'::public."TransactionType"
        );

    return query
    select
        v_user.id,
        p_country_code,
        v_user.wallet_address,

        v_treasury.id,
        v_treasury.wallet_address,
        v_treasury.wallet_index::integer,

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_amount::text,
        v_currency,

        v_token_quantity::text,
        v_gross_token_quantity::text,
        v_token_fee::text,

        v_gross_amount::text,
        v_spread::text;
end;
$function$;


/* =========================================================
 * FUNCTION OWNERS
 * ========================================================= */

alter function public.fetch_my_gold_buy_context(
    text
)
owner to postgres;

alter function public.create_my_gold_buy_state(
    jsonb
)
owner to postgres;

alter function public.prepare_gold_buy(
    text,
    jsonb,
    text,
    text
)
owner to postgres;


/* =========================================================
 * EXECUTION PERMISSIONS
 * ========================================================= */

revoke execute on function
    public.fetch_my_gold_buy_context(text)
from public, anon;

grant execute on function
    public.fetch_my_gold_buy_context(text)
to authenticated;


revoke execute on function
    public.create_my_gold_buy_state(jsonb)
from public, anon;

grant execute on function
    public.create_my_gold_buy_state(jsonb)
to authenticated;


/*
 * Preparation is called by the Edge Function only after
 * user signature verification.
 */
revoke execute on function
    public.prepare_gold_buy(
        text,
        jsonb,
        text,
        text
    )
from public, anon, authenticated;

grant execute on function
    public.prepare_gold_buy(
        text,
        jsonb,
        text,
        text
    )
to service_role;


/* =========================================================
 * RELOAD POSTGREST
 * ========================================================= */

notify pgrst, 'reload schema';