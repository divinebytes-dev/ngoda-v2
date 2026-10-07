import type {
  ClaimedLiquidationBlockchainQueueJob,
} from "./claimed-liquidation-blockchain-queue-job.ts";


export type ClaimedLiquidationJobs = {
  success: boolean;

  country_code: string;

  claimed: number;

  jobs:
    ClaimedLiquidationBlockchainQueueJob[];
};