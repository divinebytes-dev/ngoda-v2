CREATE OR REPLACE FUNCTION public.detect_unhealthy_loan_positions(p_country_code text, p_gold_price_per_gram numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_country_code text;

    v_fiscal_year integer;
    v_period integer;

    v_target_ltv_percent numeric;
    v_liquidation_ltv_percent numeric;
    v_penalty_rate_percent numeric;

    v_target_ltv numeric;
    v_penalty_rate numeric;
    v_denominator numeric;

    v_position record;

    v_total_principal numeric;
    v_total_interest numeric;
    v_total_debt numeric;

    v_locked_tokens numeric;
    v_collateral_value numeric;
    v_current_ltv numeric;

    v_debt_repayment numeric;
    v_penalty_amount numeric;
    v_total_proceeds numeric;
    v_collateral_required numeric;

    v_evaluated integer := 0;
    v_detected integer := 0;
    v_already_underway integer := 0;
    v_skipped integer := 0;

    v_blockchain_code text;
    v_blockchain_gold_balance numeric;
    v_capped_sale_value numeric;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Only the liquidation Edge Function may execute
     * this financial detection process.
     */
    v_stage :=
        'authorize service role';

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
     * Validate input.
     */
    v_stage :=
        'validate input';

    v_country_code :=
        lower(
            nullif(
                btrim(
                    p_country_code
                ),
                ''
            )
        );

    if v_country_code is null then
        raise exception
            'COUNTRY_CODE_REQUIRED';
    end if;

    if p_gold_price_per_gram is null
       or p_gold_price_per_gram <= 0
    then
        raise exception
            'INVALID_GOLD_PRICE_PER_GRAM';
    end if;

    /*
     * Confirm that the country is operational.
     */
    v_stage :=
        'validate operational country';

    perform 1
    from public.operational_country
        country_record
    where lower(
        btrim(
            country_record.country_code
        )
    ) =
        v_country_code

      and country_record.is_active =
          true
    limit 1;

    if not found then
        raise exception
            'OPERATIONAL_COUNTRY_NOT_ACTIVE';
    end if;

    /*
     * Prevent overlapping cron runs from detecting
     * positions for the same country simultaneously.
     */
    v_stage :=
        'lock country liquidation detection';

    perform pg_advisory_xact_lock(
        hashtext(
            format(
                'loan-liquidation-detection:%s',
                v_country_code
            )
        )
    );

    /*
     * Fetch the current fiscal period.
     */
    v_stage :=
        'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch the configured target LTV.
     */
    v_stage :=
        'fetch target ltv';

    select config_record.rate
    into v_target_ltv_percent
    from public.loan_config
        config_record
    where config_record.config_type::text =
              'loan_ltv'

      and config_record.is_active =
              true
    limit 1;

    if not found
       or v_target_ltv_percent is null
    then
        raise exception
            'ACTIVE_LOAN_LTV_CONFIG_NOT_FOUND';
    end if;

    /*
     * Fetch the configured liquidation threshold.
     */
    v_stage :=
        'fetch liquidation ltv';

    select config_record.rate
    into v_liquidation_ltv_percent
    from public.loan_config
        config_record
    where config_record.config_type::text =
              'liquidation_ltv'

      and config_record.is_active =
              true
    limit 1;

    if not found
       or v_liquidation_ltv_percent is null
    then
        raise exception
            'ACTIVE_LIQUIDATION_LTV_CONFIG_NOT_FOUND';
    end if;

    /*
     * Fetch the liquidation penalty rate.
     */
    v_stage :=
        'fetch liquidation penalty';

    select config_record.rate
    into v_penalty_rate_percent
    from public.loan_config
        config_record
    where config_record.config_type::text =
              'liquidation_penalty'

      and config_record.is_active =
              true
    limit 1;

    if not found
       or v_penalty_rate_percent is null
    then
        raise exception
            'ACTIVE_LIQUIDATION_PENALTY_CONFIG_NOT_FOUND';
    end if;

    /*
     * Validate configuration.
     */
    v_stage :=
        'validate liquidation configuration';

    if v_target_ltv_percent <= 0
       or v_target_ltv_percent >= 100
    then
        raise exception
            'INVALID_TARGET_LTV';
    end if;

    if v_liquidation_ltv_percent <=
       v_target_ltv_percent
       or v_liquidation_ltv_percent > 100
    then
        raise exception
            'INVALID_LIQUIDATION_LTV';
    end if;

    if v_penalty_rate_percent < 0
       or v_penalty_rate_percent >= 100
    then
        raise exception
            'INVALID_LIQUIDATION_PENALTY_RATE';
    end if;

    v_target_ltv :=
        v_target_ltv_percent / 100;

    v_penalty_rate :=
        v_penalty_rate_percent / 100;

    /*
     * Formula denominator:
     *
     * 1 - targetLtv × (1 + penaltyRate)
     */
    v_denominator :=
        1 -
        (
            v_target_ltv *
            (
                1 +
                v_penalty_rate
            )
        );

    if v_denominator <= 0 then
        raise exception
            'INVALID_PARTIAL_LIQUIDATION_CONFIGURATION';
    end if;

    /*
     * Aggregate active loan balances per user.
     */
    v_stage :=
        'detect unhealthy positions';

    for v_position in
        select
            loan_record.user_id,

            greatest(
                coalesce(
                    sum(
                        coalesce(
                            entry_record.debit_principal,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_principal,
                            0
                        )
                    ),
                    0
                ),
                0
            )::numeric as total_principal,

            greatest(
                coalesce(
                    sum(
                        coalesce(
                            entry_record.debit_interest,
                            0
                        ) -
                        coalesce(
                            entry_record.credit_interest,
                            0
                        )
                    ),
                    0
                ),
                0
            )::numeric as total_interest,

            coalesce(
                collateral_record.locked_tokens,
                0
            )::numeric as locked_tokens

        from public.loan
            loan_record

        left join public.loan_entry
            entry_record
          on entry_record.loan_id =
             loan_record.id

        JOIN public.collateral AS collateral_record
          ON collateral_record.user_id = loan_record.user_id
         AND lower(btrim(collateral_record.country_code)) =
             v_country_code

        WHERE loan_record.status =
              'active'::public."LoanStatus"
          AND lower(btrim(loan_record.country_code)) =
              v_country_code
              
        group by
            loan_record.user_id,
            collateral_record.locked_tokens

        order by
            loan_record.user_id
    loop
        v_evaluated :=
            v_evaluated + 1;

        v_total_principal :=
            trunc(
                coalesce(
                    v_position.total_principal,
                    0
                ),
                6
            );

        v_total_interest :=
            trunc(
                coalesce(
                    v_position.total_interest,
                    0
                ),
                6
            );

        v_total_debt :=
            trunc(
                v_total_principal +
                v_total_interest,
                6
            );

        v_locked_tokens :=
            trunc(
                coalesce(
                    v_position.locked_tokens,
                    0
                ),
                6
            );

        if v_total_debt <= 0
           or v_locked_tokens <= 0
        then
            v_skipped :=
                v_skipped + 1;

            continue;
        end if;

        v_collateral_value :=
            trunc(
                v_locked_tokens *
                p_gold_price_per_gram,
                6
            );

        if v_collateral_value <= 0 then
            v_skipped :=
                v_skipped + 1;

            continue;
        end if;

        v_current_ltv :=
            trunc(
                (
                    v_total_debt /
                    v_collateral_value
                ) *
                100,
                6
            );

        if v_current_ltv <
           v_liquidation_ltv_percent
        then
            v_skipped :=
                v_skipped + 1;

            continue;
        end if;

        /*
         * Do not create another liquidation job while
         * an earlier job for the position is unfinished.
         *
         * Failed jobs remain underway because they must
         * be retried instead of producing a new transfer.
         */
        perform 1
        from public.liquidation_job
            job_record
        where job_record.user_id =
                  v_position.user_id

          and lower(
              btrim(
                  job_record.country_code
              )
          ) =
                  v_country_code

          and job_record.status::text not in (
              'completed',
              'cancelled'
          )
        limit 1;

        if found then
            v_already_underway :=
                v_already_underway + 1;

            continue;
        end if;

        /*
         * Calculate the debt repayment required to leave
         * the remaining position at the target LTV:
         *
         * repayment =
         *   (
         *     debt -
         *     targetLtv × collateralValue
         *   )
         *   /
         *   (
         *     1 -
         *     targetLtv × (1 + penaltyRate)
         *   )
         */
        v_debt_repayment :=
            trunc(
                (
                    v_total_debt -
                    (
                        v_target_ltv *
                        v_collateral_value
                    )
                ) /
                v_denominator,
                6
            );

        if v_debt_repayment <= 0 then
            v_skipped :=
                v_skipped + 1;

            continue;
        end if;

        /*
         * Debt repayment cannot exceed the outstanding
         * principal plus interest.
         */
        v_debt_repayment :=
            least(
                v_debt_repayment,
                v_total_debt
            );

        v_penalty_amount :=
            trunc(
                v_debt_repayment *
                v_penalty_rate,
                6
            );

        v_total_proceeds :=
            trunc(
                v_debt_repayment +
                v_penalty_amount,
                6
            );

        /*
         * If the available collateral cannot cover the
         * calculated proceeds, use all available
         * collateral and recalculate the repayment and
         * penalty split.
         */
        if v_total_proceeds >
           v_collateral_value
        then
            v_debt_repayment :=
                trunc(
                    least(
                        v_total_debt,
                        v_collateral_value /
                        (
                            1 +
                            v_penalty_rate
                        )
                    ),
                    6
                );

            v_penalty_amount :=
                trunc(
                    v_debt_repayment *
                    v_penalty_rate,
                    6
                );

            v_total_proceeds :=
                trunc(
                    v_debt_repayment +
                    v_penalty_amount,
                    6
                );
        end if;

        v_collateral_required :=
            trunc(
                v_total_proceeds /
                p_gold_price_per_gram,
                6
            );

        v_collateral_required :=
            least(
                v_collateral_required,
                v_locked_tokens
            );

        /*
         * Select the active customer GOLD wallet with the
         * largest balance on a supported active blockchain.
         *
         * A blockchain code provides a deterministic
         * tie-breaker when balances are equal.
         */
        v_stage := 'select liquidation blockchain';

        v_blockchain_code := NULL;
        v_blockchain_gold_balance := NULL;

        SELECT
            w.blockchain_code,
            trunc(w.balance, 6)
        INTO
            v_blockchain_code,
            v_blockchain_gold_balance
        FROM public.wallet AS w
        JOIN public.supported_blockchain AS b
          ON b.code = w.blockchain_code
         AND b.is_active = true
        WHERE w.user_id = v_position.user_id
          AND lower(btrim(w.country_code)) = v_country_code
          AND w.currency_code = 'gold'
          AND w.owner_type =
              'customer'::public."WalletOwnerType"
          AND w.is_active = true
          AND w.balance > 0
          AND w.balance::text NOT IN (
              'NaN', 'Infinity', '-Infinity'
          )
          AND EXISTS (
              SELECT 1
              FROM public.supported_blockchain_network AS n
              WHERE n.blockchain_id = b.id
                AND n.is_active = true
          )
        ORDER BY
            w.balance DESC,
            w.blockchain_code ASC
        LIMIT 1;

        IF NOT FOUND
           OR coalesce(v_blockchain_gold_balance, 0) <= 0
        THEN
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        /*
         * Liquidate from one blockchain only.
         *
         * If its balance covers the calculated quantity,
         * retain the existing calculation.
         *
         * Otherwise use that blockchain's balance and
         * recalculate repayment and penalty.
         */
        IF v_collateral_required > v_blockchain_gold_balance THEN
            v_stage := 'recalculate blockchain-limited liquidation';

            v_collateral_required :=
                least(
                    v_blockchain_gold_balance,
                    v_locked_tokens
                );

            v_capped_sale_value :=
                trunc(
                    v_collateral_required *
                    p_gold_price_per_gram,
                    6
                );

            /*
             * Preserve the existing penalty rule:
             *
             * proceeds = repayment + repayment × penalty rate
             */
            v_debt_repayment :=
                trunc(
                    least(
                        v_total_debt,
                        v_capped_sale_value /
                        (1 + v_penalty_rate)
                    ),
                    6
                );

            v_penalty_amount :=
                trunc(
                    v_debt_repayment * v_penalty_rate,
                    6
                );

            v_total_proceeds :=
                trunc(
                    v_debt_repayment + v_penalty_amount,
                    6
                );
        END IF;

        if v_debt_repayment <= 0
           or v_total_proceeds <= 0
           or v_collateral_required <= 0
        then
            v_skipped :=
                v_skipped + 1;

            continue;
        end if;

        /*
         * Store the immutable liquidation calculation.
         *
         * total_required is now the total collateral-sale
         * proceeds:
         *
         * debt repayment + liquidation penalty.
         */
        insert into public.liquidation_job (
            user_id,
            fiscal_year,
            period,

            total_principal,
            total_interest,
            total_debt,

            repayment_required,
            penalty_amount,
            total_required,

            collateral_value,
            collateral_required,

            gold_price,
            target_ltv,
            liquidation_ltv,
            penalty_rate,

            status,
            country_code,
            blockchain_code
        )
        values (
            v_position.user_id,
            v_fiscal_year,
            v_period,

            v_total_principal,
            v_total_interest,
            v_total_debt,

            v_debt_repayment,
            v_penalty_amount,
            v_total_proceeds,

            v_collateral_value,
            v_collateral_required,

            p_gold_price_per_gram,
            v_target_ltv_percent,
            v_liquidation_ltv_percent,
            v_penalty_rate_percent,

            'pending'::public."LiquidationJobStatus",
            v_country_code,
            v_blockchain_code
        );

        v_detected :=
            v_detected + 1;
    end loop;

    return jsonb_build_object(
        'success',
        true,

        'country_code',
        v_country_code,

        'fiscal_year',
        v_fiscal_year,

        'period',
        v_period,

        'gold_price',
        trim_scale(
            p_gold_price_per_gram
        )::text,

        'evaluated',
        v_evaluated,

        'detected',
        v_detected,

        'already_underway',
        v_already_underway,

        'skipped',
        v_skipped
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
                v_error_state,

            message =
                format(
                    'LIQUIDATION_DETECTION_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
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

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the liquidation detection stage reported in the error'
                );
end;
$function$
