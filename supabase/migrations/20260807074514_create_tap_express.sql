/*
 * ============================================================
 * EXPRESS TAP LIMITS
 *
 * Maximum payment amount that can be processed without
 * sender approval.
 * ============================================================
 */

create or replace function public.fetch_my_express_tap_limits()
returns table (
    currency_code text,
    express_tap_limit numeric,
    is_active boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer',
            'treasury',
            'finance',
            'agent',
            'admin',
            'accounts',
            'merchant',
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
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.country_code is null
       or btrim(
           v_user.country_code
       ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    return query
    select
        lower(
            btrim(
                config_record.currency_code
            )
        ) as currency_code,

        config_record.max_amount::numeric
            as express_tap_limit,

        config_record.is_active

    from public.maximum_tap_payment_amount_config
        config_record

    where lower(
        btrim(
            config_record.country_code
        )
    ) = lower(
        btrim(
            v_user.country_code
        )
    )

      and config_record.is_active =
          true

    order by
        lower(
            btrim(
                config_record.currency_code
            )
        );
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.fetch_my_express_tap_limits()
owner to postgres;

revoke all
on function public.fetch_my_express_tap_limits()
from public, anon, authenticated, service_role;

grant execute
on function public.fetch_my_express_tap_limits()
to authenticated;