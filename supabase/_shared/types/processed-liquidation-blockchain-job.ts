export type ProcessedLiquidationBlockchainJob = {
  queue_id: string;
  liquidation_job_id: string;

  success: boolean;

  blockchain_confirmed: boolean;
  database_confirmed: boolean;

  tx_hash: string | null;

  error: string | null;
};