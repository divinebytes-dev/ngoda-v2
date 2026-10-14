alter type public."ComponentType"
add value if not exists
    'credit_agent_receivable';

alter type public."AuditActionType"
add value if not exists
    'credit_agent_cash_withdrawn';