create or replace function public.get_my_last_wallet_transactions(
    p_start_date timestamptz,
    p_end_date timestamptz,
    p_currency_code text default null,
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_user_id text;
begin
    /*
     * Required-role validation remains.
     */
    if not public.has_role(
        array[
            'admin',
            'agent',
            'vendor',
            'finance',
            'treasury',
            'customer',
            'merchant',
            'accounts'
        ]
    ) then
        raise exception 'FORBIDDEN';
    end if;

    /*
     * Use the authenticated user's ID.
     * The caller cannot provide another user's ID.
     */
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception 'UNAUTHORIZED';
    end if;

    return public.get_last_wallet_transactions(
        v_user_id,
        p_start_date,
        p_end_date,
        p_currency_code,
        p_page,
        p_page_size
    );
end;
$$;

grant execute on function public.get_my_last_wallet_transactions(
    timestamptz,
    timestamptz,
    text,
    integer,
    integer
) to authenticated;