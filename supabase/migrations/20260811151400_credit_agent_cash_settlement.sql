create or replace function public.fetch_my_credit_agent_cash_settlement_context(
    p_v text,
    p_accounts_id text,
    p_currency_code text
)
returns table (
    merchant_id text,
    merchant_country_code text,
    merchant_wallet_address text,

    accounts_id text,
    accounts_country_code text,
    accounts_wallet_address text,

    treasury_id text,

    version_time integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_accounts_id text;
    v_currency_code text;
begin
    /*
     * Validate authentication.
     *
     * The merchant scans the accounts-generated
     * transaction, signs approval and submits it.
     */
    if auth.uid() is null then
        raise exception using
            errcode =
                '42501',

            message =
                'UNAUTHORIZED';
    end if;

    /*
     * Only an active merchant may submit the settlement
     * approval.
     */
    if not public.has_role(
        array[
            'merchant'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;

    if p_v is null
       or btrim(p_v) = ''
    then
        raise exception
            'TRANSACTION_VERSION_REQUIRED';
    end if;

    v_accounts_id :=
        nullif(
            btrim(p_accounts_id),
            ''
        );

    if v_accounts_id is null then
        raise exception
            'ACCOUNTS_ID_MISSING';
    end if;

    if auth.uid()::text =
       v_accounts_id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
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

    if v_currency_code = 'gold' then
        raise exception
            'INVALID_SETTLEMENT_CURRENCY';
    end if;

    /*
     * transaction.s must identify an accounts user.
     */
    if not public.user_has_role(
        v_accounts_id,
        array[
            'accounts'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'ACCOUNTS_USER_NOT_AUTHORIZED';
    end if;

    /*
     * Return trusted context:
     *
     * - authenticated merchant;
     * - accounts user who created TransactionData;
     * - country treasury resolved from merchant country;
     * - configured transaction-version lifetime.
     *
     * The credit_agent_account join confirms that the
     * merchant is an active credit agent for the signed
     * fiat currency.
     */
    return query
    select
        merchant_record.id,
        merchant_record.country_code,
        merchant_record.wallet_address,

        accounts_record.id,
        accounts_record.country_code,
        accounts_record.wallet_address,

        treasury_record.id,

        public.get_transaction_v(
            p_v
        )

    from public.users
        merchant_record

    join public.users
        accounts_record
      on accounts_record.id =
         v_accounts_id

    join public.credit_agent_account
        credit_account_record
      on credit_account_record.merchant_id =
         merchant_record.id

     and credit_account_record.country_code =
         merchant_record.country_code

     and lower(
         btrim(
             credit_account_record.currency_code
         )
     ) =
         v_currency_code

     and credit_account_record.is_active =
         true

    cross join lateral
        public.fetch_country_treasury(
            merchant_record.country_code
        ) as treasury_record

    where merchant_record.id =
          auth.uid()::text

      and merchant_record.status =
          'active'::public."UserStatus"

      and accounts_record.status =
          'active'::public."UserStatus"

      and merchant_record.country_code =
          accounts_record.country_code

    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_CASH_SETTLEMENT_CONTEXT_NOT_FOUND';
    end if;
end;
$function$;


revoke all on function
    public.fetch_my_credit_agent_cash_settlement_context(
        text,
        text,
        text
    )
from public;

revoke all on function
    public.fetch_my_credit_agent_cash_settlement_context(
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.fetch_my_credit_agent_cash_settlement_context(
        text,
        text,
        text
    )
to authenticated;