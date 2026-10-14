create or replace function public.fetch_my_financial_document(
    p_document_number text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_document_number text;

    v_first_entry
        public.financial_entry%rowtype;

    v_reversal_document_number text;

    v_total_debit numeric := 0;
    v_total_credit numeric := 0;

    v_journal jsonb :=
        '[]'::jsonb;

    v_wallet jsonb :=
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
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_document_number :=
        nullif(
            btrim(p_document_number),
            ''
        );

    if v_document_number is null then
        raise exception
            'ENTER_DOCUMENT_NUMBER';
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
     * Fetch the first financial entry for the document.
     */
    select financial_entry_record.*
    into v_first_entry
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.document_number =
          v_document_number

      and financial_entry_record.country_code =
          v_user.country_code
    order by
        financial_entry_record.created_at asc,
        financial_entry_record.id asc
    limit 1;

    if not found then
        raise exception
            'DOCUMENT_NOT_FOUND';
    end if;

    /*
     * Find a reversal document whose reference points to this
     * document.
     */
    select financial_entry_record.document_number
    into v_reversal_document_number
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.reference =
          v_document_number

      and financial_entry_record.document_number <>
          v_document_number

      and financial_entry_record.country_code =
          v_user.country_code
    order by
        financial_entry_record.created_at asc,
        financial_entry_record.document_number asc
    limit 1;

    /*
     * Calculate financial-entry totals.
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
        v_total_debit,
        v_total_credit
    from public.financial_entry
        financial_entry_record
    where financial_entry_record.document_number =
          v_document_number

      and financial_entry_record.country_code =
          v_user.country_code;

    /*
     * Build journal lines.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                journal_line.id,

                'period',
                journal_line.period,

                'fiscal_year',
                journal_line.fiscal_year,

                'line_number',
                journal_line.line_number::text,

                'document_number',
                journal_line.document_number,

                'transaction_type',
                journal_line.transaction_type,

                'currency_code',
                journal_line.currency_code,

                'gl_account_code',
                journal_line.gl_account_code,

                'gl_account_name',
                journal_line.gl_account_name,

                'debit',
                journal_line.debit::text,

                'credit',
                journal_line.credit::text,

                'created_at',
                journal_line.created_at
            )
            order by
                journal_line.line_number
        ),
        '[]'::jsonb
    )
    into v_journal
    from (
        select
            financial_entry_record.id,
            financial_entry_record.period,
            financial_entry_record.fiscal_year,
            financial_entry_record.document_number,
            financial_entry_record.transaction_type,
            financial_entry_record.currency_code,
            financial_entry_record.gl_account_code,

            coalesce(
                gl_account_record.description,
                ''
            ) as gl_account_name,

            financial_entry_record.debit,
            financial_entry_record.credit,
            financial_entry_record.created_at,

            row_number() over (
                order by
                    financial_entry_record.created_at asc,
                    financial_entry_record.id asc
            ) as line_number
        from public.financial_entry
            financial_entry_record
        left join public.gl_account
            gl_account_record
          on gl_account_record.code =
             financial_entry_record.gl_account_code
        where financial_entry_record.document_number =
              v_document_number

          and financial_entry_record.country_code =
              v_user.country_code
    ) as journal_line;

    /*
     * Build wallet lines and resolve wallet owner types.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                wallet_line.id,

                'period',
                wallet_line.period,

                'fiscal_year',
                wallet_line.fiscal_year,

                'line_number',
                wallet_line.line_number::text,

                'document_number',
                wallet_line.document_number,

                'transaction_type',
                wallet_line.transaction_type,

                'currency_code',
                wallet_line.currency_code,

                'wallet_id',
                wallet_line.wallet_id,

                'wallet_owner',
                wallet_line.wallet_owner,

                'debit',
                wallet_line.debit::text,

                'credit',
                wallet_line.credit::text,

                'created_at',
                wallet_line.created_at
            )
            order by
                wallet_line.line_number
        ),
        '[]'::jsonb
    )
    into v_wallet
    from (
        select
            wallet_entry_record.id,
            wallet_entry_record.period,
            wallet_entry_record.fiscal_year,
            wallet_entry_record.document_number,
            wallet_entry_record.transaction_type,
            wallet_entry_record.currency_code,
            wallet_entry_record.wallet_id,

            coalesce(
                wallet_record.owner_type::text,
                ''
            ) as wallet_owner,

            wallet_entry_record.debit,
            wallet_entry_record.credit,
            wallet_entry_record.created_at,

            row_number() over (
                order by
                    wallet_entry_record.created_at asc,
                    wallet_entry_record.id asc
            ) as line_number
        from public.wallet_entry
            wallet_entry_record
        left join public.wallet
            wallet_record
          on wallet_record.id =
             wallet_entry_record.wallet_id
        where wallet_entry_record.document_number =
              v_document_number

          and wallet_entry_record.country_code =
              v_user.country_code
    ) as wallet_line;

    /*
     * Return the complete document.
     */
    return jsonb_build_object(
        'document_number',
        v_document_number,

        'reversal_document_number',
        v_reversal_document_number,

        'transaction_type',
        v_first_entry.transaction_type,

        'currency',
        v_first_entry.currency_code,

        'created_at',
        v_first_entry.created_at,

        'total_debit',
        v_total_debit::text,

        'total_credit',
        v_total_credit::text,

        'balanced',
        v_total_debit =
            v_total_credit,

        'journal',
        v_journal,

        'wallet',
        v_wallet
    );
end;
$function$;


revoke all on function
    public.fetch_my_financial_document(
        text
    )
from public;

revoke all on function
    public.fetch_my_financial_document(
        text
    )
from anon;

grant execute on function
    public.fetch_my_financial_document(
        text
    )
to authenticated;