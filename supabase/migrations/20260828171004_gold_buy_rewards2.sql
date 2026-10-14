/*
 * Gold Buy earns points.
 * Gold Sell, Gold Transfer and Cash Withdrawal do not earn points.
 *
 * The event type is retained for historical rows and reversals. Only its
 * earning rule is disabled.
 */

begin;

update public.loyalty_rule
set
    is_active = false,
    updated_at = now()
where event_type =
      'gold_token_sell'::public."LoyaltyEventType"
   or rule_code = 'gold_token_sell_standard';

commit;

select
    event_type,
    rule_code,
    is_active
from public.loyalty_rule
where event_type in (
    'gold_token_buy'::public."LoyaltyEventType",
    'gold_token_sell'::public."LoyaltyEventType"
)
order by event_type, rule_code;
