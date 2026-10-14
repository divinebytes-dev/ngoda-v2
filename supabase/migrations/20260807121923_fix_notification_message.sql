create or replace function public.create_notification_message(
    p_country_code text,
    p_transaction_type public."TransactionType",
    p_audience public."NotificationAudience",
    p_amount numeric,
    p_currency text,
    p_reference text,
    p_quantity numeric default 0,
    p_sender text default null,
    p_receiver text default null
)
returns public.notification_message
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_template
        public.notification_template%rowtype;

    v_payload jsonb;

    v_formatted_amount numeric;
    v_formatted_quantity numeric;
begin
    /*
     * Fetch the notification template.
     */
    select template_record.*
    into v_template
    from public.notification_template
        template_record
    where template_record.country_code =
          p_country_code
      and template_record.language_code =
          'en'
      and template_record.transaction_type =
          p_transaction_type
      and template_record.audience =
          p_audience
    limit 1;

    if not found then
        raise exception
            'NOTIFICATION_TEMPLATE_NOT_FOUND_%',
            upper(
                p_transaction_type::text
            );
    end if;

    /*
     * Currency amount formatting:
     *
     * - Gold: 6 decimal places
     * - Fiat: 2 decimal places
     */
    if lower(
        btrim(
            coalesce(
                p_currency,
                ''
            )
        )
    ) = 'gold'
    then
        v_formatted_amount :=
            round(
                coalesce(
                    p_amount,
                    0
                ),
                6
            );
    else
        v_formatted_amount :=
            round(
                coalesce(
                    p_amount,
                    0
                ),
                2
            );
    end if;

    /*
     * Quantity represents Gold grams in Gold transactions,
     * so it always uses 6 decimal places.
     */
    v_formatted_quantity :=
        round(
            coalesce(
                p_quantity,
                0
            ),
            6
        );

    /*
     * Build the consistently formatted notification payload.
     */
    v_payload :=
        jsonb_build_object(
            'quantity',
            v_formatted_quantity,

            'amount',
            v_formatted_amount,

            'currency',
            p_currency,

            'reference',
            p_reference
        );

    if p_sender is not null then
        v_payload :=
            v_payload ||
            jsonb_build_object(
                'sender',
                p_sender
            );
    end if;

    if p_receiver is not null then
        v_payload :=
            v_payload ||
            jsonb_build_object(
                'receiver',
                p_receiver
            );
    end if;

    return row(
        v_template.notification_type,

        public.render_notification_template(
            v_template.title_template,
            v_payload
        ),

        public.render_notification_template(
            v_template.body_template,
            v_payload
        ),

        v_payload
    )::public.notification_message;
end;
$function$;