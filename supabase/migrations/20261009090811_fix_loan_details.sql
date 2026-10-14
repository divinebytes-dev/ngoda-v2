CREATE OR REPLACE FUNCTION public.fetch_my_active_loan_detail(
    p_loan_id text,
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_loan public.loan%rowtype;

    v_entries jsonb := '[]'::jsonb;

    v_page integer;
    v_page_size integer;
    v_offset bigint;

    v_total_entries bigint := 0;
    v_total_pages bigint := 0;

    v_has_previous boolean := false;
    v_has_next boolean := false;

    v_debit_principal numeric := 0;
    v_credit_principal numeric := 0;
    v_debit_interest numeric := 0;
    v_credit_interest numeric := 0;

    v_principal_balance numeric := 0;
    v_interest_balance numeric := 0;
    v_outstanding_balance numeric := 0;
begin
    /*
     * Authenticate and authorize customer.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id = auth.uid()::text
    limit 1;

    if not found then
        raise exception 'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception 'USER_NOT_ACTIVE';
    end if;

    /*
     * Validate loan ID.
     */
    if p_loan_id is null
       or btrim(p_loan_id) = ''
    then
        raise exception 'LOAN_ID_UNDEFINED';
    end if;

    /*
     * Validate pagination parameters.
     */
    if p_page is null or p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
    then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    v_page := p_page;
    v_page_size := p_page_size;

    v_offset :=
        (v_page::bigint - 1) *
        v_page_size::bigint;

    /*
     * Fetch only an active loan belonging
     * to the authenticated customer.
     */
    select loan_record.*
    into v_loan
    from public.loan loan_record
    where loan_record.id = btrim(p_loan_id)
      and loan_record.user_id = v_user.id
      and loan_record.status =
          'active'::public."LoanStatus"
    limit 1;

    if not found then
        raise exception 'ACTIVE_LOAN_NOT_FOUND';
    end if;

    /*
     * Count all loan entries and calculate
     * financial totals across the entire loan.
     *
     * These totals must NOT be affected
     * by pagination.
     */
    select
        count(*),

        coalesce(
            sum(
                loan_entry_record.debit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.credit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.debit_interest
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.credit_interest
            ),
            0
        )
    into
        v_total_entries,
        v_debit_principal,
        v_credit_principal,
        v_debit_interest,
        v_credit_interest
    from public.loan_entry loan_entry_record
    where loan_entry_record.loan_id = v_loan.id;

    /*
     * Calculate total pages.
     */
    v_total_pages :=
        case
            when v_total_entries = 0 then 1
            else
                (
                    v_total_entries +
                    v_page_size::bigint - 1
                ) / v_page_size::bigint
        end;

    /*
     * Determine pagination navigation.
     */
    v_has_previous :=
        v_page > 1;

    v_has_next :=
        v_page < v_total_pages;

    /*
     * Fetch ONLY the requested page.
     *
     * Newest entries first.
     *
     * The ID provides deterministic
     * ordering when timestamps are equal.
     *
     * Amounts remain strings to preserve
     * the existing response format.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'created_at',
                paged_entry.created_at,

                'entry_type',
                paged_entry.entry_type::text,

                'debit_principal',
                coalesce(
                    paged_entry.debit_principal,
                    0
                )::text,

                'credit_principal',
                coalesce(
                    paged_entry.credit_principal,
                    0
                )::text,

                'debit_interest',
                coalesce(
                    paged_entry.debit_interest,
                    0
                )::text,

                'credit_interest',
                coalesce(
                    paged_entry.credit_interest,
                    0
                )::text,

                'accrual_date',
                paged_entry.accrual_date
            )
            order by
                paged_entry.created_at desc,
                paged_entry.id desc
        ),
        '[]'::jsonb
    )
    into v_entries
    from (
        select
            loan_entry_record.id,
            loan_entry_record.created_at,
            loan_entry_record.entry_type,
            loan_entry_record.debit_principal,
            loan_entry_record.credit_principal,
            loan_entry_record.debit_interest,
            loan_entry_record.credit_interest,
            loan_entry_record.accrual_date
        from public.loan_entry loan_entry_record
        where loan_entry_record.loan_id = v_loan.id
        order by
            loan_entry_record.created_at desc,
            loan_entry_record.id desc
        limit v_page_size
        offset v_offset
    ) paged_entry;

    /*
     * Calculate balances from ALL
     * loan entries.
     */
    v_principal_balance :=
        v_debit_principal -
        v_credit_principal;

    v_interest_balance :=
        v_debit_interest -
        v_credit_interest;

    v_outstanding_balance :=
        v_principal_balance +
        v_interest_balance;

    /*
     * Return paginated entries,
     * complete financial totals,
     * complete balances and
     * pagination metadata.
     */
    return jsonb_build_object(
        'entries',
        v_entries,

        'totals',
        jsonb_build_object(
            'debit_principal',
            v_debit_principal,

            'credit_principal',
            v_credit_principal,

            'debit_interest',
            v_debit_interest,

            'credit_interest',
            v_credit_interest
        ),

        'balances',
        jsonb_build_object(
            'principal_balance',
            v_principal_balance,

            'interest_balance',
            v_interest_balance,

            'outstanding_balance',
            v_outstanding_balance
        ),

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
            v_has_previous,

            'has_next',
            v_has_next
        )
    );
end;
$function$;