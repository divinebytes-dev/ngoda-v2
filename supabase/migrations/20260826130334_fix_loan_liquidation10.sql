begin;

insert into public.transaction_type_wallet_owner (
    transaction_type,
    sender_wallet_owner,
    receiver_wallet_owner,
    audit_action_type
)
select
    'loan_liquidation_sub_tx'::public."TransactionType",
    'customer'::public."WalletOwnerType",
    'treasury'::public."WalletOwnerType",
    'loan_liquidated'::public."AuditActionType"
where not exists (
    select 1
    from public.transaction_type_wallet_owner
    where transaction_type =
          'loan_liquidation_sub_tx'
              ::public."TransactionType"
);

update public.transaction_type_wallet_owner
set
    sender_wallet_owner =
        'customer'::public."WalletOwnerType",

    receiver_wallet_owner =
        'treasury'::public."WalletOwnerType",

    audit_action_type =
        'loan_liquidated'::public."AuditActionType"

where transaction_type =
      'loan_liquidation_sub_tx'
          ::public."TransactionType";

commit;