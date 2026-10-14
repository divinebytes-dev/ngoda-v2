begin;

alter table public.wallet_entry
    disable trigger wallet_entry_no_update;

update public.wallet_entry as we
set blockchain_code = w.blockchain_code
from public.wallet as w
where we.wallet_id = w.id
  and lower(we.currency_code) = 'gold'
  and we.blockchain_code is null
  and w.blockchain_code is not null;

alter table public.wallet_entry
    enable trigger wallet_entry_no_update;

commit;