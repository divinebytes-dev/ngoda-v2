BEGIN;

DO $preflight$
BEGIN
 IF to_regprocedure('public.complete_verified_gold_buy_recovery(text,text,jsonb,text)') IS NULL
 OR to_regprocedure('public.build_gold_buy_recovery_context(text,text)') IS NULL THEN
  RAISE EXCEPTION 'INSTALL_EXISTING_GOLD_BUY_CONTEXT_RECOVERY_FIRST';
 END IF;
END;
$preflight$;

-- 01_context_storage.sql
ALTER TABLE public.transaction_state
ADD COLUMN IF NOT EXISTS gold_sell_preparation jsonb;

COMMENT ON COLUMN public.transaction_state.gold_sell_preparation IS
'Immutable server-calculated Gold Sell preparation: pricing, components, GL mappings and participants. Never supplied by the client.';

CREATE OR REPLACE FUNCTION public.guard_gold_sell_preparation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.gold_sell_preparation IS NOT NULL THEN
      IF NEW.gold_sell_preparation IS DISTINCT FROM OLD.gold_sell_preparation THEN
        RAISE EXCEPTION 'GOLD_SELL_PREPARATION_IS_IMMUTABLE';
      END IF;
      IF NEW.id IS DISTINCT FROM OLD.id
         OR NEW.reference IS DISTINCT FROM OLD.reference
         OR NEW.created_by IS DISTINCT FROM OLD.created_by
         OR NEW.user_id IS DISTINCT FROM OLD.user_id
         OR NEW.country_code IS DISTINCT FROM OLD.country_code
         OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
         OR NEW.blockchain_code IS DISTINCT FROM OLD.blockchain_code
         OR NEW.transaction_data IS DISTINCT FROM OLD.transaction_data THEN
        RAISE EXCEPTION 'PREPARED_GOLD_SELL_IDENTITY_IS_IMMUTABLE';
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.gold_sell_preparation IS NOT NULL THEN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
      RAISE EXCEPTION USING errcode='42501', message='SERVICE_ROLE_REQUIRED';
    END IF;
    IF NEW.transaction_type IS DISTINCT FROM 'gold_token_sell'::public."TransactionType"
       OR jsonb_typeof(NEW.gold_sell_preparation) IS DISTINCT FROM 'object'
       OR NEW.gold_sell_preparation ->> 'schema_version' IS DISTINCT FROM '1'
       OR NEW.gold_sell_preparation ->> 'transaction_state_id' IS DISTINCT FROM NEW.id
       OR NEW.gold_sell_preparation -> 'transaction_data' IS DISTINCT FROM NEW.transaction_data
       OR NEW.gold_sell_preparation -> 'preparation' ->> 'blockchain_code' IS DISTINCT FROM NEW.blockchain_code
       OR NEW.gold_sell_preparation -> 'preparation' ->> 'seller_id' IS DISTINCT FROM NEW.user_id
       OR NEW.gold_sell_preparation -> 'preparation' ->> 'country_code' IS DISTINCT FROM NEW.country_code THEN
      RAISE EXCEPTION 'INVALID_GOLD_SELL_PREPARATION_SNAPSHOT';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.guard_gold_sell_preparation() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.guard_gold_sell_preparation()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS ngoda_guard_gold_sell_preparation ON public.transaction_state;
CREATE TRIGGER ngoda_guard_gold_sell_preparation
BEFORE INSERT OR UPDATE ON public.transaction_state
FOR EACH ROW EXECUTE FUNCTION public.guard_gold_sell_preparation();

-- Column-level revocation alone cannot override a table-wide UPDATE grant.
-- The trigger above enforces protection even if such a grant exists.
REVOKE UPDATE (gold_sell_preparation) ON public.transaction_state FROM anon, authenticated;
CREATE OR REPLACE FUNCTION public.fetch_gold_sell_execution_context(p_transaction_state_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_context jsonb;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN
  RAISE EXCEPTION USING errcode='42501',message='SERVICE_ROLE_REQUIRED'; END IF;
 SELECT gold_sell_preparation INTO v_context FROM public.transaction_state
 WHERE id=p_transaction_state_id AND transaction_type='gold_token_sell'::public."TransactionType";
 IF v_context IS NULL THEN RAISE EXCEPTION 'GOLD_SELL_PREPARATION_NOT_FOUND'; END IF;
 RETURN v_context;
END;
$function$;
ALTER FUNCTION public.fetch_gold_sell_execution_context(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_gold_sell_execution_context(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fetch_gold_sell_execution_context(text) TO service_role;

-- 02_single_pricing.sql
CREATE OR REPLACE FUNCTION public.calculate_gold_sell_execution_pricing(p_amount numeric, p_country_code text, p_currency_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
    /*
     * ==========================================================
     * NORMALIZED INPUT
     * ==========================================================
     */
    v_currency_key text :=
        lower(
            nullif(
                btrim(
                    p_currency_code
                ),
                ''
            )
        );


    /*
     * ==========================================================
     * CONFIGURATION KEYS
     * ==========================================================
     */
    v_fee_key text :=
        'gold_token_sell';

    v_tax_key text :=
        'gold_token_sell_tax';

    v_spread_key text :=
        'gold_spread_sell';


    /*
     * ==========================================================
     * CONFIGURATION
     * ==========================================================
     */
    v_config record;

    v_fee_config
        public.amount_config := null;

    v_tax_config
        public.amount_config := null;

    v_spread_config
        public.amount_config := null;


    /*
     * ==========================================================
     * PRICING VALUES
     * ==========================================================
     */
    v_gold_market_price numeric := 0;

    v_spread_rate numeric := 0;

    v_sell_price numeric := 0;

    v_quantity numeric := 0;

    v_fiat_base numeric := 0;

    v_fiat_received numeric := 0;

    v_fee_fiat numeric := 0;

    v_fee_gold numeric := 0;

    v_market_fiat numeric := 0;

    v_spread numeric := 0;

    v_tax numeric := 0;


    /*
     * ==========================================================
     * RETURN VALUES
     * ==========================================================
     */
    v_configs jsonb := '[]'::jsonb;
    v_fiat_pricing public.pricing_result;
    v_token_pricing public.pricing_result;
    v_result_fee numeric := 0;

    v_result_tax numeric := 0;

    v_result_spread numeric := 0;

begin
    /*
     * ==========================================================
     * VALIDATE TRANSACTION TYPE
     * ==========================================================
     */
    /*
     * ==========================================================
     * VALIDATE AMOUNT
     * ==========================================================
     */
    if p_amount is null
       or p_amount::text in ('NaN','Infinity','-Infinity')
       or p_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;


    /*
     * ==========================================================
     * VALIDATE INPUT CURRENCY
     * ==========================================================
     */
    if v_currency_key is null or v_currency_key not in ('usd','gold') then
        raise exception
            'CURRENCY_MISSING';
    end if;


    /*
     * ==========================================================
     * FETCH GOLD MARKET PRICE
     * ==========================================================
     */
    v_gold_market_price :=
        public.fetch_gold_price();


    if v_gold_market_price is null
       or v_gold_market_price::text in ('NaN','Infinity','-Infinity')
       or v_gold_market_price <= 0
    then
        raise exception
            'GOLD_MARKET_PRICE_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * FETCH TRANSACTION CONFIGURATION
     * ==========================================================
     */
    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        v_configs := v_configs || jsonb_build_array(to_jsonb(v_config));
        /*
         * TRANSACTION FEE
         */
        if lower(
            v_config.config_key
        ) = v_fee_key
           and lower(
               v_config.currency_code
           ) = v_currency_key
        then
            v_fee_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;


        /*
         * GOVERNMENT TAX
         */
        if lower(
            v_config.config_key
        ) = v_tax_key
           and lower(
               v_config.currency_code
           ) = v_currency_key
        then
            v_tax_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;


        /*
         * GOLD SELL SPREAD
         */
        if lower(
            v_config.config_key
        ) = v_spread_key
           and lower(
               v_config.currency_code
           ) = 'gold'
        then
            v_spread_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;
    end loop;


    /*
     * ==========================================================
     * CALCULATE CUSTOMER SELL PRICE
     * ==========================================================
     */
    v_spread_rate :=
        coalesce(
            v_spread_config.percentage,
            0
        ) / 100;


    v_sell_price :=
        v_gold_market_price *
        (
            1 -
            v_spread_rate
        );


    if v_sell_price <= 0 then
        raise exception
            'INVALID_GOLD_SELL_PRICE';
    end if;


    /*
     * ==========================================================
     * MODE 1: USER ENTERS GOLD
     * ==========================================================
     */
    if v_currency_key = 'gold' then
        v_quantity :=
            p_amount;


        v_fiat_base :=
            v_quantity *
            v_sell_price;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );


        v_fiat_received :=
            v_fiat_base -
            v_fee_fiat;


        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_market_fiat -
            v_fiat_base;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );


    /*
     * ==========================================================
     * MODE 2: USER ENTERS FIAT TO RECEIVE
     * ==========================================================
     */
    else
        v_fiat_received :=
            p_amount;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_fee_config
            );


        v_fiat_base :=
            v_fiat_received +
            v_fee_fiat;


        v_quantity :=
            v_fiat_base /
            v_sell_price;


        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_market_fiat -
            v_fiat_base;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );
    end if;


    /*
     * ==========================================================
     * VALIDATE CALCULATED RESULT
     * ==========================================================
     */
    if v_quantity is null
       or v_quantity <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_QUANTITY';
    end if;


    if v_fiat_base is null
       or v_fiat_base <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_FIAT_BASE';
    end if;


    if v_fiat_received is null
       or v_fiat_received <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_FIAT_RECEIVED';
    end if;


    if v_fee_fiat < 0 then
        raise exception
            'INVALID_GOLD_SELL_FEE';
    end if;


    if v_fee_gold < 0 then
        raise exception
            'INVALID_GOLD_SELL_GOLD_FEE';
    end if;


    if v_spread < 0 then
        raise exception
            'INVALID_GOLD_SELL_SPREAD';
    end if;


    if v_tax < 0 then
        raise exception
            'INVALID_GOLD_SELL_TAX';
    end if;


    /*
     * ==========================================================
     * MAIN GOLD SELL
     * ==========================================================
     */
    v_fiat_pricing := row(
        public.round_down(v_fee_fiat),public.round_down(v_tax),public.round_down(v_spread),0,
        public.round_down(v_quantity),public.round_down(v_fiat_received),public.round_down(v_sell_price)
    )::public.pricing_result;
    v_token_pricing := row(
        public.round_down(v_fee_gold),0,0,0,
        public.round_down(v_quantity),public.round_down(v_fiat_received),public.round_down(v_sell_price)
    )::public.pricing_result;
    return jsonb_build_object('fiat_pricing',to_jsonb(v_fiat_pricing),
        'token_pricing',to_jsonb(v_token_pricing),'market_price',v_gold_market_price::text,
        'sell_price_unrounded',v_sell_price::text,'configs',v_configs);

