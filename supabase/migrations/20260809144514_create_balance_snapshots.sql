create or replace function public.prepare_my_token_adjustment_execution(
    p_adjustment_request_id text
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
     * Preserve the existing treasury-role requirement.
     */
    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
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
     * Fetch the authenticated treasury user.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Lock the adjustment request so it cannot be claimed
     * concurrently.
     */
    select adjustment_record.*
    into v_request
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.id::text =
          btrim(
              p_adjustment_request_id
          )
    for update;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_FOUND';
    end if;

    /*
     * Only approved requests may reach the blockchain.
     */
    if v_request.status <>
       'approved'::public."AdjustmentStatus"
    then
        raise exception
            'ADJUSTMENT_REQUEST_NOT_APPROVED';
    end if;

    /*
     * A completed or partially completed request must not be
     * sent to the blockchain again.
     */
    if v_request.tx_hash is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_EXECUTED';
    end if;

    /*
     * executed_by acts as the execution claim while the
     * request remains approved.
     */
    if v_request.executed_by is not null then
        raise exception
            'ADJUSTMENT_REQUEST_ALREADY_CLAIMED';
    end if;

    if v_request.quantity is null
       or v_request.quantity <= 0
    then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_AMOUNT';
    end if;

    if v_request.adjustment_type not in (
        'minting'::public."TokenAdjustmentType",
        'burning'::public."TokenAdjustmentType"
    ) then
        raise exception
            'INVALID_TOKEN_ADJUSTMENT_TYPE';
    end if;

    /*
     * Claim the request before the blockchain call.
     *
     * executed_at is deliberately left null until accounting
     * has been completed successfully.
     */
    update public.tokenised_asset_adjustment_request
    set
        executed_by =
            v_user.id
    where id =
          v_request.id

      and status =
          'approved'::public."AdjustmentStatus"

      and executed_by is null

      and tx_hash is null;

    if not found then
        raise exception
            'ADJUSTMENT_REQUEST_CLAIM_FAILED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'adjustment_request_id',
        v_request.id::text,

        'document_number',
        v_request.document_number,

        'adjustment_type',
        v_request.adjustment_type,

        'quantity',
        v_request.quantity::text,

        'uom',
        v_request.uom,

        'currency_code',
        v_request.currency_code,

        'country_code',
        v_user.country_code,

        'executed_by',
        v_user.id
    );
end;
$function$;


create or replace function public.release_my_token_adjustment_execution(
    p_adjustment_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
    v_request_id text;
begin
    /*
     * Authenticate.
     */
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

    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null
    then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    v_user_id :=
        auth.uid()::text;

    /*
     * Release only the current user's claim and only when:
     *
     * - the request is still approved;
     * - no transaction hash has been attached;
     * - no pending blockchain record has been created.
     */
    update public.tokenised_asset_adjustment_request
    set
        executed_by =
            null
    where id::text =
          btrim(
              p_adjustment_request_id
          )

      and status =
          'approved'::public."AdjustmentStatus"

      and executed_by =
          v_user_id

      and tx_hash is null

      and not exists (
          select 1
          from public.blockchain_transaction
              blockchain_record
          where blockchain_record.reference =
                public.tokenised_asset_adjustment_request.id::text
      )
    returning id::text
    into v_request_id;

    if v_request_id is null then
        raise exception
            'ADJUSTMENT_EXECUTION_CLAIM_NOT_RELEASED';
    end if;

    return jsonb_build_object(
        'success',
        true,

        'adjustment_request_id',
        v_request_id,

        'released',
        true
    );
end;
$function$;


revoke all on function
    public.prepare_my_token_adjustment_execution(
        text
    )
from public;

revoke all on function
    public.prepare_my_token_adjustment_execution(
        text
    )
from anon;

grant execute on function
    public.prepare_my_token_adjustment_execution(
        text
    )
to authenticated;


revoke all on function
    public.release_my_token_adjustment_execution(
        text
    )
from public;

revoke all on function
    public.release_my_token_adjustment_execution(
        text
    )
from anon;

grant execute on function
    public.release_my_token_adjustment_execution(
        text
    )
to authenticated;

notify pgrst, 'reload schema';