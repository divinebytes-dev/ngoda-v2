import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import {
  AppError,
} from "../app-error.ts";

import type {
  ClaimedLiquidationAccountingJob,
} from "../types/claimed-liquidation-accounting-job.ts";

import type {
  ClaimedLiquidationAccountingJobsResult,
} from "../types/claimed-liquidation-accounting-jobs-result.ts";


function validateClaimedJob(
  value: unknown,
): value is ClaimedLiquidationAccountingJob {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return false;
  }

  const row =
    value as
      Record<string, unknown>;

  return (
    typeof row.job_id === "string" &&
    row.job_id.trim() !== "" &&
    typeof row.country_code === "string" &&
    row.country_code.trim() !== ""
  );
}


export async function claimLiquidationAccountingJobs(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    countryCode: string;
    batchSize?: number;
  },
): Promise<ClaimedLiquidationAccountingJobsResult> {
  const countryCode =
    input.countryCode
      .trim()
      .toLowerCase();

  if (!countryCode) {
    throw new AppError(
      "COUNTRY_CODE_REQUIRED",
    );
  }

  const batchSize =
    input.batchSize ?? 25;

  if (
    !Number.isSafeInteger(
      batchSize,
    ) ||
    batchSize < 1 ||
    batchSize > 100
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BATCH_SIZE",
    );
  }

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "claim_country_liquidation_accounting_jobs",
    {
      p_country_code:
        countryCode,

      p_batch_size:
        batchSize,
    },
  );

  if (error) {
    console.error(
      "CLAIM_LIQUIDATION_ACCOUNTING_JOBS_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        countryCode,

        batchSize,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_CLAIM_LIQUIDATION_ACCOUNTING_JOBS",
    );
  }

  if (
    typeof data !== "object" ||
    data === null ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_CLAIM_RESPONSE",
    );
  }

  const result =
    data as
      Partial<ClaimedLiquidationAccountingJobsResult>;

  const claimed =
    result.claimed;

  const jobs =
    result.jobs;

  if (
    result.success !== true ||
    typeof result.country_code !== "string" ||
    result.country_code
      .trim()
      .toLowerCase() !== countryCode ||
    typeof claimed !== "number" ||
    !Number.isSafeInteger(
      claimed,
    ) ||
    claimed < 0 ||
    !Array.isArray(
      jobs,
    ) ||
    !jobs.every(
      validateClaimedJob,
    )
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_CLAIM_RESPONSE",
    );
  }

  if (
    claimed !==
    jobs.length
  ) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_CLAIM_COUNT_MISMATCH",
    );
  }

  return {
    success:
      true,

    country_code:
      countryCode,

    claimed:
      claimed,

    jobs:
      jobs,
  };
}
