CREATE OR REPLACE FUNCTION public.build_posting_components(
    p_transaction_type public."TransactionType",
    p_principal numeric,
    p_mappings public.transaction_gl_mapping[],
    p_country_code text,
    p_currency_code text,
    p_reverse boolean DEFAULT false
)
RETURNS public.posting_component[]
LANGUAGE plpgsql
STABLE
AS $function$
declare
    v_components
        public.posting_component[] :=
            array[]::public.posting_component[];

    v_pricing
        public.pricing_result :=
            row(
                0,
                0,
                0,
                0,
                0,
                0
            )::public.pricing_result;

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
     * CALCULATE PRICING
     * ==========================================================
     */
    v_stage :=
        'calculate pricing';


    if not public.is_gold_transaction(
        v_transaction_type
    )
    then
        v_pricing :=
            public.calculate_transaction_pricing(
                p_transaction_type,
                p_principal,
                p_country_code,
                p_currency_code
            );

    else
        /*
         * ======================================================
         * GOLD BUY
         * ======================================================
         */
        if v_transaction_type in (
            'gold_token_buy'::public."TransactionType",
            'gold_token_buy_sub_tx'::public."TransactionType"
        )
        then
            v_stage :=
                'calculate gold buy pricing';


            v_pricing :=
                public.calculate_gold_buy_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );


            /*
             * --------------------------------------------------
             * MAIN GOLD BUY — QUANTITY INPUT
             * --------------------------------------------------
             *
             * When the signed transaction contains:
             *
             *     amount   = gold quantity
             *     currency = gold
             *
             * p_principal is expressed in GOLD.
             *
             * But gold_token_buy is the USD financial
             * transaction.
             *
             * calculate_gold_buy_pricing therefore returns
             * the calculated USD fiatPaid through
             * pricing_result.fiat_received.
             *
             * That USD amount becomes the main posting
             * principal.
             */
            if v_transaction_type =
                   'gold_token_buy'::public."TransactionType"
               and lower(
                   p_currency_code
               ) = 'gold'
            then
                v_stage :=
                    'read gold buy USD principal';


                v_new_principal :=
                    public.round_down(
                        v_pricing.fiat_received
                    );


                if v_new_principal <= 0 then
                    raise exception
                        'INVALID_GOLD_BUY_USD_PRINCIPAL';
                end if;
            end if;


        /*
         * ======================================================
         * GOLD TRANSFER
         * ======================================================
         */
        elsif v_transaction_type =
              'gold_token_transfer'::public."TransactionType"
        then
            v_stage :=
                'calculate gold transfer pricing';


            v_pricing :=
                public.calculate_gold_transfer_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );


        /*
         * ======================================================
         * GOLD SELL
         * ======================================================
         */
        elsif v_transaction_type in (
            'gold_token_sell'::public."TransactionType",
            'gold_token_sell_sub_tx'::public."TransactionType"
        )
        then
            v_stage :=
                'calculate gold sell pricing';


            v_pricing :=
                public.calculate_gold_sell_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );


            v_stage :=
                'read fiat_received';


            v_new_principal :=
                public.round_down(
                    v_pricing.fiat_received
                );
        end if;


        /*
         * ======================================================
         * GOLD SUB-TRANSACTION
         * ======================================================
         *
         * Token sub-transactions are denominated in GOLD.
         *
         * Their principal must therefore always come from
         * the calculated token quantity rather than the
         * original fiat amount.
         */
        v_stage :=
            'check gold sub-transaction';


        if public.is_gold_sub_transaction(
            v_transaction_type
        )
        then
            v_stage :=
                'read pricing quantity';


            v_new_principal :=
                public.round_down(
                    v_pricing.quantity
                );


            if v_new_principal <= 0 then
                raise exception
                    'INVALID_GOLD_TOKEN_PRINCIPAL';
            end if;
        end if;
    end if;


    /*
     * ==========================================================
     * PRINCIPAL MODE
     * ==========================================================
     */
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