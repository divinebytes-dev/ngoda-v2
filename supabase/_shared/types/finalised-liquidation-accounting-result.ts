type CompletedLiquidationAccountingResult = {
  success: true;

  already_completed: true;

  job_id: string;
  document_number: string;

  status: string;
};


type NewlyFinalisedLiquidationAccountingResult = {
  success: true;

  already_completed: false;

  job_id: string;
  document_number: string;

  blockchain_tx_hash: string;

  principal_paid: string;
  interest_paid: string;

  debt_repayment: string;
  penalty_amount: string;
  total_proceeds: string;

  collateral_transferred: string;

  status: string;
};


export type FinalisedLiquidationAccountingResult =
  | CompletedLiquidationAccountingResult
  | NewlyFinalisedLiquidationAccountingResult;