CREATE OR REPLACE FUNCTION public.fetch_my_last_agent_commission_settlement()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_fiscal_year integer;
    v_fiscal_year_start date;

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
     * Fetch the beginning of the current fiscal year.
     *
     * This becomes next_start_date when the currency has
     * never had a settlement batch.
     */
    select min(
        fiscal_period_record.opening_date
    )::date
    into v_fiscal_year_start
    from public.fiscal_period_config
        fiscal_period_record
    where fiscal_period_record.country_code =
              v_user.country_code

      and fiscal_period_record.fiscal_year =
              v_fiscal_year;

    if v_fiscal_year_start is null then
        raise exception
            'FISCAL_YEAR_START_NOT_FOUND';
    end if;

    /*
     * Return every currency having commission entries in
     * the current fiscal year.
     *
     * The latest batch is returned regardless of status,
     * because a draft batch has already reserved the
     * commission entries and must prevent another batch.
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
                        v_fiscal_year_start
                end,

                'batch_id',
                settlement_record.batch_id,

                'document_number',
                settlement_record.document_number,

                'status',
                settlement_record.status,

                'payment_underway',
                case
                    when settlement_record.batch_id
                         is null
                    then
                        false

                    when settlement_record.status::text <>
                         'settled'
                    then
                        true

                    else
                        false
                end
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
                    commission_record.currency_code
                )
            ) as currency_code

        from public.agent_commission
            commission_record

        where commission_record.fiscal_year =
                  v_fiscal_year

          and lower(
              btrim(
                  commission_record.country_code
              )
          ) =
              lower(
                  btrim(
                      v_user.country_code
                  )
              )

          and nullif(
              btrim(
                  commission_record.currency_code
              ),
              ''
          ) is not null
    ) as currency_record

    left join lateral (
        select
            batch_record.id as batch_id,

            batch_record.document_number,

            batch_record.start_date,

            batch_record.end_date,

            batch_record.status

        from public.agent_settlement_batch
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
    v_fiscal_year_start date;

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
     * Fetch the beginning of the current fiscal year.
     */
    select min(
        fiscal_period_record.opening_date
    )::date
    into v_fiscal_year_start
    from public.fiscal_period_config
        fiscal_period_record
    where fiscal_period_record.country_code =
              v_user.country_code

      and fiscal_period_record.fiscal_year =
              v_fiscal_year;

    if v_fiscal_year_start is null then
        raise exception
            'FISCAL_YEAR_START_NOT_FOUND';
    end if;

    /*
     * Return every currency having Government Tax
     * payable entries in the current fiscal year.
     *
     * Draft and other unfinished batches are returned so
     * Accounts can see that payment is underway.
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
                        v_fiscal_year_start
                end,

                'batch_id',
                settlement_record.batch_id,

                'document_number',
                settlement_record.document_number,

                'status',
                settlement_record.status,

                'payment_underway',
                case
                    when settlement_record.batch_id
                         is null
                    then
                        false

                    when settlement_record.status::text <>
                         'settled'
                    then
                        true

                    else
                        false
                end
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

            batch_record.end_date,

            batch_record.status

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