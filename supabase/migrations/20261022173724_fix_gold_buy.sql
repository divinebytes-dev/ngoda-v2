BEGIN;

-- 01_preparation_storage.sql
ALTER TABLE public.transaction_state
ADD COLUMN IF NOT EXISTS gold_buy_preparation jsonb;

COMMENT ON COLUMN public.transaction_state.gold_buy_preparation IS
'Immutable server-calculated Gold Buy preparation: pricing, components, GL mappings and participants. Never supplied by the client.';

CREATE OR REPLACE FUNCTION public.guard_gold_buy_preparation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.gold_buy_preparation IS NOT NULL THEN
      IF NEW.gold_buy_preparation IS DISTINCT FROM OLD.gold_buy_preparation THEN
        RAISE EXCEPTION 'GOLD_BUY_PREPARATION_IS_IMMUTABLE';
      END IF;
      IF NEW.id IS DISTINCT FROM OLD.id
         OR NEW.reference IS DISTINCT FROM OLD.reference
         OR NEW.created_by IS DISTINCT FROM OLD.created_by
         OR NEW.user_id IS DISTINCT FROM OLD.user_id
         OR NEW.country_code IS DISTINCT FROM OLD.country_code
         OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
         OR NEW.blockchain_code IS DISTINCT FROM OLD.blockchain_code
         OR NEW.transaction_data IS DISTINCT FROM OLD.transaction_data THEN
        RAISE EXCEPTION 'PREPARED_GOLD_BUY_IDENTITY_IS_IMMUTABLE';
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.gold_buy_preparation IS NOT NULL THEN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
      RAISE EXCEPTION USING errcode='42501', message='SERVICE_ROLE_REQUIRED';
    END IF;
    IF NEW.transaction_type IS DISTINCT FROM 'gold_token_buy'::public."TransactionType"
       OR jsonb_typeof(NEW.gold_buy_preparation) IS DISTINCT FROM 'object'
       OR NEW.gold_buy_preparation ->> 'schema_version' IS DISTINCT FROM '1'
       OR NEW.gold_buy_preparation ->> 'transaction_state_id' IS DISTINCT FROM NEW.id
       OR NEW.gold_buy_preparation -> 'transaction_data' IS DISTINCT FROM NEW.transaction_data
       OR NEW.gold_buy_preparation -> 'preparation' ->> 'blockchain_code' IS DISTINCT FROM NEW.blockchain_code
       OR NEW.gold_buy_preparation -> 'preparation' ->> 'user_id' IS DISTINCT FROM NEW.user_id
       OR NEW.gold_buy_preparation -> 'preparation' ->> 'country_code' IS DISTINCT FROM NEW.country_code THEN
      RAISE EXCEPTION 'INVALID_GOLD_BUY_PREPARATION_SNAPSHOT';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.guard_gold_buy_preparation() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.guard_gold_buy_preparation()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS ngoda_guard_gold_buy_preparation ON public.transaction_state;
CREATE TRIGGER ngoda_guard_gold_buy_preparation
BEFORE INSERT OR UPDATE ON public.transaction_state
FOR EACH ROW EXECUTE FUNCTION public.guard_gold_buy_preparation();

-- Column-level revocation alone cannot override a table-wide UPDATE grant.
-- The trigger above enforces protection even if such a grant exists.
REVOKE UPDATE (gold_buy_preparation) ON public.transaction_state FROM anon, authenticated;