end;
$function$;

ALTER FUNCTION public.calculate_gold_sell_execution_pricing(numeric,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.calculate_gold_sell_execution_pricing(numeric,text,text) FROM PUBLIC,anon,authenticated,service_role;

-- 03_components_from_context.sql
CREATE OR REPLACE FUNCTION public.build_gold_sell_components_from_pricing(
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
        'gold_token_sell'::public."TransactionType",
        'gold_token_sell_sub_tx'::public."TransactionType"
    ) or p_principal is null or p_principal <= 0
       or p_mappings is null or cardinality(p_mappings) = 0 then
        raise exception 'INVALID_GOLD_SELL_COMPONENT_INPUT';
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

ALTER FUNCTION public.build_gold_sell_components_from_pricing(public."TransactionType",numeric,public.transaction_gl_mapping[],public.pricing_result,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.build_gold_sell_components_from_pricing(public."TransactionType",numeric,public.transaction_gl_mapping[],public.pricing_result,boolean)
FROM PUBLIC, anon, authenticated, service_role;

-- 04_available_balance.sql
CREATE OR REPLACE FUNCTION public.validate_gold_sell_available_balance(
 p_seller_id text,p_country_code text,p_blockchain_code text,p_token_quantity numeric
) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $function$
DECLARE
 v_token_quantity numeric:=p_token_quantity;
 v_blockchain_code text:=p_blockchain_code;
 v_seller_gold_balance numeric;
 v_seller_gold_wallet_active boolean;
 v_total_gold numeric;
 v_locked_gold numeric;
 v_available_gold numeric;
 v_max_sellable_gold numeric;
BEGIN


    /*
     * The required GOLD quantity comes from backend pricing
     * and posting components, for both USD and GOLD input.
     */
    IF v_token_quantity IS NULL
       OR v_token_quantity::text IN (
           'NaN', 'Infinity', '-Infinity'
       )
       OR v_token_quantity <= 0
    THEN
        RAISE EXCEPTION 'INVALID_TOKEN_QUANTITY';
    END IF;

    /*
     * Gold sell uses the selected customer wallet,
     * regardless of the seller's role.
     *
     * This lock lasts for the current database transaction.
     */
    SELECT
        w.balance,
        w.is_active
    INTO
        v_seller_gold_balance,
        v_seller_gold_wallet_active
    FROM public.wallet AS w
    WHERE w.user_id = p_seller_id
      AND w.country_code = lower(btrim(p_country_code))
      AND w.currency_code = 'gold'
      AND w.owner_type =
          'customer'::public."WalletOwnerType"
      AND w.blockchain_code = v_blockchain_code
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SELLER_GOLD_WALLET_NOT_FOUND';
    END IF;

    IF v_seller_gold_wallet_active IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'SELLER_GOLD_WALLET_FROZEN';
    END IF;

    /*
     * Fail closed if any customer GOLD balance is invalid.
     */


    IF EXISTS (
        SELECT 1
        FROM public.wallet AS w
        WHERE w.user_id = p_seller_id
          AND w.country_code = lower(btrim(p_country_code))
          AND w.currency_code = 'gold'
          AND w.owner_type =
              'customer'::public."WalletOwnerType"
          AND (
              w.balance IS NULL
              OR w.balance < 0
              OR w.balance::text IN (
                  'NaN', 'Infinity', '-Infinity'
              )
          )
    ) THEN
        RAISE EXCEPTION 'INVALID_GOLD_BALANCE';
    END IF;

    /*
     * Total customer GOLD across all blockchains.
     */
    SELECT coalesce(sum(w.balance), 0)
    INTO v_total_gold
    FROM public.wallet AS w
    WHERE w.user_id = p_seller_id
      AND w.country_code = lower(btrim(p_country_code))
      AND w.currency_code = 'gold'
      AND w.owner_type =
          'customer'::public."WalletOwnerType";

    /*
     * Total collateral covering all loans.
     * No loanId filter or blockchain allocation.
     */


    IF EXISTS (
        SELECT 1
        FROM public.collateral AS c
        WHERE c.user_id = p_seller_id
          AND c.country_code = lower(btrim(p_country_code))
          AND (
              c.locked_tokens IS NULL
              OR c.locked_tokens < 0
              OR c.locked_tokens::text IN (
                  'NaN', 'Infinity', '-Infinity'
              )
          )
    ) THEN
        RAISE EXCEPTION 'INVALID_LOCKED_GOLD_BALANCE';
    END IF;

    SELECT coalesce(sum(c.locked_tokens), 0)
    INTO v_locked_gold
    FROM public.collateral AS c
    WHERE c.user_id = p_seller_id
      AND c.country_code = lower(btrim(p_country_code));

    /*
     * Maximum sellable GOLD is the lower of:
     * - selected blockchain customer wallet balance;
     * - total customer GOLD less locked collateral.
     */


    v_available_gold :=
        greatest(v_total_gold - v_locked_gold, 0);

    v_max_sellable_gold :=
        least(
            v_seller_gold_balance,
            v_available_gold
        );

    /*
     * Equality is allowed.
     *
     * token_fee_equivalent is not an additional GOLD debit.
     */
    IF v_token_quantity > v_max_sellable_gold THEN
        IF v_token_quantity > v_seller_gold_balance THEN
            RAISE EXCEPTION
                'INSUFFICIENT_BLOCKCHAIN_GOLD_BALANCE';
        ELSE
            RAISE EXCEPTION
                'INSUFFICIENT_UNLOCKED_GOLD_BALANCE';
        END IF;
    END IF;


END;
$function$;

ALTER FUNCTION public.validate_gold_sell_available_balance(text,text,text,numeric) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.validate_gold_sell_available_balance(text,text,text,numeric) FROM PUBLIC,anon,authenticated,service_role;

-- 05_prepare_gold_sell.sql
CREATE OR REPLACE FUNCTION public.prepare_gold_sell(p_seller_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_code text)
 RETURNS TABLE(seller_id text, seller_wallet_address text, seller_wallet_index bigint, treasury_id text, treasury_wallet_address text, country_code text, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, token_fee_equivalent text, gross_amount text, net_amount text, fiat_fee text, trading_spread text, government_tax text, blockchain_code text, sell_mappings transaction_gl_mapping[], sell_components posting_component[], token_mappings transaction_gl_mapping[], token_components posting_component[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_state public.transaction_state%rowtype;
    v_saved jsonb;
    v_quote jsonb;
    v_chain jsonb;
    v_preparation_json jsonb;
    v_token_pricing public.pricing_result;
    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_reference text;
    v_input_currency text;
    v_blockchain_code text;

    v_raw_input_amount numeric;
    v_input_amount numeric;

    v_pricing public.pricing_result;
    v_gold_price numeric := 0;

    v_token_quantity numeric := 0;
    v_token_fee_equivalent numeric := 0;

    v_gross_amount numeric := 0;
    v_net_amount numeric := 0;
    v_fiat_fee numeric := 0;
    v_trading_spread numeric := 0;
    v_government_tax numeric := 0;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_sell_mappings public.transaction_gl_mapping[];
    v_sell_components public.posting_component[];

    v_token_mappings public.transaction_gl_mapping[];
    v_token_components public.posting_component[];

    v_seller_gold_balance numeric;
    v_seller_gold_wallet_active boolean;

    v_total_gold numeric;
    v_locked_gold numeric;
    v_available_gold numeric;
    v_max_sellable_gold numeric;

    v_stage text := 'INITIALIZATION';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'SERVICE_ROLE_VALIDATION';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION 'TRANSACTION_DATA_IS_MISSING';
    END IF;

    IF p_seller_id IS NULL
       OR btrim(p_seller_id) = ''
    THEN
        RAISE EXCEPTION 'SELLER_ID_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION 'COUNTRY_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN
     * ==========================================================
     */
    v_stage := 'BLOCKCHAIN_VALIDATION';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Validate against the active blockchain and its
     * configured active network.
     *
     * Do not call fetch_active_supported_blockchain here,
     * because that RPC requires an authenticated user,
     * while this function is invoked with the service role.
     */
    /*
     * ==========================================================
     * 3. VALIDATE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'TRANSACTION_STATE_VALIDATION';

    SELECT state_record.*
    INTO v_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND lower(btrim(state_record.country_code)) = lower(btrim(p_country_code))
      AND state_record.created_by = p_seller_id
      AND state_record.user_id = p_seller_id
      AND state_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_state.transaction_data IS DISTINCT FROM p_transaction THEN
        RAISE EXCEPTION 'TRANSACTION_DATA_MISMATCH';
    END IF;

    IF lower(btrim(v_state.blockchain_code))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION 'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF p_transaction ->> 'v' IS DISTINCT FROM 'v7' THEN
        RAISE EXCEPTION 'OPERATION_NOT_ALLOWED';
    END IF;

    v_reference :=
        nullif(btrim(p_transaction ->> 'r'), '');

    IF v_reference IS NULL THEN
        RAISE EXCEPTION 'REFERENCE_IS_REQUIRED';
    END IF;

    IF v_state.reference IS DISTINCT FROM v_reference THEN
        RAISE EXCEPTION 'TRANSACTION_REFERENCE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 4. VALIDATE INPUT CURRENCY AND AMOUNT
     * ==========================================================
     */
    v_stage := 'INPUT_VALIDATION';

    v_input_currency :=
        lower(nullif(btrim(p_transaction ->> 'c'), ''));

    IF v_input_currency IS NULL THEN
        RAISE EXCEPTION 'CURRENCY_IS_REQUIRED';
    END IF;

    IF v_input_currency NOT IN ('usd', 'gold') THEN
        RAISE EXCEPTION 'UNSUPPORTED_GOLD_SELL_CURRENCY';
    END IF;

    /*
     * Preserve the existing signed transaction serialization.
     * transaction.a is divided by 100.
     */
    BEGIN
        v_raw_input_amount :=
            (p_transaction ->> 'a')::numeric / 100;
    EXCEPTION
        WHEN invalid_text_representation
          OR numeric_value_out_of_range
        THEN
            RAISE EXCEPTION 'INVALID_AMOUNT';
    END;

    IF v_raw_input_amount IS NULL
       OR v_raw_input_amount::text IN ('NaN','Infinity','-Infinity')
       OR v_raw_input_amount <= 0
    THEN
        RAISE EXCEPTION 'INVALID_AMOUNT';
    END IF;

    v_input_amount := v_raw_input_amount;

    /*
     * ==========================================================
     * 5. CALCULATE GOLD SELL PRICING
     * ==========================================================
     */
    v_saved := v_state.gold_sell_preparation;
    if v_saved is not null then
        if v_saved->>'schema_version' is distinct from '1'
           or v_saved->>'transaction_state_id' is distinct from v_state.id
           or v_saved->'transaction_data' is distinct from p_transaction
           or v_saved->'preparation'->>'seller_id' is distinct from p_seller_id
           or v_saved->'preparation'->>'country_code' is distinct from lower(btrim(p_country_code))
           or v_saved->'preparation'->>'blockchain_code' is distinct from v_blockchain_code then
            raise exception 'INVALID_SAVED_GOLD_SELL_PREPARATION';
        end if;
        v_seller := public.fetch_user_by_id(p_seller_id);
        v_treasury := public.fetch_user_by_id(v_saved->'preparation'->>'treasury_id');
        if v_seller.id is null or v_treasury.id is null
           or v_seller.status is distinct from 'active'::public."UserStatus"
           or v_treasury.status is distinct from 'active'::public."UserStatus"
           or lower(btrim(v_seller.country_code)) is distinct from lower(btrim(p_country_code))
           or lower(btrim(v_treasury.country_code)) is distinct from lower(btrim(p_country_code))
           or lower(v_seller.wallet_address) is distinct from lower(v_saved->'preparation'->>'seller_wallet_address')
           or lower(v_treasury.wallet_address) is distinct from lower(v_saved->'preparation'->>'treasury_wallet_address') then
            raise exception 'GOLD_SELL_SAVED_PARTICIPANT_CHANGED';
        end if;
        perform public.validate_gold_sell_available_balance(p_seller_id,p_country_code,
            v_blockchain_code,(v_saved->'preparation'->>'token_quantity')::numeric);
        return query select saved.* from jsonb_to_record(v_saved->'preparation') as saved(seller_id text, seller_wallet_address text, seller_wallet_index bigint, treasury_id text, treasury_wallet_address text, country_code text, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, token_fee_equivalent text, gross_amount text, net_amount text, fiat_fee text, trading_spread text, government_tax text, blockchain_code text, sell_mappings public.transaction_gl_mapping[], sell_components public.posting_component[], token_mappings public.transaction_gl_mapping[], token_components public.posting_component[]);
        return;
    end if;
    if exists(select 1 from public.blockchain_transaction b where b.reference=v_reference and b.created_by=p_seller_id)
       or exists(select 1 from public.financial_transaction f where f.reference in (v_reference,v_reference||'-01')) then
        raise exception 'GOLD_SELL_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    PERFORM 1
    FROM public.supported_blockchain AS b
    WHERE b.code = v_blockchain_code
      AND b.is_active = true
      AND EXISTS (
          SELECT 1
          FROM public.supported_blockchain_network AS n
          WHERE n.blockchain_id = b.id
            AND n.is_active = true
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;


    v_stage := 'GOLD_SELL_PRICING';

    v_quote := public.calculate_gold_sell_execution_pricing(v_input_amount,p_country_code,v_input_currency);
    v_pricing := jsonb_populate_record(null::public.pricing_result,v_quote->'fiat_pricing');
    v_token_pricing := jsonb_populate_record(null::public.pricing_result,v_quote->'token_pricing');

    v_gold_price :=
        coalesce(v_pricing.gold_price, 0);

    IF v_gold_price <= 0 THEN
        RAISE EXCEPTION 'INVALID_GOLD_PRICE';
    END IF;

    /*
     * ==========================================================
     * 6. FETCH SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'FETCH_SELLER_AND_TREASURY';

    v_seller :=
        public.fetch_user_by_id(p_seller_id);

    v_treasury :=
        public.fetch_country_treasury(p_country_code);

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION 'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION 'TREASURY_NOT_FOUND';
    END IF;

    IF v_seller.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION 'SELLER_NOT_ACTIVE';
    END IF;

    IF v_treasury.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION 'TREASURY_NOT_ACTIVE';
    END IF;

    IF lower(btrim(v_seller.country_code))
       IS DISTINCT FROM lower(btrim(p_country_code))
    THEN
        RAISE EXCEPTION 'SELLER_COUNTRY_MISMATCH';
    END IF;

    IF lower(btrim(v_treasury.country_code))
       IS DISTINCT FROM lower(btrim(p_country_code))
    THEN
        RAISE EXCEPTION 'TREASURY_COUNTRY_MISMATCH';
    END IF;

    IF v_seller.wallet_address IS NULL
       OR btrim(v_seller.wallet_address) = ''
    THEN
        RAISE EXCEPTION 'SELLER_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * Wallet index zero is valid.
     */
    IF v_seller.wallet_index IS NULL THEN
        RAISE EXCEPTION
            'SELLER_WALLET_INDEX_NOT_CONFIGURED';
    END IF;

    IF v_treasury.wallet_address IS NULL
       OR btrim(v_treasury.wallet_address) = ''
    THEN
        RAISE EXCEPTION 'TREASURY_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * ==========================================================
     * 7. FETCH FISCAL PERIOD
     * ==========================================================
     */
    v_stage := 'FETCH_FISCAL_PERIOD';

    SELECT
        fp.fiscal_year,
        fp.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        p_country_code
    ) AS fp;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FISCAL_PERIOD_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 8. FETCH GOLD SELL GL MAPPINGS
     * ==========================================================
     */
    v_stage := 'FETCH_GOLD_SELL_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_sell_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_sell'::public."TransactionType"
    ) AS mapping_record;

    IF v_sell_mappings IS NULL
       OR cardinality(v_sell_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 9. FETCH GOLD SUB-TRANSACTION GL MAPPINGS
     * ==========================================================
     */
    v_stage := 'FETCH_GOLD_SUB_TX_GL_MAPPINGS';

    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_token_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_sell_sub_tx'::public."TransactionType"
    ) AS mapping_record;

    IF v_token_mappings IS NULL
       OR cardinality(v_token_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_SUB_TX_GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 10. BUILD FIAT POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'BUILD_FIAT_COMPONENTS';

    v_sell_components :=
        public.build_gold_sell_components_from_pricing(
            'gold_token_sell'::public."TransactionType",v_pricing.fiat_received,
            v_sell_mappings,v_pricing,false);

    IF v_sell_components IS NULL
       OR cardinality(v_sell_components) = 0
    THEN
        RAISE EXCEPTION 'GOLD_SELL_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 11. BUILD GOLD POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'BUILD_GOLD_COMPONENTS';

    /*
     * Reverse remains true because Gold tokens
     * are treated as assets in the posting calculation.
     */
    v_token_components :=
        public.build_gold_sell_components_from_pricing(
            'gold_token_sell_sub_tx'::public."TransactionType",v_token_pricing.quantity,
            v_token_mappings,v_token_pricing,true);

    IF v_token_components IS NULL
       OR cardinality(v_token_components) = 0
    THEN
        RAISE EXCEPTION
            'GOLD_SELL_TOKEN_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 12. EXTRACT GOLD TOKEN QUANTITY
     * ==========================================================
     */
    v_stage := 'EXTRACT_GOLD_QUANTITY';

    SELECT coalesce(
        component_record.credit_amount,
        0
    )
    INTO v_token_quantity
    FROM unnest(v_token_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'principal'::public."ComponentType"
    LIMIT 1;

    /*
     * Gold precision: six decimal places, rounded down.
     */
    v_token_quantity :=
        trunc(coalesce(v_token_quantity, 0), 6);

    IF v_token_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_TOKEN_QUANTITY';
    END IF;

    /*
     * ==========================================================
     * 13. VALIDATE SELLER GOLD AND UNLOCKED BALANCE
     * ==========================================================
     */
    v_stage := 'VALIDATE_SELLABLE_GOLD';
    perform public.validate_gold_sell_available_balance(p_seller_id,p_country_code,v_blockchain_code,v_token_quantity);

    v_stage := 'EXTRACT_TOKEN_FEE';

    /*
     * This is reporting/calculation data.
     * It is not added to the on-chain transfer quantity.
     */
    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_token_fee_equivalent
    FROM unnest(v_token_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_token_fee_equivalent :=
        trunc(coalesce(v_token_fee_equivalent, 0), 6);

    /*
     * ==========================================================
     * 15. EXTRACT GROSS AND NET FIAT VALUES
     * ==========================================================
     */
    v_stage := 'EXTRACT_GROSS_AND_NET';

    SELECT
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    INTO
        v_gross_amount,
        v_net_amount
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'principal'::public."ComponentType"
    LIMIT 1;

    v_gross_amount := coalesce(v_gross_amount, 0);
    v_net_amount := coalesce(v_net_amount, 0);

    IF v_gross_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_GROSS_AMOUNT';
    END IF;

    IF v_net_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_NET_AMOUNT';
    END IF;

    IF v_net_amount > v_gross_amount THEN
        RAISE EXCEPTION
            'NET_AMOUNT_EXCEEDS_GROSS_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 16. EXTRACT FIAT TRANSACTION FEE
     * ==========================================================
     */
    v_stage := 'EXTRACT_FIAT_FEE';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_fiat_fee
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_fiat_fee := coalesce(v_fiat_fee, 0);

    IF v_fiat_fee < 0 THEN
        RAISE EXCEPTION 'INVALID_FIAT_FEE';
    END IF;

    /*
     * ==========================================================
     * 17. EXTRACT TRADING SPREAD
     * ==========================================================
     */
    v_stage := 'EXTRACT_TRADING_SPREAD';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_trading_spread
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'trading_spread'::public."ComponentType"
    LIMIT 1;

    v_trading_spread :=
        coalesce(v_trading_spread, 0);

    IF v_trading_spread < 0 THEN
        RAISE EXCEPTION 'INVALID_TRADING_SPREAD';
    END IF;

    /*
     * ==========================================================
     * 18. EXTRACT GOVERNMENT TAX
     * ==========================================================
     */
    v_stage := 'EXTRACT_GOVERNMENT_TAX';

    SELECT greatest(
        coalesce(component_record.debit_amount, 0),
        coalesce(component_record.credit_amount, 0)
    )
    INTO v_government_tax
    FROM unnest(v_sell_components) AS component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    WHERE component_record.component_type =
          'government_tax'::public."ComponentType"
    LIMIT 1;

    v_government_tax :=
        coalesce(v_government_tax, 0);

    IF v_government_tax < 0 THEN
        RAISE EXCEPTION 'INVALID_GOVERNMENT_TAX';
    END IF;

    /*
     * ==========================================================
     * 19. VALIDATE POSTING COMPONENTS
     * ==========================================================
     */
    v_stage := 'VALIDATE_POSTING_COMPONENTS';

    v_sell_components :=
        public.validate_components(
            v_sell_components
        );

    v_token_components :=
        public.validate_components(
            v_token_components
        );

    /*
     * ==========================================================
     * 20. FETCH DOCUMENT PREFIX
     * ==========================================================
     */
    v_stage := 'FETCH_DOCUMENT_PREFIX';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_sell'::public."TransactionType"
        );

    IF v_document_prefix IS NULL
       OR btrim(v_document_prefix) = ''
    THEN
        RAISE EXCEPTION 'DOCUMENT_PREFIX_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 21. RETURN TRUSTED PREPARATION
     * ==========================================================
     */
    v_stage := 'RETURN_PREPARATION';

    select jsonb_build_object('code',b.code,'chain_id',n.chain_id::text,
        'rpc_url',n.rpc_url,'explorer_url',n.explorer_url,'contract_address',b.contract_address,
        'native_currency_code',b.native_currency_code,'treasury_wallet_address',v_treasury.wallet_address)
    into v_chain from public.supported_blockchain b
    join lateral (select x.chain_id,x.rpc_url,x.explorer_url from public.supported_blockchain_network x
        where x.blockchain_id=b.id and x.is_active order by x.is_default desc,x.created_at desc,x.id limit 1) n on true
        where b.code=v_blockchain_code and b.is_active;
    if v_chain is null then raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE'; end if;
    v_preparation_json := jsonb_build_object(
        'seller_id', v_seller.id,
        'seller_wallet_address', v_seller.wallet_address,
        'seller_wallet_index', v_seller.wallet_index::bigint,
        'treasury_id', v_treasury.id,
        'treasury_wallet_address', v_treasury.wallet_address,
        'country_code', lower(btrim(p_country_code)),
        'fiscal_year', v_fiscal_year,
        'period', v_period,
        'document_prefix', v_document_prefix,
        'input_amount', v_input_amount::text,
        'input_currency', v_input_currency,
        'gold_price', v_gold_price::text,
        'token_quantity', v_token_quantity::text,
        'token_fee_equivalent', v_token_fee_equivalent::text,
        'gross_amount', v_gross_amount::text,
        'net_amount', v_net_amount::text,
        'fiat_fee', v_fiat_fee::text,
        'trading_spread', v_trading_spread::text,
        'government_tax', v_government_tax::text,
        'blockchain_code', v_blockchain_code,
        'sell_mappings', v_sell_mappings,
        'sell_components', v_sell_components,
        'token_mappings', v_token_mappings,
        'token_components', v_token_components);
    v_saved := jsonb_build_object('schema_version',1,'transaction_state_id',v_state.id,
        'transaction_data',p_transaction,'prepared_at',clock_timestamp(),
        'preparation',v_preparation_json,'pricing',v_quote,'blockchain',v_chain,
        'settlement',jsonb_build_object('fiat_wallet_amount',
            case when v_input_currency='usd' then v_input_amount::text else v_gross_amount::text end));
    update public.transaction_state set gold_sell_preparation=v_saved,updated_at=now()
        where id=v_state.id and gold_sell_preparation is null;
    if not found then raise exception 'GOLD_SELL_CONTEXT_SAVE_FAILED'; end if;

    RETURN QUERY
    SELECT
        v_seller.id,
        v_seller.wallet_address,
        v_seller.wallet_index::bigint,

        v_treasury.id,
        v_treasury.wallet_address,

        lower(btrim(p_country_code)),

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_input_amount::text,
        v_input_currency,
        v_gold_price::text,

        v_token_quantity::text,
        v_token_fee_equivalent::text,

        v_gross_amount::text,
        v_net_amount::text,
        v_fiat_fee::text,
        v_trading_spread::text,
        v_government_tax::text,

        v_blockchain_code,

        v_sell_mappings,
        v_sell_components,

        v_token_mappings,
        v_token_components;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'PREPARE_GOLD_SELL_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the Gold Sell preparation stage reported in the error'
            );
END;
$function$;
ALTER FUNCTION public.prepare_gold_sell(text,jsonb,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prepare_gold_sell(text,jsonb,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_gold_sell(text,jsonb,text,text,text) TO service_role;

-- 06_record_gold_sell.sql
CREATE OR REPLACE FUNCTION public.record_gold_sell_blockchain_transaction(p_seller_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_tx_hash text, p_explorer_url text, p_blockchain_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_state public.transaction_state%rowtype;

    v_preparation record;

    v_blockchain_code text;
    v_reference text;
    v_tx_hash text;
    v_explorer_url text;

    v_blockchain_id text;

    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_network_explorer_url text;

    v_stage text := 'INITIALIZATION';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'SERVICE_ROLE_VALIDATION';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_IS_MISSING';
    END IF;

    IF p_seller_id IS NULL
       OR btrim(p_seller_id) = ''
    THEN
        RAISE EXCEPTION
            'SELLER_ID_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR btrim(p_country_code) = ''
    THEN
        RAISE EXCEPTION
            'COUNTRY_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_stage := 'BLOCKCHAIN_VALIDATION';

    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Confirm the blockchain is active and has
     * an active network.
     *
     * The active network's explorer URL is used
     * to validate the supplied explorer link.
     */
    /*
     * ==========================================================
     * 3. VALIDATE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'TRANSACTION_STATE_VALIDATION';

    SELECT state_record.*
    INTO v_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND lower(btrim(state_record.country_code)) = lower(btrim(p_country_code))
      AND state_record.created_by = p_seller_id
      AND state_record.user_id = p_seller_id
      AND state_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_state.transaction_data
       IS DISTINCT FROM p_transaction
    THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_MISMATCH';
    END IF;

    IF lower(btrim(v_state.blockchain_code))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF p_transaction ->> 'v'
       IS DISTINCT FROM 'v7'
    THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    IF v_state.reference
       IS DISTINCT FROM v_reference
    THEN
        RAISE EXCEPTION
            'TRANSACTION_REFERENCE_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 4. VALIDATE BLOCKCHAIN TRANSACTION HASH
     * ==========================================================
     */
    v_stage := 'TRANSACTION_HASH_VALIDATION';

    v_tx_hash :=
        nullif(
            btrim(p_tx_hash),
            ''
        );

    IF v_tx_hash IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_HASH_REQUIRED';
    END IF;

    IF v_tx_hash !~ '^0x[0-9a-fA-F]{64}$' THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    /*
     * ==========================================================
     * 5. VALIDATE EXPLORER URL
     * ==========================================================
     */
    if v_state.gold_sell_preparation is null then
        raise exception 'GOLD_SELL_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    v_network_explorer_url := v_state.gold_sell_preparation->'blockchain'->>'explorer_url';
    v_stage := 'EXPLORER_URL_VALIDATION';

    v_explorer_url :=
        nullif(
            btrim(p_explorer_url),
            ''
        );

    IF v_explorer_url IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_URL_REQUIRED';
    END IF;

    IF v_network_explorer_url IS NULL
       OR btrim(v_network_explorer_url) = ''
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_NOT_CONFIGURED';
    END IF;

    /*
     * Ensure the explorer URL belongs to the
     * selected blockchain network.
     */
    IF v_explorer_url IS DISTINCT FROM
       (
           rtrim(
               btrim(v_network_explorer_url),
               '/'
           ) || '/tx/' || v_tx_hash
       )
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_EXPLORER_URL_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 6. PREPARE GOLD SELL
     * ==========================================================
     */
    v_stage := 'PREPARE_GOLD_SELL';

    SELECT preparation.*
    INTO v_preparation
    FROM public.prepare_gold_sell(
        p_seller_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'GOLD_SELL_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'PREPARATION_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 7. VALIDATE SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'VALIDATE_SELLER_AND_TREASURY';

    v_seller :=
        public.fetch_user_by_id(
            p_seller_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION
            'TREASURY_NOT_FOUND';
    END IF;

    IF lower(btrim(v_seller.wallet_address))
       IS DISTINCT FROM
       lower(btrim(v_preparation.seller_wallet_address))
    THEN
        RAISE EXCEPTION
            'SELLER_WALLET_ADDRESS_MISMATCH';
    END IF;

    IF lower(btrim(v_treasury.wallet_address))
       IS DISTINCT FROM
       lower(btrim(v_preparation.treasury_wallet_address))
    THEN
        RAISE EXCEPTION
            'TREASURY_WALLET_ADDRESS_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 8. VALIDATE PREPARED VALUES
     * ==========================================================
     */
    v_stage := 'VALIDATE_PREPARED_VALUES';

    IF v_preparation.token_quantity::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_TOKEN_QUANTITY';
    END IF;

    IF v_preparation.gross_amount::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GROSS_AMOUNT';
    END IF;

    IF v_preparation.net_amount::numeric <= 0 THEN
        RAISE EXCEPTION
            'INVALID_NET_AMOUNT';
    END IF;

    IF v_preparation.token_fee_equivalent::numeric < 0 THEN
        RAISE EXCEPTION
            'INVALID_TOKEN_FEE';
    END IF;

    /*
     * ==========================================================
     * 9. RECORD BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    -- A lost database response may cause the submission callback to retry.
    -- Return only an exactly matching record; never accept another operation.
    select b.id::text into v_blockchain_id from public.blockchain_transaction b
    where lower(b.tx_hash)=lower(v_tx_hash) and b.reference=v_reference
      and b.created_by=p_seller_id and b.transaction_type='gold_token_sell'::public."TransactionType"
      and b.country_code=lower(btrim(p_country_code)) and b.chain=v_blockchain_code
      and b.blockchain_code=v_blockchain_code and b.document_number is null
      and b.status='pending'::public."BlockchainTxStatus"
      and lower(b.sender)=lower(v_preparation.seller_wallet_address)
      and lower(b.receiver)=lower(v_preparation.treasury_wallet_address)
      and b.quantity=v_preparation.token_quantity::numeric
      and b.gross_amount=v_preparation.gross_amount::numeric
      and b.net_amount=v_preparation.net_amount::numeric
      and b.fee_amount=v_preparation.token_fee_equivalent::numeric
      and b.currency_code=v_preparation.input_currency;
    if v_blockchain_id is not null then return v_blockchain_id; end if;
    if exists(select 1 from public.blockchain_transaction b
              where lower(b.tx_hash)=lower(v_tx_hash)
                 or (b.reference=v_reference and b.created_by=p_seller_id)) then
        raise exception 'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED_OR_MISMATCHED';
    end if;
    v_stage := 'INSERT_BLOCKCHAIN_TRANSACTION';

    BEGIN
        INSERT INTO public.blockchain_transaction (
            tx_hash,
            fiscal_year,
            period,
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
            country_code,
            reference,
            description
        )
        VALUES (
            v_tx_hash,
            v_preparation.fiscal_year,
            v_preparation.period,
            'gold_token_sell'::public."TransactionType",
            v_blockchain_code,
            v_blockchain_code,
            v_preparation.seller_wallet_address,
            v_preparation.treasury_wallet_address,
            v_preparation.token_quantity::numeric,
            v_preparation.gross_amount::numeric,
            v_preparation.net_amount::numeric,
            v_preparation.token_fee_equivalent::numeric,
            v_preparation.input_currency,
            v_explorer_url,
            'pending',
            p_seller_id,
            lower(btrim(p_country_code)),
            v_reference,
            'Gold token sell on ' || v_blockchain_code
        )
        RETURNING id::text
        INTO v_blockchain_id;

    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION USING
                ERRCODE = '23505',
                MESSAGE = 'BLOCKCHAIN_TRANSACTION_ALREADY_RECORDED';
    END;

    /*
     * ==========================================================
     * 10. VALIDATE INSERT RESULT
     * ==========================================================
     */
    v_stage := 'VALIDATE_INSERT_RESULT';

    IF v_blockchain_id IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    END IF;

    RETURN v_blockchain_id;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'RECORD_GOLD_SELL_BLOCKCHAIN_TRANSACTION_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the blockchain transaction recording stage reported in the error'
            );
END;
$function$;
ALTER FUNCTION public.record_gold_sell_blockchain_transaction(text,jsonb,text,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_gold_sell_blockchain_transaction(text,jsonb,text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_gold_sell_blockchain_transaction(text,jsonb,text,text,text,text,text) TO service_role;

-- 07_complete_gold_sell.sql
CREATE OR REPLACE FUNCTION public.complete_gold_sell(p_seller_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_transaction_id text, p_blockchain_code text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, token_document_number text, quantity text, gross_amount text, net_amount text, fee text, explorer_url text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_preparation record;
    v_saved jsonb;

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
    v_blockchain_code text;

    /*
     * Actual fiat amount moved between wallets.
     *
     * Fiat input:
     * The entered USD amount is the exact amount received.
     *
     * Gold input:
     * Use the debit side of the main sell principal.
     *
     * This preserves the existing settlement rules.
     */
    v_fiat_wallet_amount numeric;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'service role validation';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_stage := 'validate blockchain code';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 3. PREPARE GOLD SELL
     * ==========================================================
     *
     * The preparation function validates:
     * - Processing transaction state
     * - Selected blockchain
     * - Seller and treasury
     * - Gold wallet balance on selected blockchain
     * - Pricing
     * - GL mappings
     * - Posting components
     */
    select s.gold_sell_preparation into v_saved from public.transaction_state s
        where s.id=p_transaction_state_id and s.created_by=p_seller_id for update;
    if v_saved is null then
        raise exception 'GOLD_SELL_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    v_stage := 'prepare gold sell';

    SELECT preparation_record.*
    INTO v_preparation
    FROM public.prepare_gold_sell(
        p_seller_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'GOLD_SELL_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'PREPARATION_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * Validate the exact customer sell price returned
     * by the preparation function.
     *
     * Do not fetch the market price again here.
     */
    v_stage := 'validate gold price';

    IF coalesce(
        v_preparation.gold_price::numeric,
        0
    ) <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GOLD_PRICE';
    END IF;

    /*
     * ==========================================================
     * 4. DETERMINE FIAT WALLET SETTLEMENT AMOUNT
     * ==========================================================
     */
    v_stage := 'resolve fiat wallet amount';

    IF lower(btrim(v_preparation.input_currency)) <> 'gold' THEN

        /*
         * FIAT INPUT
         *
         * The customer receives exactly the entered
         * USD amount.
         */
        v_fiat_wallet_amount :=
            v_preparation.input_amount::numeric;

    ELSE

        /*
         * GOLD INPUT
         *
         * Use the debit side of the main principal
         * component, preserving the existing logic.
         */
        SELECT
            component_record.debit_amount
        INTO
            v_fiat_wallet_amount
        FROM unnest(
            v_preparation.sell_components
        ) AS component_record
        WHERE component_record.component_type =
              'principal'::public."ComponentType"
        LIMIT 1;

        IF v_fiat_wallet_amount IS NULL THEN
            RAISE EXCEPTION
                'GOLD_SELL_PRINCIPAL_COMPONENT_NOT_FOUND';
        END IF;

    END IF;

    IF v_fiat_wallet_amount IS NULL
       OR v_fiat_wallet_amount <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_FIAT_WALLET_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 5. VALIDATE TRANSACTION REFERENCE
     * ==========================================================
     */
    v_stage := 'validate transaction reference';

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 6. LOCK PENDING BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'lock blockchain transaction';

    SELECT blockchain_record.*
    INTO v_blockchain_transaction
    FROM public.blockchain_transaction AS blockchain_record
    WHERE blockchain_record.id::text =
          p_blockchain_transaction_id
      AND blockchain_record.created_by =
          p_seller_id
      AND blockchain_record.reference =
          v_reference
      AND blockchain_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
      AND blockchain_record.chain =
          v_blockchain_code
      AND blockchain_record.blockchain_code = v_blockchain_code
      AND blockchain_record.document_number IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION';
    END IF;

    /*
     * ==========================================================
     * 7. VALIDATE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'validate blockchain transaction';

    IF lower(v_blockchain_transaction.sender)
       IS DISTINCT FROM
       lower(v_preparation.seller_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_SELLER_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.receiver)
       IS DISTINCT FROM
       lower(v_preparation.treasury_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TREASURY_MISMATCH';
    END IF;

    IF v_blockchain_transaction.quantity
       IS DISTINCT FROM
       v_preparation.token_quantity::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.gross_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.gross_amount::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_GROSS_AMOUNT_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.net_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.net_amount::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NET_AMOUNT_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.fee_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.token_fee_equivalent::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_FEE_AMOUNT_MISMATCH';
    END IF;

    IF lower(
        btrim(v_blockchain_transaction.country_code)
    ) IS DISTINCT FROM
       lower(btrim(v_preparation.country_code))
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_COUNTRY_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 8. FETCH SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'fetch seller and treasury';

    v_seller :=
        public.fetch_user_by_id(
            v_preparation.seller_id
        );

    v_treasury :=
        public.fetch_user_by_id(
            v_preparation.treasury_id
        );

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION
            'TREASURY_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 9. CREATE SELLER NOTIFICATION
     * ==========================================================
     *
     * The seller receives the USD wallet settlement.
     */
    v_stage := 'create seller notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_sell'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_fiat_wallet_amount,
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

    /*
     * ==========================================================
     * 10. FETCH DEVICE TOKENS
     * ==========================================================
     */
    v_stage := 'fetch seller device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_seller.id
            ),
            array[]::text[]
        );

    /*
     * ==========================================================
     * 11. GENERATE DOCUMENT NUMBERS
     * ==========================================================
     */
    v_stage := 'generate main document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    IF v_document_number IS NULL
       OR btrim(v_document_number) = ''
    THEN
        RAISE EXCEPTION
            'DOCUMENT_NUMBER_GENERATION_FAILED';
    END IF;

    v_token_document_number :=
        v_document_number || '-01';

    /*
     * ==========================================================
     * 12. INSERT FIAT FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage := 'insert fiat financial transaction';

    INSERT INTO public.financial_transaction (
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
    VALUES (
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
        'g Gold tokens at USD ' ||
        v_preparation.gold_price ||
        '/g',

        v_seller.id,
        v_preparation.gross_amount::numeric,
        'usd',
        v_preparation.country_code
    )
    RETURNING id
    INTO v_financial_transaction_id;

    /*
     * ==========================================================
     * 13. POST FIAT GL ENTRIES
     * ==========================================================
     */
    v_stage := 'post fiat financial entries';

    PERFORM *
    FROM public.post_financial_entries(
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
     * ==========================================================
     * 14. POST USD WALLET ENTRIES
     * ==========================================================
     *
     * Treasury USD wallet:
     *     Debit
     *
     * Seller customer USD wallet:
     *     Credit
     *
     * USD wallets are not blockchain-specific.
     * p_blockchain_code must remain NULL.
     */
    v_stage := 'post fiat wallet entries';

    SELECT wallet_result.receiver_notification_id
    INTO v_receiver_notification_id
    FROM public.post_wallet_entries(
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
            v_fiat_wallet_amount,

        p_debit_amount =>
            v_fiat_wallet_amount,

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
            null,

        p_blockchain_code =>
            null
    ) AS wallet_result;

    /*
     * ==========================================================
     * 15. INSERT GOLD FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage := 'insert token financial transaction';

    INSERT INTO public.financial_transaction (
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
    VALUES (
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
        'g Gold tokens to treasury on ' ||
        v_blockchain_code,

        v_seller.id,
        v_preparation.token_quantity::numeric,
        'gold',
        v_preparation.country_code
    )
    RETURNING id
    INTO v_token_financial_transaction_id;

    /*
     * ==========================================================
     * 16. POST GOLD GL ENTRIES
     * ==========================================================
     */
    v_stage := 'post token financial entries';

    PERFORM *
    FROM public.post_financial_entries(
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
     * ==========================================================
     * 17. POST BLOCKCHAIN-SPECIFIC GOLD WALLET ENTRIES
     * ==========================================================
     *
     * Seller customer Gold wallet:
     *     Debit token_quantity
     *
     * Treasury Gold wallet:
     *     Credit token_quantity
     *
     * Both wallets belong to the selected blockchain.
     *
     * No additional Gold fee is transferred.
     */
    v_stage := 'post token wallet entries';

    PERFORM *
    FROM public.post_wallet_entries(
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
            null,

        p_blockchain_code =>
            v_blockchain_code
    );

    /*
     * ==========================================================
     * 18. COMPLETE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'complete blockchain transaction';

    UPDATE public.blockchain_transaction
    SET
        document_number =
            v_token_document_number,

        status =
            'completed'::public."BlockchainTxStatus"

    WHERE id::text =
          p_blockchain_transaction_id
      AND chain =
          v_blockchain_code
      AND blockchain_code = v_blockchain_code
      AND status =
          'pending'::public."BlockchainTxStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * 19. COMPLETE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'complete transaction state';

    UPDATE public.transaction_state
    SET
        user_id =
            v_seller.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()

    WHERE id =
          p_transaction_state_id
      AND created_by =
          p_seller_id
      AND transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND blockchain_code =
          v_blockchain_code
      AND status =
          'processing'::public."TransactionStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'TRANSACTION_STATE_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * 20. RETURN COMPLETION RESULT
     * ==========================================================
     *
     * Financial gross and net values remain unchanged.
     * Fiat wallet settlement is calculated separately.
     */
    v_stage := 'return gold sell result';

    RETURN QUERY
    SELECT
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

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state =
                RETURNED_SQLSTATE,

            v_error_message =
                MESSAGE_TEXT,

            v_error_detail =
                PG_EXCEPTION_DETAIL,

            v_error_hint =
                PG_EXCEPTION_HINT,

            v_error_context =
                PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE =
                v_error_state,

            MESSAGE =
                format(
                    'GOLD_SELL_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            DETAIL =
                coalesce(
                    nullif(
                        concat_ws(
                            E'\n',
                            nullif(v_error_detail, ''),
                            nullif(v_error_context, '')
                        ),
                        ''
                    ),
                    'No additional PostgreSQL context'
                ),

            HINT =
                coalesce(
                    nullif(v_error_hint, ''),
                    'Check the Gold Sell stage reported in the error'
                );
END;
$function$;
ALTER FUNCTION public.complete_gold_sell(text,jsonb,text,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_gold_sell(text,jsonb,text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_gold_sell(text,jsonb,text,text,text,text,text) TO service_role;

-- 08_gold_sell_recovery.sql
CREATE OR REPLACE FUNCTION public.build_gold_sell_recovery_context(
 p_executor_id text,p_blockchain_transaction_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO '' AS $function$
DECLARE
 v_executor public.users%rowtype;
 v_b public.blockchain_transaction%rowtype;
 v_s public.transaction_state%rowtype;
 v_saved jsonb;
 v_chain jsonb;
 v_network record;
BEGIN
 SELECT * INTO v_executor FROM public.users WHERE id=p_executor_id AND status='active'::public."UserStatus";
 IF NOT FOUND OR NOT public.user_has_role(p_executor_id,ARRAY['treasury'::public."Role"]::public."Role"[]) THEN
  RAISE EXCEPTION USING errcode='42501',message='ACTIVE_TREASURY_USER_REQUIRED'; END IF;
 SELECT * INTO v_b FROM public.blockchain_transaction WHERE id::text=p_blockchain_transaction_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCKCHAIN_TRANSACTION_NOT_FOUND'; END IF;
 IF v_b.country_code IS DISTINCT FROM v_executor.country_code THEN
  RAISE EXCEPTION USING errcode='42501',message='BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH'; END IF;
 IF v_b.transaction_type IS DISTINCT FROM 'gold_token_sell'::public."TransactionType"
 OR v_b.status IS DISTINCT FROM 'pending'::public."BlockchainTxStatus" OR v_b.document_number IS NOT NULL THEN
  RAISE EXCEPTION 'PENDING_GOLD_SELL_REQUIRED'; END IF;
 IF v_b.tx_hash IS NULL OR v_b.tx_hash !~ '^0x[0-9a-fA-F]{64}$' THEN RAISE EXCEPTION 'VALID_TRANSACTION_HASH_REQUIRED'; END IF;
 SELECT * INTO v_s FROM public.transaction_state WHERE reference=v_b.reference AND created_by=v_b.created_by;
 IF NOT FOUND OR v_s.user_id IS DISTINCT FROM v_b.created_by
 OR v_s.country_code IS DISTINCT FROM v_b.country_code OR v_s.transaction_type IS DISTINCT FROM v_b.transaction_type
 OR v_s.status IS DISTINCT FROM 'processing'::public."TransactionStatus" THEN RAISE EXCEPTION 'INVALID_TRANSACTION_STATE'; END IF;
 v_saved:=v_s.gold_sell_preparation;
 IF v_saved IS NULL THEN RAISE EXCEPTION 'GOLD_SELL_PREPARATION_MISSING_RECONCILIATION_REQUIRED'; END IF;
 v_chain:=v_saved->'blockchain';
 IF jsonb_typeof(v_chain) IS DISTINCT FROM 'object'
 OR v_chain->>'code' IS DISTINCT FROM v_s.blockchain_code
 OR v_s.blockchain_code IS DISTINCT FROM v_b.blockchain_code
 OR v_s.blockchain_code IS DISTINCT FROM v_b.chain::text
 OR v_saved->'preparation'->>'blockchain_code' IS DISTINCT FROM v_s.blockchain_code THEN
  RAISE EXCEPTION 'SAVED_GOLD_SELL_BLOCKCHAIN_MISMATCH'; END IF;
 -- A submitted transaction remains recoverable on its original network even
 -- after it is disabled or its current contract address is changed.
 SELECT n.rpc_url INTO v_network FROM public.supported_blockchain b
 JOIN public.supported_blockchain_network n ON n.blockchain_id=b.id
 WHERE b.code=v_s.blockchain_code AND n.chain_id=(v_chain->>'chain_id')::bigint;
 IF NOT FOUND THEN RAISE EXCEPTION 'SAVED_GOLD_SELL_NETWORK_NOT_FOUND'; END IF;
 RETURN jsonb_build_object('transaction_type',v_b.transaction_type,
 'blockchain_transaction_id',v_b.id::text,'transaction_state_id',v_s.id,
 'user_id',v_s.user_id,'country_code',v_s.country_code,'reference',v_s.reference,
 'transaction_data',v_s.transaction_data,'snapshot',v_saved,'tx_hash',v_b.tx_hash,
 'sender',v_b.sender,'receiver',v_b.receiver,'quantity',v_b.quantity::text,
 'fee_amount',v_b.fee_amount::text,'gross_amount',v_b.gross_amount::text,
 'net_amount',v_b.net_amount::text,'currency_code',v_b.currency_code,
 'blockchain_code',v_s.blockchain_code,'chain_id',v_chain->>'chain_id',
 'contract_address',v_chain->>'contract_address','rpc_url',v_network.rpc_url);
END;
$function$;
ALTER FUNCTION public.build_gold_sell_recovery_context(text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.build_gold_sell_recovery_context(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.complete_verified_gold_sell_recovery(
 p_executor_id text,p_blockchain_transaction_id text,p_verified_context jsonb,p_ip_address text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_context jsonb;v_id text;v_result jsonb;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN RAISE EXCEPTION USING errcode='42501',message='SERVICE_ROLE_REQUIRED'; END IF;
 SELECT s.id INTO v_id FROM public.transaction_state s JOIN public.blockchain_transaction b
 ON b.reference=s.reference AND b.created_by=s.created_by WHERE b.id::text=p_blockchain_transaction_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'TRANSACTION_STATE_NOT_FOUND'; END IF;
 PERFORM 1 FROM public.transaction_state WHERE id=v_id FOR UPDATE;
 PERFORM 1 FROM public.blockchain_transaction WHERE id::text=p_blockchain_transaction_id FOR UPDATE;
 v_context:=public.build_gold_sell_recovery_context(p_executor_id,p_blockchain_transaction_id);
 IF v_context IS DISTINCT FROM p_verified_context THEN RAISE EXCEPTION 'RECOVERY_CONTEXT_CHANGED_RETRY_REQUIRED'; END IF;
 SELECT to_jsonb(r) INTO v_result FROM public.complete_gold_sell(
 p_seller_id=>v_context->>'user_id',p_transaction=>v_context->'transaction_data',
 p_country_code=>v_context->>'country_code',p_transaction_state_id=>v_id,
 p_blockchain_transaction_id=>p_blockchain_transaction_id,p_blockchain_code=>v_context->>'blockchain_code',
 p_ip_address=>p_ip_address) r;
 RETURN v_result;
END;
$function$;
ALTER FUNCTION public.complete_verified_gold_sell_recovery(text,text,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_verified_gold_sell_recovery(text,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_verified_gold_sell_recovery(text,text,jsonb,text) TO service_role;

-- General recovery entry point: routing only. Each trade owns its context.
CREATE OR REPLACE FUNCTION public.fetch_my_blockchain_recovery_context(p_blockchain_transaction_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_executor public.users%rowtype;
 v_transaction public.blockchain_transaction%rowtype;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION USING errcode='42501',message='UNAUTHORIZED'; END IF;
 IF nullif(btrim(p_blockchain_transaction_id),'') IS NULL THEN
  RAISE EXCEPTION 'BLOCKCHAIN_TRANSACTION_ID_REQUIRED'; END IF;
 SELECT * INTO v_executor FROM public.users
 WHERE id=auth.uid()::text AND status='active'::public."UserStatus";
 IF NOT FOUND OR NOT public.user_has_role(auth.uid()::text,ARRAY['treasury'::public."Role"]::public."Role"[]) THEN
  RAISE EXCEPTION USING errcode='42501',message='ACTIVE_TREASURY_USER_REQUIRED'; END IF;
 SELECT * INTO v_transaction FROM public.blockchain_transaction
 WHERE id::text=btrim(p_blockchain_transaction_id);
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCKCHAIN_TRANSACTION_NOT_FOUND'; END IF;
 IF v_transaction.country_code IS DISTINCT FROM v_executor.country_code THEN
  RAISE EXCEPTION USING errcode='42501',message='BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH'; END IF;
 CASE v_transaction.transaction_type
 WHEN 'gold_token_buy'::public."TransactionType" THEN
  RETURN public.build_gold_buy_recovery_context(v_executor.id,btrim(p_blockchain_transaction_id));
 WHEN 'gold_token_sell'::public."TransactionType" THEN
  RETURN public.build_gold_sell_recovery_context(v_executor.id,btrim(p_blockchain_transaction_id));
 ELSE
  -- Other transaction types continue through their existing processor.
  RETURN jsonb_build_object('transaction_type',v_transaction.transaction_type);
 END CASE;
END;
$function$;
ALTER FUNCTION public.fetch_my_blockchain_recovery_context(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_my_blockchain_recovery_context(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_blockchain_recovery_context(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.process_my_incomplete_blockchain_transaction(p_blockchain_transaction_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_executor public.users%rowtype;
    v_initiating_user public.users%rowtype;
    v_receiving_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_transaction_type
        public."TransactionType";

    v_sub_transaction_type
        public."TransactionType";

    v_mappings
        public.transaction_gl_mapping[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_token_components
        public.posting_component[];

    v_token_principal_component
        public.posting_component;

    v_fiat_principal_component
        public.posting_component;

    v_receiver_notification
        public.notification_message;

    v_is_transfer boolean := false;

    v_principal numeric;
    v_quantity numeric;
    v_gross_token_quantity numeric;
    v_gross_amount numeric := 0;
    v_fee numeric := 0;

    v_currency_code text;
    v_reference text;

    v_fiat_sender_id text;
    v_fiat_receiver_id text;

    v_token_sender_id text;
    v_token_receiver_id text;

    v_notification_sender text;
    v_notification_receiver text;

    v_document_prefix text;
    v_document_number text;
    v_token_document_number text;
    v_token_reference text;

    v_financial_transaction_id bigint;
    v_token_financial_transaction_id bigint;

    v_receiver_notification_id text;

    v_device_tokens text[] :=
        array[]::text[];

    v_result jsonb;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    if nullif(
        btrim(p_blockchain_transaction_id),
        ''
    ) is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ID_REQUIRED';
    end if;

    /*
     * Fetch treasury operator.
     */
    v_stage :=
        'fetch treasury operator';

    v_executor :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_executor.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if v_executor.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Lock incomplete blockchain transaction.
     */
    v_stage :=
        'lock blockchain transaction';

    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          btrim(
              p_blockchain_transaction_id
          )

      and blockchain_record.document_number is null

      and (
          blockchain_record.status is null
          or blockchain_record.status <>
             'completed'::public."BlockchainTxStatus"
      )
    for update;

    if not found then
        raise exception
            'TRANSACTION_NOT_FOUND_OR_ALREADY_COMPLETED';
    end if;

    if v_blockchain_transaction.country_code is distinct from
       v_executor.country_code
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH';
    end if;

    if v_blockchain_transaction.created_by is null then
        raise exception
            'TRANSACTION_CREATED_BY_NOT_FOUND';
    end if;

    v_transaction_type :=
        v_blockchain_transaction.transaction_type;

    -- Buy and Sell each require their own saved preparation and verified recovery.
    -- Block the old live-pricing path even when this RPC is called directly.
    if v_transaction_type in ('gold_token_buy'::public."TransactionType",'gold_token_sell'::public."TransactionType") then
        raise exception 'USE_VERIFIED_TOKEN_TRADE_RECOVERY';
    end if;

    /*
     * Mint and burn use their existing accounting completion
     * function.
     */
    if v_transaction_type in (
        'gold_token_mint'::public."TransactionType",
        'gold_token_burn'::public."TransactionType"
    )
    then
        v_stage :=
            'complete token adjustment';

        if nullif(
            btrim(
                v_blockchain_transaction.reference
            ),
            ''
        ) is null
        then
            raise exception
                'ADJUSTMENT_REQUEST_REFERENCE_NOT_FOUND';
        end if;

        return public.complete_my_token_adjustment_execution(
            v_blockchain_transaction.reference,
            v_blockchain_transaction.id::text,
            p_ip_address
        );
    end if;

    /*
     * Validate supported Gold transaction.
     */
    if v_transaction_type not in (
        'gold_token_buy'::public."TransactionType",
        'gold_token_sell'::public."TransactionType",
        'gold_token_transfer'::public."TransactionType"
    )
    then
        raise exception
            'UNSUPPORTED_BLOCKCHAIN_TRANSACTION_TYPE';
    end if;

    v_is_transfer :=
        v_transaction_type =
        'gold_token_transfer'::public."TransactionType";

    /*
     * Resolve currency and reference.
     */
    v_currency_code :=
        lower(
            nullif(
                btrim(
                    v_blockchain_transaction.currency_code
                ),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_CURRENCY_NOT_FOUND';
    end if;

    v_reference :=
        coalesce(
            nullif(
                btrim(
                    v_blockchain_transaction.reference
                ),
                ''
            ),
            v_blockchain_transaction.tx_hash
        );

    if nullif(
        btrim(v_reference),
        ''
    ) is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_REFERENCE_NOT_FOUND';
    end if;

    /*
     * Resolve original principal.
     */
    if v_is_transfer then
        v_principal :=
            v_blockchain_transaction.quantity;
    else
        v_principal :=
            v_blockchain_transaction.gross_amount;
    end if;

    if v_principal is null
       or v_principal <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Resolve token sub-transaction.
     */
    v_sub_transaction_type :=
        case v_transaction_type
            when 'gold_token_buy'::public."TransactionType"
            then
                'gold_token_buy_sub_tx'::public."TransactionType"

            when 'gold_token_sell'::public."TransactionType"
            then
                'gold_token_sell_sub_tx'::public."TransactionType"

            when 'gold_token_transfer'::public."TransactionType"
            then
                'gold_token_transfer'::public."TransactionType"
        end;

    /*
     * Fetch initiating user.
     */
    v_stage :=
        'fetch initiating user';

    v_initiating_user :=
        public.fetch_user_by_id(
            v_blockchain_transaction.created_by
        );

    if v_initiating_user.id is null then
        raise exception
            'INITIATING_USER_NOT_FOUND';
    end if;

    if v_initiating_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'INITIATING_USER_NOT_ACTIVE';
    end if;

    /*
     * Fetch country treasury.
     */
    v_stage :=
        'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_blockchain_transaction.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    /*
     * Resolve transfer receiver using blockchain address.
     */
    if v_is_transfer then
        v_stage :=
            'fetch transfer receiver';

        select user_record.*
        into v_receiving_user
        from public.users
            user_record
        where lower(
            user_record.wallet_address
        ) =
            lower(
                v_blockchain_transaction.receiver
            )

          and user_record.country_code =
              v_blockchain_transaction.country_code
        limit 1;

        if not found then
            raise exception
                'RECEIVER_NOT_FOUND';
        end if;

        if v_receiving_user.status <>
           'active'::public."UserStatus"
        then
            raise exception
                'RECEIVER_NOT_ACTIVE';
        end if;

        if v_receiving_user.id =
           v_initiating_user.id
        then
            raise exception
                'OPERATION_NOT_ALLOWED';
        end if;
    end if;

    /*
     * Resolve transaction parties.
     */
    if v_transaction_type =
       'gold_token_buy'::public."TransactionType"
    then
        v_fiat_sender_id :=
            v_initiating_user.id;

        v_fiat_receiver_id :=
            v_treasury.id;

        v_token_sender_id :=
            v_treasury.id;

        v_token_receiver_id :=
            v_initiating_user.id;

        v_notification_sender :=
            coalesce(
                v_treasury.email,
                v_treasury.id
            );

        v_notification_receiver :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

    elsif v_transaction_type =
          'gold_token_sell'::public."TransactionType"
    then
        v_fiat_sender_id :=
            v_treasury.id;

        v_fiat_receiver_id :=
            v_initiating_user.id;

        v_token_sender_id :=
            v_initiating_user.id;

        v_token_receiver_id :=
            v_treasury.id;

        v_notification_sender :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

        v_notification_receiver :=
            coalesce(
                v_treasury.email,
                v_treasury.id
            );

    else
        v_token_sender_id :=
            v_initiating_user.id;

        v_token_receiver_id :=
            v_receiving_user.id;

        v_notification_sender :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

        v_notification_receiver :=
            coalesce(
                v_receiving_user.email,
                v_receiving_user.phone,
                v_receiving_user.id
            );
    end if;

    /*
     * Fetch wallet-owner configuration.
     */
    v_stage :=
        'fetch wallet-owner configuration';

    v_wallet_owners :=
        public.fetch_transaction_type_wallet_owner(
            v_transaction_type
        );

    /*
     * Fetch document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );

    if nullif(
        btrim(v_document_prefix),
        ''
    ) is null
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Build fiat components for buy/sell.
     */
    if not v_is_transfer then
        v_stage :=
            'fetch fiat GL mappings';

        select array_agg(mapping_record)
        into v_mappings
        from public.fetch_gl_mappings(
            v_transaction_type
        ) as mapping_record;

        if v_mappings is null
           or cardinality(v_mappings) = 0
        then
            raise exception
                'GL_MAPPINGS_NOT_FOUND';
        end if;

        v_stage :=
            'build fiat posting components';

        v_components :=
            public.build_posting_components(
                v_transaction_type,
                v_principal,
                v_mappings,
                v_blockchain_transaction.country_code,
                v_currency_code,
                false
            );

        if v_components is null
           or cardinality(v_components) = 0
        then
            raise exception
                'POSTING_COMPONENTS_NOT_FOUND';
        end if;
    else
        v_mappings :=
            array[]::public.transaction_gl_mapping[];

        v_components :=
            array[]::public.posting_component[];
    end if;

    /*
     * Build token components.
     */
    v_stage :=
        'fetch token GL mappings';

    select array_agg(mapping_record)
    into v_token_mappings
    from public.fetch_gl_mappings(
        v_sub_transaction_type
    ) as mapping_record;

    if v_token_mappings is null
       or cardinality(v_token_mappings) = 0
    then
        raise exception
            'TOKEN_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage :=
        'build token posting components';

    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_principal,
            v_token_mappings,
            v_blockchain_transaction.country_code,
            v_currency_code,
            true
        );

    if v_token_components is null
       or cardinality(v_token_components) = 0
    then
        raise exception
            'TOKEN_POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Extract token principal.
     */
    v_stage :=
        'extract token principal component';

    select component_record.*
    into v_token_principal_component
    from unnest(
        v_token_components
    ) as component_record
    where component_record.component_type =
          'principal'::public."ComponentType"
    limit 1;

    if not found then
        raise exception
            'TOKEN_PRINCIPAL_COMPONENT_NOT_FOUND';
    end if;

    v_quantity :=
        public.round_down(
            case
                when v_token_principal_component.debit_amount > 0
                then
                    v_token_principal_component.debit_amount
                else
                    v_token_principal_component.credit_amount
            end
        );

    if v_quantity is null
       or v_quantity <= 0
    then
        raise exception
            'INVALID_QUANTITY';
    end if;

    v_gross_token_quantity :=
        case
            when v_token_principal_component.credit_amount > 0
            then
                v_token_principal_component.credit_amount
            else
                v_quantity
        end;

    /*
     * Extract transfer fee.
     */
    v_stage :=
        'extract token transaction fee';

    select coalesce(
        component_record.debit_amount,
        0
    )
    into v_fee
    from unnest(
        v_token_components
    ) as component_record
    where component_record.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_fee :=
        coalesce(
            v_fee,
            0
        );

    /*
     * Extract fiat principal.
     */
    if not v_is_transfer then
        v_stage :=
            'extract fiat principal component';

        select component_record.*
        into v_fiat_principal_component
        from unnest(
            v_components
        ) as component_record
        where component_record.component_type =
              'principal'::public."ComponentType"
        limit 1;

        if not found then
            raise exception
                'FIAT_PRINCIPAL_COMPONENT_NOT_FOUND';
        end if;

        v_gross_amount :=
            coalesce(
                v_fiat_principal_component.debit_amount,
                0
            );

        if v_gross_amount <= 0 then
            raise exception
                'INVALID_GROSS_AMOUNT';
        end if;
    else
        v_gross_amount :=
            0;
    end if;

    /*
     * Build receiver notification.
     */
    v_stage :=
        'create recovery notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code =>
                v_blockchain_transaction.country_code,

            p_transaction_type =>
                v_transaction_type,

            p_audience =>
                'receiver'::public."NotificationAudience",

            p_amount =>
                v_gross_amount,

            p_currency =>
                case
                    when v_is_transfer
                        then 'GOLD'
                    else upper(v_currency_code)
                end,

            p_reference =>
                v_reference,

            p_quantity =>
                v_quantity,

            p_sender =>
                v_notification_sender,

            p_receiver =>
                v_notification_receiver
        );

    v_device_tokens :=
        public.fetch_device_tokens(
            v_blockchain_transaction.country_code,
            v_token_receiver_id
        );

    /*
     * Generate document numbers.
     */
    v_stage :=
        'generate recovery document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_blockchain_transaction.fiscal_year,
            v_blockchain_transaction.period,
            v_blockchain_transaction.country_code
        );

    v_token_document_number :=
        case
            when v_is_transfer
                then v_document_number
            else v_document_number || '-01'
        end;

    v_token_reference :=
        case
            when v_is_transfer
                then v_reference
            else v_reference || '-01'
        end;

    /*
     * ========================================================
     * FIAT LEG
     * ========================================================
     */
    if not v_is_transfer then
        v_stage :=
            'create fiat financial transaction';

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
            v_blockchain_transaction.fiscal_year,
            v_blockchain_transaction.period,
            v_reference,
            v_transaction_type,
            coalesce(
                v_blockchain_transaction.description,
                v_transaction_type::text
            ),
            v_blockchain_transaction.created_by,
            v_gross_amount,
            v_currency_code,
            v_blockchain_transaction.country_code
        )
        returning id
        into v_financial_transaction_id;

        v_stage :=
            'post fiat financial entries';

        perform *
        from public.post_financial_entries(
            p_document_number =>
                v_document_number,

            p_country_code =>
                v_blockchain_transaction.country_code,

            p_transaction_id =>
                v_financial_transaction_id,

            p_transaction_type =>
                v_transaction_type,

            p_created_by =>
                v_blockchain_transaction.created_by,

            p_components =>
                v_components,

            p_mappings =>
                v_mappings,

            p_currency_code =>
                v_currency_code,

            p_fiscal_year =>
                v_blockchain_transaction.fiscal_year,

            p_period =>
                v_blockchain_transaction.period,

            p_reference =>
                v_reference,

            p_deposit_type =>
                null
        );

        v_stage :=
            'post fiat wallet entries';

        perform *
        from public.post_wallet_entries(
            p_fiscal_year =>
                v_blockchain_transaction.fiscal_year,

            p_period =>
                v_blockchain_transaction.period,

            p_document_number =>
                v_document_number,

            p_reference =>
                v_reference,

            p_receiver_id =>
                v_fiat_receiver_id,

            p_sender_id =>
                v_fiat_sender_id,

            p_transaction_type =>
                v_transaction_type,

            p_credit_amount =>
                v_gross_amount,

            p_debit_amount =>
                v_gross_amount,

            p_sender_wallet_owner =>
                v_wallet_owners.sender_wallet_owner,

            p_receiver_wallet_owner =>
                v_wallet_owners.receiver_wallet_owner,

            p_currency_code =>
                v_currency_code,

            p_country_code =>
                v_blockchain_transaction.country_code,

            p_audit_action_type =>
                v_wallet_owners.audit_action_type,

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
    end if;

    /*
     * ========================================================
     * TOKEN LEG
     * ========================================================
     */
    v_stage :=
        'create token financial transaction';

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
        v_blockchain_transaction.fiscal_year,
        v_blockchain_transaction.period,
        v_token_reference,
        v_sub_transaction_type,
        coalesce(
            v_blockchain_transaction.description,
            v_transaction_type::text
        ),
        v_blockchain_transaction.created_by,
        v_gross_token_quantity,
        'gold',
        v_blockchain_transaction.country_code
    )
    returning id
    into v_token_financial_transaction_id;

    v_stage :=
        'post token financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_token_document_number,

        p_country_code =>
            v_blockchain_transaction.country_code,

        p_transaction_id =>
            v_token_financial_transaction_id,

        p_transaction_type =>
            v_sub_transaction_type,

        p_created_by =>
            v_blockchain_transaction.created_by,

        p_components =>
            v_token_components,

        p_mappings =>
            v_token_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_blockchain_transaction.fiscal_year,

        p_period =>
            v_blockchain_transaction.period,

        p_reference =>
            v_token_reference,

        p_deposit_type =>
            null
    );

    v_stage :=
        'post token wallet entries';

    select wallet_result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_blockchain_transaction.fiscal_year,

        p_period =>
            v_blockchain_transaction.period,

        p_document_number =>
            v_token_document_number,

        p_reference =>
            v_token_reference,

        p_receiver_id =>
            v_token_receiver_id,

        p_sender_id =>
            v_token_sender_id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            case
                when v_is_transfer
                    then v_quantity
                else v_gross_token_quantity
            end,

        p_debit_amount =>
            v_gross_token_quantity,

        p_sender_wallet_owner =>
            v_wallet_owners.receiver_wallet_owner,

        p_receiver_wallet_owner =>
            v_wallet_owners.sender_wallet_owner,

        p_currency_code =>
            'gold',

        p_country_code =>
            v_blockchain_transaction.country_code,

        p_audit_action_type =>
            v_wallet_owners.audit_action_type,

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            case
                when v_is_transfer
                    then v_fee
                else 0
            end,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    ) as wallet_result;

    /*
     * Complete blockchain transaction.
     */
    v_stage :=
        'complete blockchain transaction';

    update public.blockchain_transaction
    set
        document_number =
            v_token_document_number,

        status =
            'completed'::public."BlockchainTxStatus"
    where id =
          v_blockchain_transaction.id

      and document_number is null;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COMPLETION_FAILED';
    end if;

    v_result :=
        jsonb_build_object(
            'success',
            true,

            'document_number',
            v_document_number,

            'token_document_number',
            v_token_document_number,

            'reference',
            v_reference,

            'transaction_type',
            v_transaction_type,

            'quantity',
            v_quantity::text,

            'total_spent',
            v_gross_amount::text,

            'fee',
            v_fee::text,

            'explorer_url',
            v_blockchain_transaction.explorer_url,

            'receiver_notification_id',
            v_receiver_notification_id,

            'device_tokens',
            to_jsonb(v_device_tokens),

            'notification',
            to_jsonb(
                v_receiver_notification
            )
        );

    return v_result;

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
                    'INCOMPLETE_BLOCKCHAIN_POSTING_FAILED at [%s]: %s',
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
                    'Check the incomplete blockchain posting stage reported in the error'
                );
end;
$function$;

COMMIT;
