import type {
  ClaimedLiquidationAccountingJob,
} from "./claimed-liquidation-accounting-job.ts";


export type ClaimedLiquidationAccountingJobsResult = {
  success: boolean;

  country_code: string;

  claimed: number;

  jobs:
    ClaimedLiquidationAccountingJob[];
};