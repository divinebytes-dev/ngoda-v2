CREATE OR REPLACE FUNCTION public.fetch_financial_statement_gl_entries(
    p_gl text,
    p_currency_code text,
    p_start_date date,
    p_end_date date,
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_gl text;
    v_currency_code text;

    v_gl_type text;
    v_gl_description text;
    v_is_debit_normal boolean;

    v_start_at timestamptz;
    v_end_at timestamptz;

    v_opening_debit numeric := 0;
    v_opening_credit numeric := 0;
    v_opening_balance numeric := 0;

    v_total_debit numeric := 0;
    v_total_credit numeric := 0;
    v_range_movement numeric := 0;

    v_calculated_closing_balance numeric := 0;
    v_closing_balance numeric := 0;
    v_difference numeric := 0;
    v_balanced boolean := true;

    v_total_entries bigint := 0;
    v_total_pages integer := 0;
    v_offset integer := 0;

    v_entries jsonb :=
        '[]'::jsonb;
begin
    /*
     * Authenticate and authorize.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'finance',
            'accounts',
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch the authenticated user's trusted country.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Normalize and validate parameters.
     */
    v_gl :=
        nullif(
            btrim(p_gl),
            ''
        );

    if v_gl is null then
        raise exception
            'GL_IS_REQUIRED';
    end if;

    v_currency_code :=
        nullif(
            lower(
                btrim(p_currency_code)
            ),
            ''
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_start_date is null then
        raise exception
            'START_DATE_IS_REQUIRED';
    end if;

    if p_end_date is null then
        raise exception
            'END_DATE_IS_REQUIRED';
    end if;

    if p_start_date > p_end_date then
        raise exception
            'INVALID_DATE_RANGE';
    end if;

    if p_page is null
       or p_page < 1 then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100 then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    /*
     * Convert the requested dates into the same effective
     * range as the old implementation:
     *
     * start date = beginning of day
     * end date   = entire end day
     *
     * Using the following day as an exclusive upper bound
     * avoids timestamp precision problems.
     */
    v_start_at :=
        p_start_date::timestamp
        at time zone 'UTC';

    v_end_at :=
        (p_end_date + 1)::timestamp
        at time zone 'UTC';

    /*
     * Fetch GL account details.
     */
    select
        gl_account_record.type::text,
        coalesce(
            gl_account_record.description,
            ''
        )
    into
        v_gl_type,
        v_gl_description
    from public.gl_account
        gl_account_record
    where gl_account_record.code =
          v_gl
    limit 1;

    if not found then
        raise exception
            'GL_ACCOUNT_NOT_FOUND';
    end if;

    /*
     * Asset and expense accounts are debit-normal.
     * Other account types are credit-normal.
     *
     * This preserves the old TypeScript behaviour.
     */
    v_is_debit_normal :=
        v_gl_type in (
            'asset',
            'expense'
        );

    /*
     * Calculate the opening balance from all entries
     * before the requested start date.
     */
    select
        coalesce(
            sum(
                financial_entry_record.debit
            ),
            0
        ),
        coalesce(
            sum(
                financial_entry_record.credit
            ),
            0
        )
    into
        v_opening_debit,
        v_opening_credit
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.country_code =
          v_user.country_code

      and financial_entry_record.currency_code =
          v_currency_code

      and financial_entry_record.gl_account_code =
          v_gl

      and financial_entry_record.created_at <
          v_start_at;

    if v_is_debit_normal then
        v_opening_balance :=
            v_opening_debit -
            v_opening_credit;
    else
        v_opening_balance :=
            v_opening_credit -
            v_opening_debit;
    end if;

    /*
     * Calculate totals for the requested statement range.
     */
    select
        coalesce(
            sum(
                financial_entry_record.debit
            ),
            0
        ),
        coalesce(
            sum(
                financial_entry_record.credit
            ),
            0
        ),
        count(*)
    into
        v_total_debit,
        v_total_credit,
        v_total_entries
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.country_code =
          v_user.country_code

      and financial_entry_record.currency_code =
          v_currency_code

      and financial_entry_record.gl_account_code =
          v_gl

      and financial_entry_record.created_at >=
          v_start_at

      and financial_entry_record.created_at <
          v_end_at;

    if v_is_debit_normal then
        v_range_movement :=
            v_total_debit -
            v_total_credit;
    else
        v_range_movement :=
            v_total_credit -
            v_total_debit;
    end if;

    v_calculated_closing_balance :=
        v_opening_balance +
        v_range_movement;

    /*
     * The old financial-statement implementation derives
     * closing balance from the financial entries.
     */
    v_closing_balance :=
        v_calculated_closing_balance;

    v_difference :=
        v_closing_balance -
        v_calculated_closing_balance;

    v_balanced :=
        abs(v_difference) <=
        0.000001;

    /*
     * Pagination.
     */
    if v_total_entries = 0 then
        v_total_pages := 0;
    else
        v_total_pages :=
            ceil(
                v_total_entries::numeric /
                p_page_size::numeric
            )::integer;
    end if;

    v_offset :=
        (p_page - 1) *
        p_page_size;

    /*
     * Build the paginated GL entries.
     *
     * Running balance is calculated before pagination so
     * page 2, page 3, etc. continue from the preceding
     * entries rather than restarting at opening balance.
     */
    with ordered_entries as (
        select
            financial_entry_record.id,
            financial_entry_record.period,
            financial_entry_record.fiscal_year,
            financial_entry_record.reference,
            financial_entry_record.document_number,
            financial_entry_record.transaction_id,
            financial_entry_record.transaction_type,
            financial_entry_record.gl_account_code,
            financial_entry_record.currency_code,
            financial_entry_record.debit,
            financial_entry_record.credit,
            financial_entry_record.deposit_type,
            financial_entry_record.created_at,

            v_opening_balance +
            sum(
                case
                    when v_is_debit_normal then
                        coalesce(
                            financial_entry_record.debit,
                            0
                        ) -
                        coalesce(
                            financial_entry_record.credit,
                            0
                        )
                    else
                        coalesce(
                            financial_entry_record.credit,
                            0
                        ) -
                        coalesce(
                            financial_entry_record.debit,
                            0
                        )
                end
            ) over (
                order by
                    financial_entry_record.created_at asc,
                    financial_entry_record.id asc
                rows between
                    unbounded preceding
                    and current row
            ) as running_balance

        from public.financial_entry
            financial_entry_record

        where financial_entry_record.country_code =
              v_user.country_code

          and financial_entry_record.currency_code =
              v_currency_code

          and financial_entry_record.gl_account_code =
              v_gl

          and financial_entry_record.created_at >=
              v_start_at

          and financial_entry_record.created_at <
              v_end_at
    ),

    paged_entries as (
        select *
        from ordered_entries
        order by
            created_at asc,
            id asc
        limit p_page_size
        offset v_offset
    )

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                paged_entry.id,

                'period',
                paged_entry.period,

                'fiscal_year',
                paged_entry.fiscal_year,

                'reference',
                paged_entry.reference,

                'document_number',
                paged_entry.document_number,

                'transaction_id',
                paged_entry.transaction_id,

                'transaction_type',
                paged_entry.transaction_type,

                'gl_account_code',
                paged_entry.gl_account_code,

                'currency_code',
                paged_entry.currency_code,

                'debit',
                paged_entry.debit,

                'credit',
                paged_entry.credit,

                'deposit_type',
                paged_entry.deposit_type,

                'running_balance',
                paged_entry.running_balance,

                'created_at',
                paged_entry.created_at
            )
            order by
                paged_entry.created_at asc,
                paged_entry.id asc
        ),
        '[]'::jsonb
    )
    into v_entries
    from paged_entries
        paged_entry;

    /*
     * Return the FinancialStatementDrilldown contract.
     */
    return jsonb_build_object(
        'gl_account_code',
        v_gl,

        'description',
        v_gl_description,

        'currency_code',
        v_currency_code,

        'start_date',
        p_start_date,

        'end_date',
        p_end_date,

        'balanced',
        v_balanced,

        'opening_balance',
        v_opening_balance,

        'total_debit',
        v_total_debit,

        'total_credit',
        v_total_credit,

        'calculated_closing_balance',
        v_calculated_closing_balance,

        'closing_balance',
        v_closing_balance,

        'difference',
        v_difference,

        'pagination',
        jsonb_build_object(
            'page',
            p_page,

            'page_size',
            p_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            p_page > 1,

            'has_next',
            p_page < v_total_pages
        ),

        'entries',
        v_entries
    );
end;
$function$;