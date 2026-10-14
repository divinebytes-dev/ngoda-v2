create or replace function public.update_token_adjustment_request_status(
    p_adjustment_request_id text,
    p_status text,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_request
        public.tokenised_asset_adjustment_request%rowtype;

    v_status
        public."AdjustmentStatus";

    v_audit_action
        public."AuditActionType";

    v_fiscal_year integer;
    v_period integer;
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
     * Preserve the existing accounts-role requirement.
     */
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
     * Validate request identifier.
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null
    then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    /*
     * Only approved and rejected are valid review outcomes.
     */
    if lower(
        coalesce(
            btrim(p_status),
            ''
        )
    ) not in (
        'approved',
        'rejected'
    )
    then
        raise exception
            'INVALID_ADJUSTMENT_STATUS';
    end if;

    v_status :=
        lower(
            btrim(p_status)
        )::public."AdjustmentStatus";

    /*
     * Fetch the authenticated accounts user.
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
     * Lock the adjustment request to prevent two reviewers
     * from processing it concurrently.
     */
    select adjustment_record.*
    into v_request
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.id::text =
          btrim(p_adjustment_request_id)
    for update;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_FOUND';
    end if;

    if v_request.status <>
       'pending'::public."AdjustmentStatus"
    then
        raise exception
            'INVALID_ADJUSTMENT_STATUS';
    end if;

    /*
     * Fetch the fiscal period for the reviewing user's country.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Determine the correct audit action.
     */
    v_audit_action :=
        case
            when v_request.adjustment_type =
                 'minting'::public."TokenAdjustmentType"
             and v_status =
                 'approved'::public."AdjustmentStatus"
            then
                'minting_approved'::public."AuditActionType"

            when v_request.adjustment_type =
                 'minting'::public."TokenAdjustmentType"
             and v_status =
                 'rejected'::public."AdjustmentStatus"
            then
                'minting_rejected'::public."AuditActionType"

            when v_request.adjustment_type =
                 'burning'::public."TokenAdjustmentType"
             and v_status =
                 'approved'::public."AdjustmentStatus"
            then
                'burning_approved'::public."AuditActionType"

            when v_request.adjustment_type =
                 'burning'::public."TokenAdjustmentType"
             and v_status =
                 'rejected'::public."AdjustmentStatus"
            then
                'burning_rejected'::public."AuditActionType"

            else
                null
        end;

    if v_audit_action is null then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE_%',
            v_request.adjustment_type;
    end if;

    /*
     * Update the request.
     *
     * approved_by and approved_at are the existing schema
     * fields and therefore also record the rejection reviewer.
     */
    update public.tokenised_asset_adjustment_request
    set
        status =
            v_status,

        approved_by =
            v_user.id,

        approved_at =
            now()
    where id =
          v_request.id;

    /*
     * Create audit log.
     */
    insert into public.audit_log (
        fiscal_year,
        country_code,
        period,
        document_number,
        user_id,
        action_type,
        entity_type,
        entity_id,
        metadata
    )
    values (
        v_fiscal_year,
        v_user.country_code,
        v_period,
        v_request.document_number,
        v_user.id,
        v_audit_action,
        'adjustment_request',
        v_request.id::text,

        jsonb_build_object(
            'status',
            v_status,

            'adjustment_type',
            v_request.adjustment_type,

            'quantity',
            v_request.quantity::text,

            'description',
            v_request.description,

            'ip_address',
            p_ip_address
        )
    );

    return jsonb_build_object(
        'success',
        true,

        'adjustment_request_id',
        v_request.id::text,

        'document_number',
        v_request.document_number,

        'adjustment_type',
        v_request.adjustment_type,

        'status',
        v_status,

        'audit_action',
        v_audit_action
    );
end;
$function$;


revoke all on function
    public.update_token_adjustment_request_status(
        text,
        text,
        text
    )
from public;

revoke all on function
    public.update_token_adjustment_request_status(
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.update_token_adjustment_request_status(
        text,
        text,
        text
    )
to authenticated;

alter type public."AuditActionType"
    add value if not exists 'minting_rejected';

alter type public."AuditActionType"
    add value if not exists 'burning_rejected';
    
notify pgrst, 'reload schema';