-- 02_execution_pricing.sql
-- One quote operation reads configs and the Gold market price once, computes
-- each accounting leg once, and preserves the existing per-leg fee/tax keys.
-- It does not call calculate_gold_buy_pricing or build_posting_components.
CREATE OR REPLACE FUNCTION public.calculate_gold_buy_execution_pricing(
  p_amount numeric, p_country_code text, p_currency_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
  v_configs jsonb;
  v_config jsonb;
  v_currency text := lower(btrim(p_currency_code));
  v_leg text;
  v_type public."TransactionType";
  v_fee public.amount_config;
  v_tax_config public.amount_config;
  v_spread_config public.amount_config;
  v_market numeric;
  v_buy numeric;
  v_quantity numeric;
  v_paid numeric;
  v_base numeric;
  v_fee_fiat numeric;
  v_fee_gold numeric;
  v_spread numeric;
  v_tax numeric;
  v_pricing public.pricing_result;
  v_result jsonb := '{}'::jsonb;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0
     OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;
  IF v_currency IS NULL OR v_currency NOT IN ('usd','gold') THEN
    RAISE EXCEPTION 'UNSUPPORTED_GOLD_BUY_CURRENCY';
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) INTO v_configs
  FROM public.fetch_all_transaction_configs(p_country_code, v_currency) c;

  FOR v_config IN SELECT value FROM jsonb_array_elements(v_configs)
  LOOP
    IF lower(v_config ->> 'config_key') = 'gold_spread_buy'
       AND lower(v_config ->> 'currency_code') = 'gold' THEN
      v_spread_config := ROW(
        (v_config ->> 'percentage')::numeric,
        (v_config ->> 'fixed_amount')::numeric,
        (v_config ->> 'min_amount')::numeric,
        (v_config ->> 'max_amount')::numeric
      )::public.amount_config;
    END IF;
  END LOOP;

  v_market := public.fetch_gold_price();
  IF v_market IS NULL OR v_market <= 0
     OR v_market::text IN ('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION 'GOLD_MARKET_PRICE_NOT_FOUND';
  END IF;
  v_buy := v_market * (1 + coalesce(v_spread_config.percentage, 0) / 100);
  IF v_buy <= 0 THEN RAISE EXCEPTION 'INVALID_GOLD_BUY_PRICE'; END IF;

  FOREACH v_leg IN ARRAY ARRAY['fiat_pricing','token_pricing']::text[]
  LOOP
    v_type := public.get_base_transaction_type(
      CASE WHEN v_leg = 'fiat_pricing'
        THEN 'gold_token_buy'::public."TransactionType"
        ELSE 'gold_token_buy_sub_tx'::public."TransactionType" END
    );
    -- These are the identities the supplied builder expects for Gold Buy.
    IF (v_leg = 'fiat_pricing' AND v_type IS DISTINCT FROM 'gold_token_buy'::public."TransactionType")
       OR (v_leg = 'token_pricing' AND v_type IS DISTINCT FROM 'gold_token_buy_sub_tx'::public."TransactionType") THEN
      RAISE EXCEPTION 'UNEXPECTED_GOLD_BUY_BASE_TRANSACTION_TYPE_%', v_type;
    END IF;
    v_fee := NULL;
    v_tax_config := NULL;
    FOR v_config IN SELECT value FROM jsonb_array_elements(v_configs)
    LOOP
      IF lower(v_config ->> 'currency_code') = v_currency THEN
        IF lower(v_config ->> 'config_key') = lower(v_type::text) THEN
          v_fee := ROW(
            (v_config ->> 'percentage')::numeric,
            (v_config ->> 'fixed_amount')::numeric,
            (v_config ->> 'min_amount')::numeric,
            (v_config ->> 'max_amount')::numeric
          )::public.amount_config;
        END IF;
        IF lower(v_config ->> 'config_key') = lower(v_type::text) || '_tax' THEN
          v_tax_config := ROW(
            (v_config ->> 'percentage')::numeric,
            (v_config ->> 'fixed_amount')::numeric,
            (v_config ->> 'min_amount')::numeric,
            (v_config ->> 'max_amount')::numeric
          )::public.amount_config;
        END IF;
      END IF;
    END LOOP;

    IF v_currency = 'gold' THEN
      v_quantity := p_amount;
      v_base := v_quantity * v_buy;
      v_fee_fiat := public.calculate_configured_amount(v_base, v_fee);
      v_paid := v_base + v_fee_fiat;
    ELSE
      v_paid := p_amount;
      v_fee_fiat := public.calculate_configured_amount(v_paid, v_fee);
      v_base := v_paid - v_fee_fiat;
      IF v_base <= 0 THEN RAISE EXCEPTION 'INVALID_GOLD_BUY_FIAT_BASE'; END IF;
      v_quantity := v_base / v_buy;
    END IF;
    v_fee_gold := v_fee_fiat / v_buy;
    v_spread := v_base - v_quantity * v_market;
    v_tax := public.calculate_configured_amount(v_paid, v_tax_config);
    IF v_quantity <= 0 OR v_paid <= 0 OR v_base <= 0 THEN
      RAISE EXCEPTION 'INVALID_GOLD_BUY_CALCULATED_PRICING';
    END IF;
    v_pricing := ROW(
      public.round_down(CASE WHEN v_leg = 'fiat_pricing' THEN v_fee_fiat ELSE v_fee_gold END),
      public.round_down(CASE WHEN v_leg = 'fiat_pricing' THEN v_tax ELSE 0 END),
      public.round_down(CASE WHEN v_leg = 'fiat_pricing' THEN v_spread ELSE 0 END),
      0, public.round_down(v_quantity), public.round_down(v_paid), public.round_down(v_buy)
    )::public.pricing_result;
    v_result := v_result || jsonb_build_object(v_leg, to_jsonb(v_pricing));
  END LOOP;
  RETURN v_result || jsonb_build_object('market_price', v_market::text);
END;
$function$;

ALTER FUNCTION public.calculate_gold_buy_execution_pricing(numeric,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.calculate_gold_buy_execution_pricing(numeric,text,text)
FROM PUBLIC, anon, authenticated, service_role;

-- 03_components_from_saved_pricing.sql
CREATE OR REPLACE FUNCTION public.build_gold_buy_components_from_pricing(
    p_transaction_type public."TransactionType",
    p_principal numeric,
    p_mappings public.transaction_gl_mapping[],
    p_pricing public.pricing_result,
    p_reverse boolean DEFAULT false
)
 RETURNS posting_component[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
    v_components
        public.posting_component[] :=
            array[]::public.posting_component[];

    /*
     * pricing_result now contains:
     *
     * fee
     * tax
     * spread
     * commission
     * quantity
     * fiat_received
     * gold_price
     */
    v_pricing public.pricing_result := p_pricing;

    v_transaction_type
        public."TransactionType";

    v_principal_mode
        public."PrincipalMode";

    v_mapping
        public.transaction_gl_mapping%rowtype;

    v_component
        public.posting_component;

    v_principal_component
        public.posting_component;

    v_new_principal numeric;

    v_charges numeric :=
        0;

    v_raw_amount numeric;

    v_amount numeric;

    v_reverse boolean :=
        coalesce(
            p_reverse,
            false
        );

    /*
     * Debugging information.
     */
    v_stage text :=
        'initialization';

    v_mapping_position integer :=
        0;

    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
    v_error_state text;

begin
    /*
     * ==========================================================
     * INITIAL PRINCIPAL
     * ==========================================================
     */
    v_stage :=
        'round principal';


    v_new_principal :=
        public.round_down(
            p_principal
        );


    /*
     * ==========================================================
     * BASE TRANSACTION TYPE
     * ==========================================================
     */
    v_stage :=
        'resolve base transaction type';


    v_transaction_type :=
        public.get_base_transaction_type(
            p_transaction_type
        );


    /*
     * ==========================================================
     * USE SUPPLIED PRICING
     * ==========================================================
     */
    if p_transaction_type not in (
        'gold_token_buy'::public."TransactionType",
        'gold_token_buy_sub_tx'::public."TransactionType"
    ) or p_principal is null or p_principal <= 0
       or p_mappings is null or cardinality(p_mappings) = 0 then
        raise exception 'INVALID_GOLD_BUY_COMPONENT_INPUT';
    end if;

    v_stage :=
        'resolve principal mode';


    v_principal_mode :=
        public.resolve_principal_mode(
            v_transaction_type
        );


    /*
     * ==========================================================
     * BUILD NON-PRINCIPAL COMPONENTS
     * ==========================================================
     */
    v_stage :=
        'iterate mappings';


    foreach v_mapping in array p_mappings
    loop
        v_mapping_position :=
            v_mapping_position + 1;


        v_stage :=
            format(
                'mapping %s: read component_type',
                v_mapping_position
            );


        if v_mapping.component_type =
           'principal'::public."ComponentType"
        then
            continue;
        end if;


        v_stage :=
            format(
                'mapping %s: resolve component amount',
                v_mapping_position
            );


        v_raw_amount :=
            public.resolve_component_amount(
                v_mapping.component_type,
                v_pricing
            );


        v_stage :=
            format(
                'mapping %s: round component amount',
                v_mapping_position
            );


        v_amount :=
            public.round_down(
                v_raw_amount
            );


        /*
         * Zero-value configured components are deliberately
         * skipped.
         *
         * This allows fees and taxes to be disabled by
         * configuring them as zero.
         */
        if v_amount <= 0 then
            continue;
        end if;


        v_stage :=
            format(
                'mapping %s: check self balancing',
                v_mapping_position
            );


        if public.is_self_balancing_component(
            v_mapping.component_type
        )
        then
            v_component :=
                row(
                    v_mapping.component_type,
                    v_amount,
                    v_amount
                )::public.posting_component;


            v_components :=
                array_append(
                    v_components,
                    v_component
                );


            continue;
        end if;


        /*
         * Only non-self-balancing components form part of
         * the amount needed by build_principal_component().
         */
        v_charges :=
            v_charges +
            v_amount;


        v_stage :=
            format(
                'mapping %s: build posting component',
                v_mapping_position
            );


        if v_reverse then
            v_component :=
                row(
                    v_mapping.component_type,
                    v_amount,
                    0
                )::public.posting_component;

        else
            v_component :=
                row(
                    v_mapping.component_type,
                    0,
                    v_amount
                )::public.posting_component;
        end if;


        v_components :=
            array_append(
                v_components,
                v_component
            );
    end loop;


    /*
     * ==========================================================
     * BUILD PRINCIPAL COMPONENT
     * ==========================================================
     */
    v_stage :=
        'build principal component';


    v_principal_component :=
        public.build_principal_component(
            v_new_principal,
            v_charges,
            v_principal_mode,
            v_reverse
        );


    /*
     * ==========================================================
     * PREPEND PRINCIPAL
     * ==========================================================
     */
    v_stage :=
        'prepend principal component';


    v_components :=
        array_prepend(
            v_principal_component,
            v_components
        );


    /*
     * ==========================================================
     * VALIDATE COMPONENTS
     * ==========================================================
     */
    v_stage :=
        'validate components';


    return public.validate_components(
        v_components
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
                coalesce(
                    nullif(
                        v_error_state,
                        ''
                    ),
                    'P0001'
                ),

            message =
                format(
                    'BUILD_POSTING_COMPONENTS_FAILED at [%s]: %s',
                    coalesce(
                        nullif(
                            v_stage,
                            ''
                        ),
                        'unknown'
                    ),
                    coalesce(
                        nullif(
                            v_error_message,
                            ''
                        ),
                        'UNKNOWN_POSTING_COMPONENT_ERROR'
                    )
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
                    'Check the posting-component stage reported in the error'
                );
end;
$function$;

ALTER FUNCTION public.build_gold_buy_components_from_pricing(public."TransactionType",numeric,public.transaction_gl_mapping[],public.pricing_result,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.build_gold_buy_components_from_pricing(public."TransactionType",numeric,public.transaction_gl_mapping[],public.pricing_result,boolean)
FROM PUBLIC, anon, authenticated, service_role;

-- 04_prepare_gold_buy.sql
CREATE OR REPLACE FUNCTION public.prepare_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_code text)
 RETURNS TABLE(user_id text, country_code text, user_wallet_address text, treasury_id text, treasury_wallet_address text, treasury_wallet_index bigint, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, gross_token_quantity text, token_fee text, gross_amount text, spread text, blockchain_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_execution_pricing jsonb;
    v_token_pricing public.pricing_result;
    v_saved jsonb;
    v_preparation_json jsonb;
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
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
    /*
     * Exact pricing result used for this Gold Buy.
     *
     * gold_price is the customer Buy price per gram,
     * including the configured Buy spread.
     */
    v_pricing public.pricing_result;
    v_gold_price numeric := 0;
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
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    v_blockchain_code := lower(nullif(btrim(p_blockchain_code), ''));
    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;
    perform 1 from public.supported_blockchain b
    where b.code = v_blockchain_code and b.is_active = true
      and exists (
        select 1 from public.supported_blockchain_network n
        where n.blockchain_id = b.id and n.is_active = true
      );
    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    end if;
    v_stage := 'Validate and read the processing transaction';
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
    limit 1
    for update;
    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;
    if v_transaction_state.blockchain_code is distinct from v_blockchain_code then
        raise exception 'TRANSACTION_BLOCKCHAIN_MISMATCH';
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
    if v_transaction_state.reference is distinct from p_transaction ->> 'r'
       or nullif(btrim(p_transaction ->> 'r'), '') is null then
        raise exception 'TRANSACTION_REFERENCE_MISMATCH';
    end if;
    v_stage := 'Validate the buyer role';
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
    v_stage := 'Parse signed transaction fields';
    /*
     * Parse signed transaction fields.
     */
    v_amount :=
        (p_transaction ->> 'a')::numeric /
        100;
    if v_amount is null or v_amount::text in ('NaN', 'Infinity', '-Infinity') or v_amount <= 0 then
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
    if v_currency not in ('usd', 'gold') then
        raise exception 'UNSUPPORTED_GOLD_BUY_CURRENCY';
    end if;
    v_saved := v_transaction_state.gold_buy_preparation;
    if v_saved is not null then
        if v_saved ->> 'schema_version' is distinct from '1'
           or v_saved ->> 'transaction_state_id' is distinct from p_transaction_state_id
           or v_saved -> 'transaction_data' is distinct from p_transaction
           or jsonb_typeof(v_saved -> 'preparation') is distinct from 'object'
           or v_saved -> 'preparation' ->> 'blockchain_code' is distinct from v_blockchain_code
           or v_saved -> 'preparation' ->> 'user_id' is distinct from p_user_id
           or v_saved -> 'preparation' ->> 'country_code' is distinct from p_country_code
           or jsonb_typeof(v_saved -> 'fiat_components') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'token_components') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'fiat_mappings') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'token_mappings') is distinct from 'array' then
            raise exception 'INVALID_SAVED_GOLD_BUY_PREPARATION';
        end if;
        return query
        select saved.* from jsonb_to_record(v_saved -> 'preparation') as saved(user_id text, country_code text, user_wallet_address text, treasury_id text, treasury_wallet_address text, treasury_wallet_index bigint, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, gross_token_quantity text, token_fee text, gross_amount text, spread text, blockchain_code text);
        return;
    end if;

    -- A historical submitted purchase without a saved quote must be reconciled.
    -- Never invent a new quote after tokens may already have moved.
    if exists (select 1 from public.blockchain_transaction b
               where b.reference = p_transaction ->> 'r' and b.created_by = p_user_id)
       or exists (select 1 from public.financial_transaction f
                  where f.reference = p_transaction ->> 'r' and f.created_by = p_user_id) then
        raise exception 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;

    v_stage := 'calculate exact gold-buy pricing';
    /*
     * Calculate the exact Gold Buy price used by this
     * transaction.
     *
     * Do not fetch the Gold market price independently.
     * calculate_gold_buy_execution_pricing is the pricing source of
     * truth and returns the Buy price in gold_price.
     */
    v_execution_pricing := public.calculate_gold_buy_execution_pricing(
        v_amount, p_country_code, v_currency
    );
    v_pricing := jsonb_populate_record(
        null::public.pricing_result, v_execution_pricing -> 'fiat_pricing'
    );
    v_token_pricing := jsonb_populate_record(
        null::public.pricing_result, v_execution_pricing -> 'token_pricing'
    );
    v_gold_price :=
        coalesce(
            v_pricing.gold_price,
            0
        );
    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_PRICE';
    end if;
    v_stage := 'Fetch buyer and treasury';
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
    if v_user.id is null or v_user.status is distinct from 'active'::public."UserStatus" then
        raise exception 'USER_NOT_AUTHORIZED';
    end if;
    if v_treasury.id is null or v_treasury.status is distinct from 'active'::public."UserStatus"
       or v_treasury.country_code is distinct from p_country_code then
        raise exception 'TREASURY_NOT_AUTHORIZED';
    end if;
    if v_treasury.wallet_index < 0 then
        raise exception 'INVALID_WALLET_INDEX';
    end if;
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
    v_stage := 'Fetch fiscal period';
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
    v_stage := 'Fetch fiat mappings';
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
    v_stage := 'Fetch gold-token mappings';
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
    v_stage := 'Build fiat components';
    /*
     * Build fiat components.
     */
    v_fiat_components := public.build_gold_buy_components_from_pricing(
        'gold_token_buy'::public."TransactionType",
        case when v_currency = 'gold' then v_pricing.fiat_received else v_amount end,
        v_fiat_mappings, v_pricing, false
    );
    v_stage := 'Build reversed gold-token components';
    /*
     * Build reversed gold-token components.
     */
    v_token_components := public.build_gold_buy_components_from_pricing(
        v_sub_transaction_type, v_token_pricing.quantity,
        v_token_mappings, v_token_pricing, true
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
    v_stage := 'Extract net and gross token quantities';
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
    v_stage := 'Extract the token-denominated transaction fee';
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
    v_stage := 'Extract the fiat gross amount';
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
    v_stage := 'Extract trading spread';
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
    v_fiat_components := public.validate_components(v_fiat_components);
    v_token_components := public.validate_components(v_token_components);
    if v_token_fee < 0 or v_spread < 0 then
        raise exception 'INVALID_POSTING_COMPONENT_AMOUNT';
    end if;
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_buy'::public."TransactionType"
        );
    if nullif(btrim(v_document_prefix), '') is null then
        raise exception 'DOCUMENT_PREFIX_NOT_FOUND';
    end if;
    v_stage := 'validate sender wallets';
    perform 1 from public.wallet w
    where w.user_id = p_user_id and w.country_code = p_country_code
      and w.currency_code = 'usd'
      and w.owner_type = 'customer'::public."WalletOwnerType"
      and w.blockchain_code is null and w.is_active = true
      and w.balance >= v_gross_amount;
    if not found then
        raise exception 'BUYER_USD_WALLET_UNAVAILABLE_OR_INSUFFICIENT';
    end if;
    perform 1 from public.wallet w
    where w.user_id = v_treasury.id and w.country_code = p_country_code
      and w.currency_code = 'gold'
      and w.owner_type = 'treasury'::public."WalletOwnerType"
      and w.blockchain_code = v_blockchain_code and w.is_active = true
      and w.balance >= v_token_quantity;
    if not found then
        raise exception 'TREASURY_GOLD_WALLET_UNAVAILABLE_OR_INSUFFICIENT';
    end if;
    v_preparation_json := jsonb_build_object(
        'user_id', v_user.id,
        'country_code', p_country_code,
        'user_wallet_address', v_user.wallet_address,
        'treasury_id', v_treasury.id,
        'treasury_wallet_address', v_treasury.wallet_address,
        'treasury_wallet_index', v_treasury.wallet_index,
        'fiscal_year', v_fiscal_year,
        'period', v_period,
        'document_prefix', v_document_prefix,
        'input_amount', v_amount::text,
        'input_currency', v_currency,
        'gold_price', v_gold_price::text,
        'token_quantity', v_token_quantity::text,
        'gross_token_quantity', v_gross_token_quantity::text,
        'token_fee', v_token_fee::text,
        'gross_amount', v_gross_amount::text,
        'spread', v_spread::text,
        'blockchain_code', v_blockchain_code
    );
    v_saved := jsonb_build_object(
        'schema_version', 1,
        'transaction_state_id', p_transaction_state_id,
        'transaction_data', p_transaction,
        'prepared_at', clock_timestamp(),
        'preparation', v_preparation_json,
        'pricing', v_execution_pricing,
        'fiat_components', to_jsonb(v_fiat_components),
        'token_components', to_jsonb(v_token_components),
        'fiat_mappings', to_jsonb(v_fiat_mappings),
        'token_mappings', to_jsonb(v_token_mappings)
    );
    update public.transaction_state s
    set gold_buy_preparation = v_saved, updated_at = now()
    where s.id = p_transaction_state_id and s.gold_buy_preparation is null;
    if not found then raise exception 'GOLD_BUY_PREPARATION_SAVE_FAILED'; end if;

    v_stage := 'return preparation';
    return query
    select
        v_user.id,
        p_country_code,
        v_user.wallet_address,
        v_treasury.id,
        v_treasury.wallet_address,
        v_treasury.wallet_index::bigint,
        v_fiscal_year,
        v_period,
        v_document_prefix,
        v_amount::text,
        v_currency,
        v_gold_price::text,
        v_token_quantity::text,
        v_gross_token_quantity::text,
        v_token_fee::text,
        v_gross_amount::text,
        v_spread::text,
        v_blockchain_code;
exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;

ALTER FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) TO service_role;

-- 05_record_gold_buy_blockchain_transaction.sql
CREATE OR REPLACE FUNCTION public.record_gold_buy_blockchain_transaction(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_tx_hash text, p_explorer_url text, p_blockchain_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
    v_preparation record;
    v_user public.users%rowtype;
    v_reference text;
    v_blockchain_transaction_id text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    v_blockchain_code := lower(nullif(btrim(p_blockchain_code), ''));
    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;
    perform 1 from public.supported_blockchain b
    where b.code = v_blockchain_code and b.is_active = true
      and exists (
        select 1 from public.supported_blockchain_network n
        where n.blockchain_id = b.id and n.is_active = true
      );
    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    end if;
    if p_tx_hash is null
       or p_tx_hash !~
          '^0x[0-9a-fA-F]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;
    if p_explorer_url is null
       or btrim(p_explorer_url) = ''
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISSING';
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
    v_stage := 'require saved preparation before recording submission';
    perform 1 from public.transaction_state s
    where s.id = p_transaction_state_id and s.created_by = p_user_id
      and s.user_id = p_user_id and s.country_code = p_country_code
      and s.transaction_data = p_transaction and s.blockchain_code = v_blockchain_code
      and s.transaction_type = 'gold_token_buy'::public."TransactionType"
      and s.status = 'processing'::public."TransactionStatus"
      and s.gold_buy_preparation is not null
    for update;
    if not found then
        raise exception 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    v_stage := 'read saved gold-buy preparation';
    /*
     * prepare_gold_buy returns the saved preparation here.
     * The guard above prohibits first-time pricing after submission.
     */
    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) as preparation;
    if not found then
        raise exception
            'GOLD_BUY_PREPARATION_NOT_FOUND';
    end if;
    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );
    v_stage := 'insert database record';
    insert into public.blockchain_transaction (
        fiscal_year,
        period,
        country_code,
        tx_hash,
        document_number,
        reference,
        transaction_type,
        chain,
        blockchain_code,
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
        description
    )
    values (
        v_preparation.fiscal_year,
        v_preparation.period,
        p_country_code,
        lower(p_tx_hash),
        null,
        v_reference,
        'gold_token_buy'::public."TransactionType",
        v_blockchain_code,
        v_blockchain_code,
        v_preparation.treasury_wallet_address,
        v_preparation.user_wallet_address,
        v_preparation.token_quantity::numeric,
        v_preparation.input_amount::numeric,
        0,
        v_preparation.token_fee::numeric,
        v_preparation.input_currency,
        p_explorer_url,
        'pending'::public."BlockchainTxStatus",
        p_user_id,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.token_quantity ||
        'g Gold tokens'
    )
    returning id::text
    into v_blockchain_transaction_id;
    if v_blockchain_transaction_id is null then
        raise exception 'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    end if;
    return v_blockchain_transaction_id;
exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message =
                'BLOCKCHAIN_TRANSACTION_REPLAY';
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;

ALTER FUNCTION public.record_gold_buy_blockchain_transaction(text,jsonb,text,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_gold_buy_blockchain_transaction(text,jsonb,text,text,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_gold_buy_blockchain_transaction(text,jsonb,text,text,text,text,text) TO service_role;

-- 06_complete_gold_buy.sql
CREATE OR REPLACE FUNCTION public.complete_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_transaction_id text, p_blockchain_code text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, quantity text, total_spent text, explorer_url text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_saved jsonb;
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
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    v_blockchain_code := lower(nullif(btrim(p_blockchain_code), ''));
    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;
    perform 1 from public.supported_blockchain b
    where b.code = v_blockchain_code and b.is_active = true
      and exists (
        select 1 from public.supported_blockchain_network n
        where n.blockchain_id = b.id and n.is_active = true
      );
    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    end if;
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
    if v_transaction_state.blockchain_code is distinct from v_blockchain_code then
        raise exception 'TRANSACTION_BLOCKCHAIN_MISMATCH';
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
     * Read the existing immutable preparation. Never calculate a new quote
     * after a blockchain row has been recorded.
     */
    v_saved := v_transaction_state.gold_buy_preparation;
    if v_saved is null then
        raise exception 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    v_stage := 'read saved gold buy';
    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
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
    if v_blockchain_transaction.chain::text is distinct from
       v_blockchain_code then
        raise exception 'BLOCKCHAIN_CHAIN_MISMATCH';
    end if;
    if v_blockchain_transaction.blockchain_code is distinct from v_blockchain_code then
        raise exception 'BLOCKCHAIN_CODE_MISMATCH';
    end if;
    if v_blockchain_transaction.currency_code is distinct from v_preparation.input_currency then
        raise exception 'BLOCKCHAIN_CURRENCY_MISMATCH';
    end if;
    if v_blockchain_transaction.net_amount is distinct from 0::numeric then
        raise exception 'BLOCKCHAIN_NET_AMOUNT_MISMATCH';
    end if;
    if v_blockchain_transaction.quantity
       is distinct from
       v_preparation.token_quantity::numeric
    then
        raise exception using message = 'BLOCKCHAIN_QUANTITY_MISMATCH',
            detail = format('Saved preparation quantity=%s; blockchain record quantity=%s',
                v_preparation.token_quantity, v_blockchain_transaction.quantity);
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
    /* Load the exact components and GL mappings saved before signing. */
    v_stage := 'load saved posting components and mappings';
    select array_agg(
        jsonb_populate_record(null::public.transaction_gl_mapping, e.value) order by e.ordinality
    ) into v_fiat_mappings
    from jsonb_array_elements(v_saved -> 'fiat_mappings') with ordinality e(value, ordinality);
    if v_fiat_mappings is null or cardinality(v_fiat_mappings) = 0 then
        raise exception 'SAVED_GOLD_BUY_FIAT_MAPPINGS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.transaction_gl_mapping, e.value) order by e.ordinality
    ) into v_token_mappings
    from jsonb_array_elements(v_saved -> 'token_mappings') with ordinality e(value, ordinality);
    if v_token_mappings is null or cardinality(v_token_mappings) = 0 then
        raise exception 'SAVED_GOLD_BUY_TOKEN_MAPPINGS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.posting_component, e.value) order by e.ordinality
    ) into v_fiat_components
    from jsonb_array_elements(v_saved -> 'fiat_components') with ordinality e(value, ordinality);
    if v_fiat_components is null or cardinality(v_fiat_components) = 0 then
        raise exception 'SAVED_GOLD_BUY_FIAT_COMPONENTS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.posting_component, e.value) order by e.ordinality
    ) into v_token_components
    from jsonb_array_elements(v_saved -> 'token_components') with ordinality e(value, ordinality);
    if v_token_components is null or cardinality(v_token_components) = 0 then
        raise exception 'SAVED_GOLD_BUY_TOKEN_COMPONENTS_MISSING';
    end if;
    /*
     * Build buyer notification.
     */
    v_stage := 'validate posting components';
    v_fiat_components := public.validate_components(v_fiat_components);
    v_token_components := public.validate_components(v_token_components);
    if not exists (
        select 1 from unnest(v_fiat_components) c
        where c.component_type = 'principal'::public."ComponentType"
          and c.debit_amount = v_preparation.gross_amount::numeric
    ) or not exists (
        select 1 from unnest(v_token_components) c
        where c.component_type = 'principal'::public."ComponentType"
          and public.round_down(c.debit_amount) = v_preparation.token_quantity::numeric
          and public.round_down(c.credit_amount) = v_preparation.gross_token_quantity::numeric
    ) then
        raise exception 'POSTING_PREPARATION_MISMATCH';
    end if;
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
            null,
        p_blockchain_code => null
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
            null,
        p_blockchain_code => v_blockchain_code
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
      and chain = v_blockchain_code
      and blockchain_code = v_blockchain_code
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
      and blockchain_code = v_blockchain_code
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
$function$;

ALTER FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) TO service_role;

COMMIT;
