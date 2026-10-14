alter type public."AuditActionType"
add value if not exists
    'credit_agent_funded';

    alter type public."AuditActionType"
add value if not exists
    'credit_agent_funding_reversed';