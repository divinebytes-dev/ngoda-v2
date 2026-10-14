CREATE OR REPLACE FUNCTION public.fetch_incomplete_blockchain_transactions(
    p_page integer DEFAULT 1,
    p_page_size integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_page integer;
    v_page_size integer;
    v_offset integer;

    v_total_entries bigint := 0;
    v_total_pages integer := 1;

    v_transactions jsonb :=
        '[]'::jsonb;
begin
    /*
     * Preserve the authorization behaviour of the existing
     * report: any authenticated application user may call
     * this RPC.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Validate pagination.
     */
    if p_page is null
       or p_page < 1
    then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    v_page :=
        p_page;

    v_page_size :=
        p_page_size;

    v_offset :=
        (v_page - 1) *
        v_page_size;

    /*
     * Combine the two incomplete-processing sources before
     * pagination:
     *
     * 1. General blockchain transactions that do not yet
     *    have an accounting document.
     *
     * 2. Liquidation jobs that have not reached completed,
     *    including jobs that have not created a blockchain
     *    transaction yet.
     *
     * source_type lets the frontend select the correct
     * detail model and actions for each row.
     */
    with incomplete_records as materialized (
        select
            blockchain_record.created_at
                as sort_created_at,

            blockchain_record.id::text
                as sort_id,

            to_jsonb(
                blockchain_record
            ) ||
            jsonb_build_object(
                'source_type',
                'blockchain_transaction',

                'record_id',
                blockchain_record.id,

                'record_status',
                coalesce(
                    to_jsonb(blockchain_record) ->>
                        'status',
                    to_jsonb(blockchain_record) ->>
                        'chain_status'
                ),

                'error_message',
                coalesce(
                    nullif(
                        to_jsonb(blockchain_record) ->>
                            'error_message',
                        ''
                    ),
                    nullif(
                        to_jsonb(blockchain_record) ->>
                            'reason',
                        ''
                    ),
                    nullif(
                        blockchain_record.description,
                        ''
                    )
                )
            ) as payload

        from public.blockchain_transaction
            blockchain_record

        where blockchain_record.document_number
              is null

        union all

        select
            liquidation_record.created_at
                as sort_created_at,

            liquidation_record.id::text
                as sort_id,

            jsonb_build_object(
                /*
                 * Common transaction fields retained for
                 * the existing frontend transaction list.
                 */
                'id',
                liquidation_record.id,

                'source_type',
                'liquidation_job',

                'record_id',
                liquidation_record.id,

                'liquidation_job_id',
                liquidation_record.id,

                'user_id',
                liquidation_record.user_id,

                'period',
                liquidation_record.period,

                'fiscal_year',
                liquidation_record.fiscal_year,

                'country_code',
                liquidation_record.country_code,

                'tx_hash',
                nullif(
                    to_jsonb(queue_record) ->>
                        'tx_hash',
                    ''
                ),

                'document_number',
                liquidation_record.document_number,

                'reference',
                liquidation_record.id,

                'transaction_type',
                'loan_liquidation',

                'sender',
                coalesce(
                    nullif(
                        to_jsonb(queue_record) ->>
                            'sender_wallet_address',
                        ''
                    ),
                    liquidation_record.user_id
                ),

                'receiver',
                nullif(
                    to_jsonb(queue_record) ->>
                        'receiver_wallet_address',
                    ''
                ),

                'quantity',
                trim_scale(
                    liquidation_record.collateral_required
                )::text,

                'gross_amount',
                trim_scale(
                    liquidation_record.total_debt
                )::text,

                'net_amount',
                trim_scale(
                    liquidation_record.repayment_required
                )::text,

                'fee_amount',
                trim_scale(
                    liquidation_record.penalty_amount
                )::text,

                'currency_code',
                'gold',

                'chain',
                'chiado',

                'chain_status',
                coalesce(
                    queue_record.status::text,
                    liquidation_record.status::text
                ),

                'record_status',
                liquidation_record.status::text,

                'description',
                coalesce(
                    nullif(
                        liquidation_record.error_message,
                        ''
                    ),
                    nullif(
                        to_jsonb(queue_record) ->>
                            'error_message',
                        ''
                    ),
                    nullif(
                        to_jsonb(queue_record) ->>
                            'reason',
                        ''
                    )
                ),

                'error_message',
                coalesce(
                    nullif(
                        liquidation_record.error_message,
                        ''
                    ),
                    nullif(
                        to_jsonb(queue_record) ->>
                            'error_message',
                        ''
                    ),
                    nullif(
                        to_jsonb(queue_record) ->>
                            'reason',
                        ''
                    )
                ),

                'explorer_url',
                nullif(
                    to_jsonb(queue_record) ->>
                        'explorer_url',
                    ''
                ),

                'created_by',
                'system',

                'created_at',
                liquidation_record.created_at,

                /*
                 * Liquidation-specific fields.
                 */
                'blockchain_queue_id',
                liquidation_record.blockchain_queue_id,

                'blockchain_status',
                queue_record.status,

                'retry_count',
                coalesce(
                    nullif(
                        to_jsonb(queue_record) ->>
                            'retry_count',
                        ''
                    )::integer,
                    0
                ),

                'total_principal',
                trim_scale(
                    liquidation_record.total_principal
                )::text,

                'total_interest',
                trim_scale(
                    liquidation_record.total_interest
                )::text,

                'total_debt',
                trim_scale(
                    liquidation_record.total_debt
                )::text,

                'penalty_amount',
                trim_scale(
                    liquidation_record.penalty_amount
                )::text,

                'repayment_required',
                trim_scale(
                    liquidation_record.repayment_required
                )::text,

                'collateral_required',
                trim_scale(
                    liquidation_record.collateral_required
                )::text,

                'gold_price',
                trim_scale(
                    liquidation_record.gold_price
                )::text,

                'email',
                user_record.email,

                'phone',
                user_record.phone,

                'first_name',
                user_record.first_name,

                'surname',
                user_record.surname
            ) as payload

        from public.liquidation_job
            liquidation_record

        left join public.users
            user_record
          on user_record.id =
             liquidation_record.user_id

        left join lateral (
            select queue_source.*
            from public.liquidation_blockchain_queue
                queue_source
            where queue_source.liquidation_job_id =
                  liquidation_record.id::text
            order by
                queue_source.id desc
            limit 1
        ) as queue_record
          on true

        where liquidation_record.status::text <>
              'completed'
    ),

    page_records as (
        select incomplete_record.*
        from incomplete_records
            incomplete_record
        order by
            incomplete_record.sort_created_at desc,
            incomplete_record.sort_id desc
        limit v_page_size
        offset v_offset
    )
    select
        (
            select count(*)::bigint
            from incomplete_records
        ),

        coalesce(
            (
                select jsonb_agg(
                    page_record.payload
                    order by
                        page_record.sort_created_at desc,
                        page_record.sort_id desc
                )
                from page_records
                    page_record
            ),
            '[]'::jsonb
        )
    into
        v_total_entries,
        v_transactions;

    v_total_pages :=
        case
            when v_total_entries = 0
                then 1
            else
                ceil(
                    v_total_entries::numeric /
                    v_page_size
                )::integer
        end;

    return jsonb_build_object(
        'transactions',
        v_transactions,

        'pagination',
        jsonb_build_object(
            'page',
            v_page,

            'page_size',
            v_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            v_page > 1,

            'has_next',
            v_page < v_total_pages
        )
    );
end;
$function$;
