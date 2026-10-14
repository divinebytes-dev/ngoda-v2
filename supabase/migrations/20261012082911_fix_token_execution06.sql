CREATE OR REPLACE FUNCTION public.release_my_token_adjustment_execution(
    p_adjustment_request_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_request_id text;
begin
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * ==========================================================
     * ROLE AUTHORIZATION
     * ==========================================================
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
     * ==========================================================
     * VALIDATE REQUEST IDENTIFIER
     * ==========================================================
     */
    if nullif(
        btrim(p_adjustment_request_id),
        ''
    ) is null then
        raise exception
            'ADJUSTMENT_REQUEST_ID_REQUIRED';
    end if;

    /*
     * ==========================================================
     * FETCH AUTHENTICATED TREASURY USER
     * ==========================================================
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if nullif(
        btrim(v_user.country_code),
        ''
    ) is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * ==========================================================
     * RELEASE EXECUTION CLAIM
     * ==========================================================
     *
     * The claim can only be released when:
     *
     * 1. The request is approved.
     * 2. The claim belongs to the current treasury user.
     * 3. The request belongs to the user's country.
     * 4. No transaction hash has been recorded.
     * 5. No blockchain transaction record exists.
     *
     * The Edge Function must only invoke this RPC when
     * blockchain execution has not started.
     */

    update public.tokenised_asset_adjustment_request
    set
        executed_by = null
    where id::text =
        btrim(p_adjustment_request_id)

      and status =
        'approved'::public."AdjustmentStatus"

      and executed_by =
        v_user.id

      and country_code =
        v_user.country_code

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

    /*
     * ==========================================================
     * VALIDATE RELEASE
     * ==========================================================
     */
    if v_request_id is null then
        raise exception
            'ADJUSTMENT_EXECUTION_CLAIM_NOT_RELEASED';
    end if;

    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     */
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