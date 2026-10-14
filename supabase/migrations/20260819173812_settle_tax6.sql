CREATE OR REPLACE FUNCTION public.fetch_my_government_tax_settlement_items(
    p_batch_id text,
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
    v_user public.users%rowtype;

    v_batch
        public.government_tax_settlement_batch%rowtype;

    v_batch_id text;

    v_offset integer;
    v_total_entries integer;
    v_total_pages integer;

    v_items jsonb :=
        '[]'::jsonb;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Accounts processes Government Tax settlements.
     * Finance reviews and approves/cancels them.
     */
    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    v_batch_id :=
        nullif(
            btrim(p_batch_id),
            ''
        );

    if v_batch_id is null then
        raise exception
            'SETTLEMENT_BATCH_ID_REQUIRED';
    end if;

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

    v_offset :=
        (p_page - 1) *
        p_page_size;

    /*
     * Fetch trusted user context.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
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
     * Fetch the requested tax settlement batch and
     * enforce country isolation.
     */
    select batch_record.*
    into v_batch
    from public.government_tax_settlement_batch
        batch_record
    where batch_record.id::text =
              v_batch_id

      and lower(
          btrim(
              batch_record.country_code
          )
      ) =
          lower(
              btrim(
                  v_user.country_code
              )
          )
    limit 1;

    if not found then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_BATCH_NOT_FOUND';
    end if;

    /*
     * Count all items belonging to the batch.
     */
    select count(*)::integer
    into v_total_entries
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
          v_batch.id;

    v_total_pages :=
        case
            when v_total_entries = 0
            then 1

            else ceil(
                v_total_entries::numeric /
                p_page_size::numeric
            )::integer
        end;

    /*
     * Fetch the requested page.
     *
     * Government Tax settlement items are grouped by
     * originating transaction type.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                paged_item.id,

                'batch_id',
                paged_item.batch_id,

                'transaction_type',
                paged_item.transaction_type,

                'fiscal_year',
                paged_item.fiscal_year,

                'period',
                paged_item.period,

                'currency_code',
                lower(
                    btrim(
                        paged_item.currency_code
                    )
                ),

                'gross_amount',
                trim_scale(
                    paged_item.gross_amount
                )::text,

                'tax_amount',
                trim_scale(
                    paged_item.tax_amount
                )::text,

                'status',
                paged_item.status
            )
            order by
                paged_item.transaction_type,
                paged_item.id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select item_record.*
        from public.government_tax_settlement_item
            item_record
        where item_record.batch_id =
              v_batch.id
        order by
            item_record.transaction_type,
            item_record.id
        offset v_offset
        limit p_page_size
    ) as paged_item;

    return jsonb_build_object(
        /*
         * Batch header.
         */
        'currency',
        lower(
            btrim(
                v_batch.currency_code
            )
        ),

        /*
         * This is the total Government Tax payable.
         */
        'totalAmount',
        trim_scale(
            v_batch.total_amount
        )::text,

        'totalItems',
        v_total_entries,

        /*
         * Paginated drill-down.
         */
        'items',
        v_items,

        'pagination',
        jsonb_build_object(
            'page',
            p_page,

            'page_size',
            p_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            p_page > 1,

            'has_next',
            p_page < v_total_pages
        )
    );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.fetch_my_government_tax_settlement_items(
        text,
        integer,
        integer
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_government_tax_settlement_items(
        text,
        integer,
        integer
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_government_tax_settlement_items(
        text,
        integer,
        integer
    )
TO authenticated;

NOTIFY pgrst, 'reload schema';