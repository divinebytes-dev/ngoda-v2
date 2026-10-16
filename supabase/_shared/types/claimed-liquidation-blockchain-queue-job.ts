export type ClaimedLiquidationBlockchainQueueJob = {
  queue_id: string;
  liquidation_job_id: string;

  user_id: string;
  wallet_index: string | number;

  treasury_id: string;
  sender_wallet_address: string;

  collateral: string;

  debt_repayment_amount: string;
  penalty_amount: string;
  total_liquidation_proceeds: string;
  total_debt: string;

  gold_price: string;

  document_number: string;

  fiscal_year: number;
  period: number;

  country_code: string;

  retry_count: number;
  attempt_count: number;

  manual_review_required: boolean;

  queue_status: string;

  blockchain_code: string;


  /*
   * When present, the blockchain transaction has already
   * been submitted. The processor must wait for this
   * transaction instead of sending another transfer.
   */
  tx_hash: string | null;

  claimed_at: string | null;
  lease_expires_at: string | null;

  signed_payload:
    Record<string, unknown> | null;
};