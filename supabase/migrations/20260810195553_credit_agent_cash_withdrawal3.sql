/*
 * Principal portion funded by cash already held.
 */
insert into public.transaction_gl_mapping (
    transaction_type,
    component_type,
    debit_gl,
    credit_gl,
    is_active
)
select
    'credit_agent_cash_withdrawal'::public."TransactionType",
    'principal'::public."ComponentType",
    '2002000',
    '1008000',
    true
where not exists (
    select 1
    from public.transaction_gl_mapping mapping_record
    where mapping_record.transaction_type =
          'credit_agent_cash_withdrawal'::public."TransactionType"
      and mapping_record.component_type =
          'principal'::public."ComponentType"
);

/*
 * Principal portion funded from remaining credit float.
 */
insert into public.transaction_gl_mapping (
    transaction_type,
    component_type,
    debit_gl,
    credit_gl,
    is_active
)
select
    'credit_agent_cash_withdrawal'::public."TransactionType",
    'credit_agent_receivable'::public."ComponentType",
    '2002000',
    '1007000',
    true
where not exists (
    select 1
    from public.transaction_gl_mapping mapping_record
    where mapping_record.transaction_type =
          'credit_agent_cash_withdrawal'::public."TransactionType"
      and mapping_record.component_type =
          'credit_agent_receivable'::public."ComponentType"
);