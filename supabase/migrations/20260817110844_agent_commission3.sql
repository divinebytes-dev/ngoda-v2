CREATE OR REPLACE FUNCTION public.fetch_my_last_government_tax_settlement()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_fiscal_year integer;

    v_result jsonb :=
        '[]'::jsonb;
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
     * Fetch the current fiscal year.
     */
    select fiscal_period.fiscal_year
    into v_fiscal_year
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Return every currency having Government Tax
     * payable entries during the current fiscal year.
     *
     * For every currency, fetch its latest settled tax
     * batch in the Accounts user's country.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'currency_code',
                currency_record.currency_code,

                'start_date',
                settlement_record.start_date,

                'end_date',
                settlement_record.end_date,

                'next_start_date',
                case
                    when settlement_record.end_date
                         is not null
                    then
                        settlement_record.end_date::date +
                        1
                    else
                        null
                end,

                'batch_id',
                settlement_record.batch_id,

                'document_number',
                settlement_record.document_number
            )
            order by
                currency_record.currency_code
        ),
        '[]'::jsonb
    )
    into v_result
    from (
        select distinct
            lower(
                btrim(
                    tax_record.currency_code
                )
            ) as currency_code

        from public.government_tax_payable
            tax_record

        where tax_record.fiscal_year =
                  v_fiscal_year

          and lower(
              btrim(
                  tax_record.country_code
              )
          ) =
              lower(
                  btrim(
                      v_user.country_code
                  )
              )

          and nullif(
              btrim(
                  tax_record.currency_code
              ),
              ''
          ) is not null
    ) as currency_record

    left join lateral (
        select
            batch_record.id as batch_id,

            batch_record.document_number,

            batch_record.start_date,

            batch_record.end_date

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
              currency_record.currency_code

          and batch_record.status =
              'settled'

        order by
            batch_record.end_date desc,
            batch_record.created_at desc,
            batch_record.id desc

        limit 1
    ) as settlement_record
      on true;

    return v_result;
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_my_last_government_tax_settlement()
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_last_government_tax_settlement()
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_last_government_tax_settlement()
TO authenticated;