export type PreparedLiquidationBlockchainJob = {
  job_id: string;
  queue_id: string;

  document_number: string;

  user_id: string;

  currency_code: string;
  blockchain_code: string;  
  collateral: string;
  sender_wallet_address: string;
  receiver_wallet_address: string;
};


export type PreparedLiquidationBlockchainJobsResult = {
  success: boolean;

  country_code: string;

  prepared: number;
  already_prepared: number;
  failed: number;

  error_message: string | null;

  jobs:
    PreparedLiquidationBlockchainJob[];
};