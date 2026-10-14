CREATE OR REPLACE FUNCTION public.sync_my_credit_agent_currency_accounts(
    p_country_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_country_code text;
    v_inserted_count integer := 0;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_country_code :=
        lower(
            nullif(
                btrim(p_country_code),
                ''
            )
        );

    if v_country_code is null then
        raise exception
            'COUNTRY_CODE_REQUIRED';
    end if;

    /*
     * Create every missing active fiat-currency account
     * for merchants who are already approved credit agents.
     */
    insert into public.credit_agent_account (
        merchant_id,
        country_code,
        currency_code,
        receivable_balance,
        cash_holding_balance,
        is_active,
        approved_by,
        created_at,
        updated_at
    )
    select
        approved_merchant.merchant_id,
        v_country_code,
        lower(
            btrim(
                currency_record.currency_code
            )
        ),
        0,
        0,
        true,
        approved_merchant.approved_by,
        now(),
        now()
    from (
        /*
         * One row per already-approved merchant.
         */
        select distinct on (
            account_record.merchant_id
        )
            account_record.merchant_id,
            account_record.approved_by

        from public.credit_agent_account
            account_record

        where lower(
            btrim(
                account_record.country_code
            )
        ) =
            v_country_code

          and account_record.is_active =
              true

        order by
            account_record.merchant_id,
            account_record.updated_at desc
    ) approved_merchant

    cross join public.country_currencies
        currency_record

    where lower(
        btrim(
            currency_record.country_code
        )
    ) =
        v_country_code

      and currency_record.is_active =
          true

      and lower(
          btrim(
              currency_record.currency_code
          )
      ) <>
          'gold'

    on conflict (
        merchant_id,
        country_code,
        currency_code
    )
    do nothing;

    get diagnostics
        v_inserted_count =
            row_count;

    return jsonb_build_object(
        'success',
        true,

        'country_code',
        v_country_code,

        'accounts_created',
        v_inserted_count
    );
end;
$function$;