/* =========================================================
 * NOTIFICATION MESSAGE RESULT
 * ========================================================= */

create type public.notification_message as (
    notification_type public."NotificationType",
    title text,
    body text,
    payload jsonb
);


/* =========================================================
 * RENDER NOTIFICATION TEMPLATE
 * ========================================================= */

create or replace function public.render_notification_template(
    p_template text,
    p_payload jsonb
)
returns text
language plpgsql
immutable
strict
parallel safe
as $$
declare
    v_rendered text := p_template;
    v_key text;
    v_value text;
begin
    for v_key, v_value in
        select e.key, e.value
        from jsonb_each_text(p_payload) as e
    loop
        v_rendered := replace(
            v_rendered,
            '{{' || v_key || '}}',
            v_value
        );
    end loop;

    return v_rendered;
end;
$$;


/* =========================================================
 * CREATE NOTIFICATION MESSAGE
 * ========================================================= */

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
as $$
declare
    v_template public.notification_template%rowtype;
    v_payload jsonb;
begin
    select t.*
    into v_template
    from public.notification_template t
    where t.country_code = p_country_code
      and t.language_code = 'en'
      and t.transaction_type = p_transaction_type
      and t.audience = p_audience
    limit 1;

    if not found then
        raise exception
            'NOTIFICATION_TEMPLATE_NOT_FOUND_%',
            upper(p_transaction_type::text);
    end if;

    v_payload := jsonb_build_object(
        'quantity', p_quantity,
        'amount', p_amount,
        'currency', p_currency,
        'reference', p_reference
    );

    if p_sender is not null then
        v_payload := v_payload || jsonb_build_object(
            'sender',
            p_sender
        );
    end if;

    if p_receiver is not null then
        v_payload := v_payload || jsonb_build_object(
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
$$;