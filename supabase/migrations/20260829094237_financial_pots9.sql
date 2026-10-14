CREATE TYPE financial_activity_type AS ENUM (
  'deposit',
  'withdrawal',
  'spending',

  'investment_buy',
  'investment_sell',
  'investment_transfer_in',
  'investment_transfer_out',

  'loan_disbursement',
  'loan_repayment'
);

