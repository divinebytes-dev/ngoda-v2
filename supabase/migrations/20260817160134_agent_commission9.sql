CREATE OR REPLACE FUNCTION public.create_my_agent_commission_settlement_batch(p_currency_code text, p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_currency_code text;

    v_fiscal_year integer;
    v_period integer;

    v_document_number text;

    v_total_agents integer := 0;
    v_total_amount numeric := 0;

    v_batch public.agent_settlement_batch%rowtype;

    v_items jsonb :=
        '[]'::jsonb;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication and authorization.
     */
    v_stage :=
        'authorize accounts user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch trusted Accounts user context.
     */
    v_stage :=
        'fetch accounts user';

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'ACCOUNTS_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'ACCOUNTS_USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(
            v_user.country_code
        ),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Validate input.
     */
    v_stage :=
        'validate input';

    v_currency_code :=
        lower(
            nullif(
                btrim(
                    p_currency_code
                ),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_CODE_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'INVALID_COMMISSION_SETTLEMENT_CURRENCY';
    end if;

    if p_start_date is null then
        raise exception
            'START_DATE_REQUIRED';
    end if;

    if p_end_date is null then
        raise exception
            'END_DATE_REQUIRED';
    end if;

    if p_start_date > p_end_date then
        raise exception
            'INVALID_SETTLEMENT_DATE_RANGE';
    end if;

    /*
     * Confirm that the currency is configured for the
     * Accounts user's country.
     */
    perform 1
    from public.country_currencies
        currency_record
    where lower(
        btrim(
            currency_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              currency_record.currency_code
          )
      ) =
        v_currency_code

      and currency_record.is_active =
        true
    limit 1;

    if not found then
        raise exception
            'COUNTRY_CURRENCY_NOT_ACTIVE';
    end if;

    /*
    * Prevent another settlement batch from being created
    * while the currency already has an unfinished payment.
    */
    v_stage :=
        'check existing payment underway';

    perform 1
    from public.agent_settlement_batch
        batch_record
    where lower(
        btrim(
            batch_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

    and lower(
        btrim(
            batch_record.currency_code
        )
    ) =
        v_currency_code

    and batch_record.status <>
        'settled'::public."SettlementStatus"
    limit 1;

    if found then
        raise exception
            'AGENT_COMMISSION_PAYMENT_ALREADY_UNDERWAY_%',
            upper(
                v_currency_code
            );
    end if;
    /*
     * Lock every eligible commission row.
     *
     * The end date is inclusive. Therefore, entries are
     * selected until the start of the following day.
     *
     * settlement_batch_id must be null so the same
     * commission cannot be included in multiple batches.
     */
    v_stage :=
        'lock unsettled commissions';

    perform 1
    from public.agent_commission
        commission_record
    where lower(
        btrim(
            commission_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              commission_record.currency_code
          )
      ) =
        v_currency_code

      and commission_record.is_settled =
        false

      and commission_record.settlement_batch_id
          is null

      and commission_record.created_at >=
        p_start_date::timestamptz

      and commission_record.created_at <
        (
            p_end_date +
            1
        )::timestamptz
    for update;

    if not found then
        return jsonb_build_object(
            'batch',
            null,

            'items',
            '[]'::jsonb
        );
    end if;

    /*
     * Calculate batch totals.
     *
     * agent_id is also used for vendors and merchants
     * earning withdrawal commission.
     */
    v_stage :=
        'calculate settlement totals';

    select
        count(
            distinct commission_record.agent_id
        )::integer,

        coalesce(
            sum(
                commission_record.commission_amount
            ),
            0
        )::numeric
    into
        v_total_agents,
        v_total_amount
    from public.agent_commission
        commission_record
    where lower(
        btrim(
            commission_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              commission_record.currency_code
          )
      ) =
        v_currency_code

      and commission_record.is_settled =
        false

      and commission_record.settlement_batch_id
          is null

      and commission_record.created_at >=
        p_start_date::timestamptz

      and commission_record.created_at <
        (
            p_end_date +
            1
        )::timestamptz;

    if v_total_agents <= 0
       or v_total_amount <= 0
    then
        raise exception
            'INVALID_AGENT_COMMISSION_SETTLEMENT_TOTAL';
    end if;

    /*
     * Fetch fiscal period.
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
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Generate settlement document number.
     */
    v_stage :=
        'generate document number';

    v_document_number :=
        public.generate_document_number(
            'AGENT-COMM',
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * Create the batch header.
     */
    v_stage :=
        'create settlement batch';

    insert into public.agent_settlement_batch (
        document_number,
        fiscal_year,
        period,
        currency_code,
        start_date,
        end_date,
        total_agents,
        total_amount,
        created_by,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        v_currency_code,
        p_start_date,
        p_end_date,
        v_total_agents,
        v_total_amount,
        v_user.id,
        lower(
            btrim(
                v_user.country_code
            )
        )
    )
    returning *
    into v_batch;

    /*
     * Create one settlement item per commission earner.
     *
     * agent_id may belong to an agent, vendor or merchant.
     */
    v_stage :=
        'create settlement items';

    insert into public.agent_settlement_item (
        batch_id,
        agent_id,
        fiscal_year,
        period,
        currency_code,
        total_commission,
        total_withdrawal_volume,
        total_fees_generated,
        country_code
    )
    select
        v_batch.id,
        commission_record.agent_id,
        v_fiscal_year,
        v_period,
        v_currency_code,

        coalesce(
            sum(
                commission_record.commission_amount
            ),
            0
        ),

        coalesce(
            sum(
                commission_record.amount
            ),
            0
        ),

        coalesce(
            sum(
                commission_record.fee_amount
            ),
            0
        ),

        lower(
            btrim(
                v_user.country_code
            )
        )

    from public.agent_commission
        commission_record

    where lower(
        btrim(
            commission_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              commission_record.currency_code
          )
      ) =
        v_currency_code

      and commission_record.is_settled =
        false

      and commission_record.settlement_batch_id
          is null

      and commission_record.created_at >=
        p_start_date::timestamptz

      and commission_record.created_at <
        (
            p_end_date +
            1
        )::timestamptz

    group by
        commission_record.agent_id;

    if not found then
        raise exception
            'AGENT_SETTLEMENT_ITEMS_NOT_CREATED';
    end if;

    /*
     * Reserve the underlying commission rows for this
     * batch.
     *
     * They remain unpaid until the batch payment process
     * sets is_settled to true.
     */
    v_stage :=
        'assign commissions to settlement batch';

    update public.agent_commission
    set
        settlement_batch_id =
            v_batch.id
    where lower(
        btrim(
            country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              currency_code
          )
      ) =
        v_currency_code

      and is_settled =
        false

      and settlement_batch_id
          is null

      and created_at >=
        p_start_date::timestamptz

      and created_at <
        (
            p_end_date +
            1
        )::timestamptz;

    if not found then
        raise exception
            'AGENT_COMMISSIONS_NOT_ASSIGNED_TO_BATCH';
    end if;

    /*
     * Return the created items.
     */
    v_stage :=
        'build result';

    select coalesce(
        jsonb_agg(
            to_jsonb(
                item_record
            )
            ||
            jsonb_build_object(
                'total_commission',
                item_record.total_commission::text,

                'total_withdrawal_volume',
                item_record.total_withdrawal_volume::text,

                'total_fees_generated',
                item_record.total_fees_generated::text
            )
            order by
                item_record.agent_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.agent_settlement_item
        item_record
    where item_record.batch_id =
          v_batch.id;

    return jsonb_build_object(
        'batch',
        to_jsonb(
            v_batch
        )
        ||
        jsonb_build_object(
            'total_amount',
            v_batch.total_amount::text
        ),

        'items',
        v_items
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
                    'AGENT_COMMISSION_SETTLEMENT_BATCH_FAILED at [%s]: %s',
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
                    'Check the Agent Commission Settlement Batch stage reported in the error'
                );
end;
$function$
