CREATE OR REPLACE FUNCTION public.create_my_government_tax_settlement_batch(
    p_currency_code text,
    p_start_date date,
    p_end_date date
)
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

    v_document_prefix text;
    v_document_number text;

    v_batch_id
        public.government_tax_settlement_batch.id%type;

    v_total_gross numeric := 0;
    v_total_tax numeric := 0;

    v_payable_count integer := 0;
    v_assigned_count integer := 0;
    v_item_count integer := 0;

    v_existing_batch record;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication and Accounts authorization.
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
     * Validate input.
     */
    v_stage :=
        'validate input';

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_CODE_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'INVALID_TAX_SETTLEMENT_CURRENCY';
    end if;

    if p_start_date is null then
        raise exception
            'START_DATE_REQUIRED';
    end if;

    if p_end_date is null then
        raise exception
            'END_DATE_REQUIRED';
    end if;

    /*
     * A same-day settlement is valid.
     */
    if p_start_date > p_end_date then
        raise exception
            'INVALID_SETTLEMENT_DATE_RANGE';
    end if;

    /*
     * Fetch trusted Accounts user.
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
        btrim(v_user.country_code),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Validate the country currency.
     *
     * Both the country configuration and the system
     * supported-currency configuration must be active.
     */
    v_stage :=
        'validate settlement currency';

    perform 1
    from public.country_currencies
        country_currency_record
    join public.supported_currency
        supported_currency_record
      on lower(
          btrim(
              supported_currency_record.currency_code
          )
      ) =
         lower(
             btrim(
                 country_currency_record.currency_code
             )
         )
    where lower(
        btrim(
            country_currency_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              country_currency_record.currency_code
          )
      ) =
          v_currency_code

      and country_currency_record.is_active =
          true

      and supported_currency_record.is_active =
          true

      and supported_currency_record.currency_category =
          'fiat'::public."CurrencyCategory"
    limit 1;

    if not found then
        raise exception
            'SETTLEMENT_CURRENCY_NOT_ACTIVE';
    end if;

    /*
     * Serialize tax-batch creation by country and
     * currency.
     *
     * This prevents two requests from both passing the
     * active-batch check before either inserts a batch.
     */
    v_stage :=
        'lock tax settlement currency';

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            format(
                'government-tax-settlement:%s:%s',
                lower(
                    btrim(
                        v_user.country_code
                    )
                ),
                v_currency_code
            ),
            0
        )
    );

    /*
     * Do not create another batch while an earlier batch
     * for the currency is still actionable or processing.
     *
     * Failed and partial batches must be retried instead
     * of creating a new batch.
     */
    v_stage :=
        'check payment underway';

    select
        batch_record.id,
        batch_record.document_number,
        batch_record.status
    into v_existing_batch
    from public.government_tax_settlement_batch
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

      and batch_record.status::text in (
          'draft',
          'pending',
          'approved',
          'partial',
          'failed',
          'processing'
      )
    order by
        batch_record.created_at desc,
        batch_record.id desc
    limit 1
    for update;

    if found then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_PAYMENT_UNDERWAY_%_%',
            upper(
                v_existing_batch.status::text
            ),
            v_existing_batch.document_number;
    end if;

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
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Lock every eligible Government Tax payable row.
     *
     * The end date is inclusive, therefore selection
     * continues until the start of the following day.
     *
     * settlement_batch_id must be null so a payable
     * cannot belong to multiple batches.
     */
    v_stage :=
        'lock unsettled government tax';

    perform 1
    from public.government_tax_payable
        tax_record
    where lower(
        btrim(
            tax_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              tax_record.currency_code
          )
      ) =
          v_currency_code

      and tax_record.is_settled =
          false

      and tax_record.settlement_batch_id
          is null

      and tax_record.created_at >=
          p_start_date::timestamptz

      and tax_record.created_at <
          (
              p_end_date +
              1
          )::timestamptz
    for update;

    /*
     * Aggregate the locked payable rows.
     */
    v_stage :=
        'aggregate government tax';

    select
        count(*)::integer,

        coalesce(
            sum(
                tax_record.gross_amount
            ),
            0
        ),

        coalesce(
            sum(
                tax_record.tax_amount
            ),
            0
        )
    into
        v_payable_count,
        v_total_gross,
        v_total_tax
    from public.government_tax_payable
        tax_record
    where lower(
        btrim(
            tax_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              tax_record.currency_code
          )
      ) =
          v_currency_code

      and tax_record.is_settled =
          false

      and tax_record.settlement_batch_id
          is null

      and tax_record.created_at >=
          p_start_date::timestamptz

      and tax_record.created_at <
          (
              p_end_date +
              1
          )::timestamptz;

    if v_payable_count = 0 then
        raise exception
            'GOVERNMENT_TAX_PAYABLE_NOT_FOUND_FOR_SELECTED_DATE_RANGE';
    end if;

    if v_total_tax <= 0 then
        raise exception
            'INVALID_GOVERNMENT_TAX_SETTLEMENT_TOTAL';
    end if;

    /*
     * Fetch the configured document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'government_tax_settlement'::public."TransactionType"
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
     * Generate the settlement batch document number.
     */
    v_stage :=
        'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * Create the draft batch.
     *
     * total_amount is the tax amount payable to the
     * Government, not the underlying transaction volume.
     */
    v_stage :=
        'create tax settlement batch';

    insert into public.government_tax_settlement_batch (
        document_number,
        fiscal_year,
        period,
        currency_code,
        country_code,
        start_date,
        end_date,
        total_amount,
        status,
        created_by
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        v_currency_code,
        v_user.country_code,
        p_start_date,
        p_end_date,
        v_total_tax,
        'draft',
        v_user.id
    )
    returning id
    into v_batch_id;

    if v_batch_id is null then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_BATCH_CREATE_FAILED';
    end if;

    /*
     * Create one item per transaction type.
     */
    v_stage :=
        'create tax settlement items';

    insert into public.government_tax_settlement_item (
        batch_id,
        transaction_type,
        fiscal_year,
        period,
        currency_code,
        country_code,
        gross_amount,
        tax_amount,
        status
    )
    select
        v_batch_id,
        tax_record.transaction_type,
        v_fiscal_year,
        v_period,
        v_currency_code,
        v_user.country_code,

        coalesce(
            sum(
                tax_record.gross_amount
            ),
            0
        ),

        coalesce(
            sum(
                tax_record.tax_amount
            ),
            0
        ),

        'draft'
    from public.government_tax_payable
        tax_record
    where lower(
        btrim(
            tax_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and lower(
          btrim(
              tax_record.currency_code
          )
      ) =
          v_currency_code

      and tax_record.is_settled =
          false

      and tax_record.settlement_batch_id
          is null

      and tax_record.created_at >=
          p_start_date::timestamptz

      and tax_record.created_at <
          (
              p_end_date +
              1
          )::timestamptz

    group by
        tax_record.transaction_type;

    get diagnostics
        v_item_count =
            row_count;

    if v_item_count = 0 then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_ITEMS_CREATE_FAILED';
    end if;

    /*
     * Assign every selected payable row to the batch.
     */
    v_stage :=
        'assign government tax payables';

    update public.government_tax_payable
    set
        settlement_batch_id =
            v_batch_id
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

    get diagnostics
        v_assigned_count =
            row_count;

    if v_assigned_count <>
       v_payable_count
    then
        raise exception
            'GOVERNMENT_TAX_PAYABLE_ASSIGNMENT_COUNT_MISMATCH_EXPECTED_%_ASSIGNED_%',
            v_payable_count,
            v_assigned_count;
    end if;

    return jsonb_build_object(
        'success',
        true,

        'batch_id',
        v_batch_id,

        'document_number',
        v_document_number,

        'currency_code',
        v_currency_code,

        'start_date',
        p_start_date,

        'end_date',
        p_end_date,

        'status',
        'draft',

        /*
         * Underlying transaction volume.
         */
        'totalAmount',
        trim_scale(
            v_total_gross
        )::text,

        /*
         * Amount payable to Government.
         */
        'totalTax',
        trim_scale(
            v_total_tax
        )::text,

        'payable_count',
        v_payable_count,

        'item_count',
        v_item_count
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
                    'GOVERNMENT_TAX_SETTLEMENT_BATCH_FAILED at [%s]: %s',
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
                    'Check the Government Tax Settlement Batch stage'
                );
end;
$function$;