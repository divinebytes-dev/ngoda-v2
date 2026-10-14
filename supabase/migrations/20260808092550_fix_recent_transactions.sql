create or replace function public.fetch_my_recent_financial_transactions(
    p_currency_code text default null,
    p_page integer default 1,
    p_page_size integer default 50,
    p_start_date date default null,
    p_end_date date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_currency_code text;
    v_currency_record record;

    v_page integer;
    v_page_size integer;
    v_offset integer;

    v_total_entries bigint;
    v_total_pages integer;

    v_transactions jsonb;

    /*
     * The frontend expects currencies directly at the root:
     *
     * {
     *   "usd": {
     *     "pagination": {...},
     *     "transactions": [...]
     *   }
     * }
     */
    v_result jsonb :=
        '{}'::jsonb;
begin
    /*
     * Authentication and role authorization.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch the authenticated user's country for report
     * data isolation.
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
     * Validate pagination.
     */
    if p_page is null
       or p_page < 1
    then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    /*
     * Validate optional date range.
     */
    if p_start_date is not null
       and p_end_date is not null
       and p_end_date < p_start_date
    then
        raise exception
            'INVALID_REPORT_DATE_RANGE';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    v_page_size :=
        p_page_size;

    /*
     * When no currency is selected, return the first page
     * independently for every currency.
     */
    v_page :=
        case
            when v_currency_code is null
                then 1
            else p_page
        end;

    v_offset :=
        (v_page - 1) *
        v_page_size;

    /*
     * Get currencies directly from financial_transaction.
     *
     * There is no dependency on country_currencies.
     */
    for v_currency_record in
        select distinct
            lower(
                financial_transaction_record.currency_code
            ) as currency_code
        from public.financial_transaction
            financial_transaction_record
        where financial_transaction_record.country_code =
              v_user.country_code

          and financial_transaction_record.currency_code
              is not null

          and btrim(
              financial_transaction_record.currency_code
          ) <> ''

          and (
              v_currency_code is null
              or lower(
                  financial_transaction_record.currency_code
              ) = v_currency_code
          )

          and (
              p_start_date is null
              or financial_transaction_record.created_at >=
                  p_start_date::timestamptz
          )

          and (
              p_end_date is null
              or financial_transaction_record.created_at <
                  (
                      p_end_date +
                      interval '1 day'
                  )
          )
        order by
            lower(
                financial_transaction_record.currency_code
            )
    loop
        /*
         * Count matching transactions for this currency.
         */
        select count(*)
        into v_total_entries
        from public.financial_transaction
            financial_transaction_record
        where financial_transaction_record.country_code =
              v_user.country_code

          and lower(
              financial_transaction_record.currency_code
          ) =
              v_currency_record.currency_code

          and (
              p_start_date is null
              or financial_transaction_record.created_at >=
                  p_start_date::timestamptz
          )

          and (
              p_end_date is null
              or financial_transaction_record.created_at <
                  (
                      p_end_date +
                      interval '1 day'
                  )
          );

        v_total_pages :=
            case
                when v_total_entries = 0
                    then 1
                else ceil(
                    v_total_entries::numeric /
                    v_page_size::numeric
                )::integer
            end;

        /*
         * Fetch the requested transaction page.
         */
        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'fiscal_year',
                    transaction_record.fiscal_year,

                    'period',
                    transaction_record.period,

                    'created_at',
                    transaction_record.created_at,

                    'document_number',
                    transaction_record.document_number,

                    'transaction_type',
                    transaction_record.transaction_type,

                    'description',
                    transaction_record.description,

                    'gross_amount',
                    transaction_record.gross_amount
                )
                order by
                    transaction_record.created_at desc,
                    transaction_record.document_number desc
            ),
            '[]'::jsonb
        )
        into v_transactions
        from (
            select
                financial_transaction_record.fiscal_year,
                financial_transaction_record.period,
                financial_transaction_record.created_at,
                financial_transaction_record.document_number,
                financial_transaction_record.transaction_type,
                financial_transaction_record.description,
                financial_transaction_record.gross_amount
            from public.financial_transaction
                financial_transaction_record
            where financial_transaction_record.country_code =
                  v_user.country_code

              and lower(
                  financial_transaction_record.currency_code
              ) =
                  v_currency_record.currency_code

              and (
                  p_start_date is null
                  or financial_transaction_record.created_at >=
                      p_start_date::timestamptz
              )

              and (
                  p_end_date is null
                  or financial_transaction_record.created_at <
                      (
                          p_end_date +
                          interval '1 day'
                      )
              )
            order by
                financial_transaction_record.created_at desc,
                financial_transaction_record.document_number desc
            limit v_page_size
            offset v_offset
        ) as transaction_record;

        /*
         * Add the currency directly to the root object.
         */
        v_result :=
            v_result ||
            jsonb_build_object(
                v_currency_record.currency_code,

                jsonb_build_object(
                    'pagination',
                    jsonb_build_object(
                        'page',
                        v_page,

                        'page_size',
                        v_page_size,

                        'total_entries',
                        v_total_entries,

                        'total_pages',
                        v_total_pages,

                        'has_previous',
                        v_page > 1,

                        'has_next',
                        v_page < v_total_pages
                    ),

                    'transactions',
                    v_transactions
                )
            );
    end loop;

    return v_result;
end;
$function$;


revoke all on function
    public.fetch_my_recent_financial_transactions(
        text,
        integer,
        integer,
        date,
        date
    )
from public;

revoke all on function
    public.fetch_my_recent_financial_transactions(
        text,
        integer,
        integer,
        date,
        date
    )
from anon;

grant execute on function
    public.fetch_my_recent_financial_transactions(
        text,
        integer,
        integer,
        date,
        date
    )
to authenticated;