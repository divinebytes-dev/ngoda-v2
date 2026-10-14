CREATE OR REPLACE FUNCTION public.fetch_my_credit_agent_drilldown(
    p_merchant_id text,
    p_currency_code text,
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
    v_accounts public.users%rowtype;
    v_merchant public.users%rowtype;
    v_account public.credit_agent_account%rowtype;
    v_last_settlement public.credit_agent_entry%rowtype;

    v_currency_code text;
    v_page integer;
    v_page_size integer;
    v_offset integer;

    v_opening_receivable numeric := 0;
    v_opening_cash_holding numeric := 0;

    v_total_entries integer := 0;
    v_total_pages integer := 1;

    v_entries jsonb := '[]'::jsonb;
begin
    /*
     * Authentication and authorization.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    if nullif(
        btrim(p_merchant_id),
        ''
    ) is null
    then
        raise exception
            'MERCHANT_ID_REQUIRED';
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
            'CURRENCY_REQUIRED';
    end if;

    v_page :=
        coalesce(
            p_page,
            1
        );

    v_page_size :=
        coalesce(
            p_page_size,
            50
        );

    if v_page < 1 then
        raise exception
            'INVALID_PAGE';
    end if;

    if v_page_size < 1
       or v_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    v_offset :=
        (v_page - 1) *
        v_page_size;

    /*
     * Resolve the authenticated Accounts user.
     */
    select accounts_record.*
    into v_accounts
    from public.users accounts_record
    where accounts_record.id =
          auth.uid()::text

      and accounts_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'ACCOUNTS_USER_NOT_FOUND';
    end if;

    /*
     * Resolve the merchant in the Accounts user's country.
     */
    select merchant_record.*
    into v_merchant
    from public.users merchant_record
    join public.user_role role_record
      on role_record.id =
         merchant_record.role_id
    where merchant_record.id =
          btrim(p_merchant_id)

      and merchant_record.country_code =
          v_accounts.country_code

      and lower(
          role_record.name::text
      ) = 'merchant'
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    /*
     * Fetch the selected currency account.
     *
     * Inactive accounts remain available for reporting.
     */
    select account_record.*
    into v_account
    from public.credit_agent_account account_record
    where account_record.merchant_id =
          v_merchant.id

      and account_record.country_code =
          v_merchant.country_code

      and lower(
          btrim(
              account_record.currency_code
          )
      ) = v_currency_code
    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_FOUND';
    end if;

    /*
     * Find the most recent cash-settlement checkpoint for
     * this merchant and currency.
     */
    select entry_record.*
    into v_last_settlement
    from public.credit_agent_entry entry_record
    where entry_record.credit_agent_account_id =
          v_account.id

      and entry_record.transaction_type =
          'credit_agent_cash_settlement'::public."TransactionType"
    order by
        entry_record.created_at desc,
        entry_record.id desc
    limit 1;

    if found then
        /*
         * The balances immediately after settlement become
         * the opening position for this drilldown.
         */
        v_opening_receivable :=
            coalesce(
                v_last_settlement.receivable_balance_after,
                0
            );

        v_opening_cash_holding :=
            coalesce(
                v_last_settlement.cash_holding_balance_after,
                0
            );
    else
        /*
         * No settlement exists. Use the balances before the
         * first credit-agent entry as the opening position.
         */
        select
            coalesce(
                first_entry.receivable_balance_before,
                0
            ),

            coalesce(
                first_entry.cash_holding_balance_before,
                0
            )
        into
            v_opening_receivable,
            v_opening_cash_holding
        from public.credit_agent_entry first_entry
        where first_entry.credit_agent_account_id =
              v_account.id
        order by
            first_entry.created_at asc,
            first_entry.id asc
        limit 1;

        if not found then
            v_opening_receivable := 0;
            v_opening_cash_holding := 0;
        end if;
    end if;

    /*
     * Count entries after the most recent settlement.
     *
     * When there is no settlement, all account entries are
     * included.
     */
    select count(*)::integer
    into v_total_entries
    from public.credit_agent_entry entry_record
    where entry_record.credit_agent_account_id =
          v_account.id

      and (
          v_last_settlement.id is null

          or

          (
              entry_record.created_at,
              entry_record.id
          ) >
          (
              v_last_settlement.created_at,
              v_last_settlement.id
          )
      );

    v_total_pages :=
        greatest(
            1,
            ceil(
                v_total_entries::numeric /
                v_page_size
            )::integer
        );

    /*
     * Return chronological entries so each stored balance
     * reads naturally as a running balance.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                entry_record.id::text,

                'document_number',
                entry_record.document_number,

                'transaction_type',
                entry_record.transaction_type,

                'fiscal_year',
                entry_record.fiscal_year,

                'period',
                entry_record.period,

                'currency_code',
                lower(
                    entry_record.currency_code
                ),

                'debit_receivable',
                trim_scale(
                    entry_record.debit_receivable
                )::text,

                'credit_receivable',
                trim_scale(
                    entry_record.credit_receivable
                )::text,

                'debit_cash_holding',
                trim_scale(
                    entry_record.debit_cash_holding
                )::text,

                'credit_cash_holding',
                trim_scale(
                    entry_record.credit_cash_holding
                )::text,

                'receivable_balance_before',
                trim_scale(
                    entry_record.receivable_balance_before
                )::text,

                'receivable_running_balance',
                trim_scale(
                    entry_record.receivable_balance_after
                )::text,

                'cash_holding_balance_before',
                trim_scale(
                    entry_record.cash_holding_balance_before
                )::text,

                'cash_holding_running_balance',
                trim_scale(
                    entry_record.cash_holding_balance_after
                )::text,

                'created_by',
                entry_record.created_by,

                'created_at',
                entry_record.created_at
            )
            order by
                entry_record.created_at asc,
                entry_record.id asc
        ),
        '[]'::jsonb
    )
    into v_entries
    from (
        select account_entry.*
        from public.credit_agent_entry account_entry
        where account_entry.credit_agent_account_id =
              v_account.id

          and (
              v_last_settlement.id is null

              or

              (
                  account_entry.created_at,
                  account_entry.id
              ) >
              (
                  v_last_settlement.created_at,
                  v_last_settlement.id
              )
          )

        order by
            account_entry.created_at asc,
            account_entry.id asc

        offset v_offset
        limit v_page_size
    ) entry_record;

    return jsonb_build_object(
        'merchant',
        jsonb_build_object(
            'user_id',
            v_merchant.id,

            'email',
            v_merchant.email,

            'phone',
            v_merchant.phone,

            'first_name',
            v_merchant.first_name,

            'surname',
            v_merchant.surname,

            'address',
            v_merchant.address,

            'country_code',
            v_merchant.country_code
        ),

        'account',
        jsonb_build_object(
            'credit_agent_account_id',
            v_account.id::text,

            'currency_code',
            v_currency_code,

            'is_active',
            v_account.is_active,

            'current_receivable_balance',
            trim_scale(
                v_account.receivable_balance
            )::text,

            'current_cash_holding_balance',
            trim_scale(
                v_account.cash_holding_balance
            )::text
        ),

        'opening',
        jsonb_build_object(
            'receivable_balance',
            trim_scale(
                v_opening_receivable
            )::text,

            'cash_holding_balance',
            trim_scale(
                v_opening_cash_holding
            )::text,

            'last_settlement_document_number',
            v_last_settlement.document_number,

            'last_settlement_at',
            v_last_settlement.created_at
        ),

        'entries',
        v_entries,

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
        )
    );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.fetch_my_credit_agent_drilldown(
        text,
        text,
        integer,
        integer
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_credit_agent_drilldown(
        text,
        text,
        integer,
        integer
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_credit_agent_drilldown(
        text,
        text,
        integer,
        integer
    )
TO authenticated;