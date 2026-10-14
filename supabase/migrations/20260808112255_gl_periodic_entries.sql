create or replace function public.fetch_my_gl_period_entries(
    p_gl_account_code text,
    p_currency_code text,
    p_fiscal_year integer,
    p_period integer,
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_gl_account_code text;
    v_currency_code text;

    v_gl_description text;
    v_gl_type text;

    v_is_debit_normal boolean;

    v_exact_snapshot
        public.gl_balance_snapshot%rowtype;

    v_previous_snapshot
        public.gl_balance_snapshot%rowtype;

    v_opening_balance numeric := 0;
    v_closing_balance numeric := 0;

    v_total_entries bigint := 0;
    v_total_pages integer := 1;

    v_total_debit numeric := 0;
    v_total_credit numeric := 0;

    v_total_movement numeric := 0;

    v_calculated_closing_balance numeric := 0;
    v_difference numeric := 0;

    v_balance_tolerance numeric :=
        0.000001;

    v_page integer;
    v_page_size integer;
    v_offset integer;

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
            'treasury',
            'finance',
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate required parameters.
     */
    v_gl_account_code :=
        nullif(
            btrim(p_gl_account_code),
            ''
        );

    if v_gl_account_code is null then
        raise exception
            'GL_IS_REQUIRED';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_fiscal_year is null then
        raise exception
            'FISCAL_YEAR_IS_REQUIRED';
    end if;

    if p_period is null then
        raise exception
            'PERIOD_IS_REQUIRED';
    end if;

    if p_period < 1
       or p_period > 12
    then
        raise exception
            'INVALID_PERIOD';
    end if;

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

    v_page :=
        p_page;

    v_page_size :=
        p_page_size;

    v_offset :=
        (v_page - 1) *
        v_page_size;

    /*
     * Fetch the authenticated user's country.
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
     * Fetch GL information and determine its normal balance.
     */
    select
        coalesce(
            gl_account_record.description,
            ''
        ),

        lower(
            gl_account_record.type::text
        )
    into
        v_gl_description,
        v_gl_type
    from public.gl_account
        gl_account_record
    where gl_account_record.code =
          v_gl_account_code;

    if not found then
        raise exception
            'GL_ACCOUNT_NOT_FOUND';
    end if;

    v_is_debit_normal :=
        v_gl_type in (
            'asset',
            'expense'
        );

    /*
     * First try the exact requested-period snapshot.
     */
    select snapshot_record.*
    into v_exact_snapshot
    from public.gl_balance_snapshot
        snapshot_record
    where snapshot_record.country_code =
          v_user.country_code

      and snapshot_record.gl_account_code =
          v_gl_account_code

      and lower(
          snapshot_record.currency_code
      ) =
          v_currency_code

      and snapshot_record.fiscal_year =
          p_fiscal_year

      and snapshot_record.period =
          p_period
    limit 1;

    if found then
        v_opening_balance :=
            coalesce(
                v_exact_snapshot.opening_balance,
                0
            );

        v_closing_balance :=
            coalesce(
                v_exact_snapshot.closing_balance,
                0
            );
    else
        /*
         * No exact snapshot exists. Find the latest preceding
         * snapshot, first in the same fiscal year and then in
         * an earlier fiscal year.
         */
        select snapshot_record.*
        into v_previous_snapshot
        from public.gl_balance_snapshot
            snapshot_record
        where snapshot_record.country_code =
              v_user.country_code

          and snapshot_record.gl_account_code =
              v_gl_account_code

          and lower(
              snapshot_record.currency_code
          ) =
              v_currency_code

          and (
              snapshot_record.fiscal_year <
                  p_fiscal_year

              or (
                  snapshot_record.fiscal_year =
                      p_fiscal_year

                  and snapshot_record.period <
                      p_period
              )
          )
        order by
            snapshot_record.fiscal_year desc,
            snapshot_record.period desc
        limit 1;

        if found then
            v_opening_balance :=
                coalesce(
                    v_previous_snapshot.closing_balance,
                    0
                );

            v_closing_balance :=
                v_opening_balance;
        else
            v_opening_balance := 0;
            v_closing_balance := 0;
        end if;
    end if;

    /*
     * Count entries and calculate complete period totals.
     */
    select
        count(*),

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
        v_total_entries,
        v_total_debit,
        v_total_credit
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.country_code =
          v_user.country_code

      and financial_entry_record.gl_account_code =
          v_gl_account_code

      and lower(
          financial_entry_record.currency_code
      ) =
          v_currency_code

      and financial_entry_record.fiscal_year =
          p_fiscal_year

      and financial_entry_record.period =
          p_period;

    /*
     * Calculate the closing balance according to the GL's
     * normal balance type.
     */
    v_total_movement :=
        case
            when v_is_debit_normal
            then
                v_total_debit -
                v_total_credit

            else
                v_total_credit -
                v_total_debit
        end;

    v_calculated_closing_balance :=
        v_opening_balance +
        v_total_movement;

    v_difference :=
        v_calculated_closing_balance -
        v_closing_balance;

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
     * Calculate the running balance over all period entries,
     * then return only the requested page.
     */
    with ordered_entries as (
        select
            financial_entry_record.id,
            financial_entry_record.document_number,
            financial_entry_record.transaction_type,

            coalesce(
                financial_entry_record.debit,
                0
            ) as debit,

            coalesce(
                financial_entry_record.credit,
                0
            ) as credit,

            financial_entry_record.created_at,

            row_number() over (
                order by
                    financial_entry_record.created_at asc,
                    financial_entry_record.id asc
            ) as entry_number,

            sum(
                case
                    when v_is_debit_normal
                    then
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

                rows between unbounded preceding
                         and current row
            ) as cumulative_movement
        from public.financial_entry
            financial_entry_record
        where financial_entry_record.country_code =
              v_user.country_code

          and financial_entry_record.gl_account_code =
              v_gl_account_code

          and lower(
              financial_entry_record.currency_code
          ) =
              v_currency_code

          and financial_entry_record.fiscal_year =
              p_fiscal_year

          and financial_entry_record.period =
              p_period
    ),

    paginated_entries as (
        select ordered_entry.*
        from ordered_entries
            ordered_entry
        where ordered_entry.entry_number >
              v_offset

          and ordered_entry.entry_number <=
              (
                  v_offset +
                  v_page_size
              )
        order by
            ordered_entry.entry_number
    )

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                paginated_entry.id::text,

                'document_number',
                paginated_entry.document_number,

                'transaction_type',
                paginated_entry.transaction_type,

                'debit',
                paginated_entry.debit::text,

                'credit',
                paginated_entry.credit::text,

                'running_balance',
                (
                    v_opening_balance +
                    paginated_entry.cumulative_movement
                )::text,

                'created_at',
                paginated_entry.created_at
            )
            order by
                paginated_entry.entry_number
        ),
        '[]'::jsonb
    )
    into v_entries
    from paginated_entries
        paginated_entry;

    return jsonb_build_object(
        'currency_code',
        v_currency_code,

        'fiscal_year',
        p_fiscal_year,

        'gl_account_code',
        v_gl_account_code,

        'period',
        p_period,

        'description',
        v_gl_description,

        'balanced',
        abs(
            v_difference
        ) <= v_balance_tolerance,

        'difference',
        v_difference::text,

        'opening_balance',
        v_opening_balance::text,

        'total_debit',
        v_total_debit::text,

        'total_credit',
        v_total_credit::text,

        'calculated_closing_balance',
        v_calculated_closing_balance::text,

        'closing_balance',
        v_closing_balance::text,

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

        'entries',
        v_entries
    );
end;
$function$;


revoke all on function
    public.fetch_my_gl_period_entries(
        text,
        text,
        integer,
        integer,
        integer,
        integer
    )
from public;

revoke all on function
    public.fetch_my_gl_period_entries(
        text,
        text,
        integer,
        integer,
        integer,
        integer
    )
from anon;

grant execute on function
    public.fetch_my_gl_period_entries(
        text,
        text,
        integer,
        integer,
        integer,
        integer
    )
to authenticated;