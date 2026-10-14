create or replace function public.fetch_token_adjustments_by_status(
    p_status text
)
returns table(
    id text,
    document_number text,
    adjustment_type public."TokenAdjustmentType",
    quantity numeric,
    uom public."Uom",
    status public."AdjustmentStatus",
    description text,
    available_gold numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_status public."AdjustmentStatus";
    v_available_gold numeric := 0;
begin
    /*
     * Authenticate.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Only roles involved in Gold reserve management may
     * view token adjustment requests.
     */
    if not public.has_role(
        array[
            'accounts',
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate and cast the requested status.
     */
    if nullif(
        btrim(p_status),
        ''
    ) is null
    then
        raise exception
            'STATUS_IS_REQUIRED';
    end if;

    begin
        v_status :=
            lower(
                btrim(p_status)
            )::public."AdjustmentStatus";
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_ADJUSTMENT_STATUS_%',
                p_status;
    end;

    /*
     * Physical Gold is global because the blockchain token
     * supply is global.
     */
    select coalesce(
        sum(
            coalesce(
                asset_entry_record.credit,
                0
            ) -
            coalesce(
                asset_entry_record.debit,
                0
            )
        ),
        0
    )
    into v_available_gold
    from public.asset_entry
        asset_entry_record;

    /*
     * Fetch adjustment requests for any supplied valid status.
     */
    return query
    select
        adjustment_record.id::text,
        adjustment_record.document_number,
        adjustment_record.adjustment_type,
        adjustment_record.quantity,
        adjustment_record.uom,
        adjustment_record.status,
        adjustment_record.description,
        v_available_gold
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.status =
          v_status
    order by adjustment_record.created_at desc;
end;
$function$;


revoke all on function
    public.fetch_token_adjustments_by_status(
        text
    )
from public;

revoke all on function
    public.fetch_token_adjustments_by_status(
        text
    )
from anon;

grant execute on function
    public.fetch_token_adjustments_by_status(
        text
    )
to authenticated;

notify pgrst, 'reload schema';