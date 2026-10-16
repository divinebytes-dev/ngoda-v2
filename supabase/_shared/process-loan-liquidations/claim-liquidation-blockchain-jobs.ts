import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import type {
  ClaimedLiquidationBlockchainQueueJob,
} from "../types/claimed-liquidation-blockchain-queue-job.ts";

import type {
  ClaimedLiquidationJobs,
} from "../types/claimed-liquidation-jobs.ts";


function isNonEmptyString(
  value: unknown,
): value is string {
  return (
    typeof value === "string" &&
    value.trim() !== ""
  );
}


function isNullableString(
  value: unknown,
): value is string | null {
  return (
    value === null ||
    typeof value === "string"
  );
}


function isNullableTransactionHash(
  value: unknown,
): value is string | null {
  return (
    value === null ||
    (
      typeof value === "string" &&
      /^0x[0-9a-fA-F]{64}$/.test(
        value.trim(),
      )
    )
  );
}


function validateClaimedJob(
  value: unknown,
): value is ClaimedLiquidationBlockchainQueueJob {
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

  const walletIndexValid =
    typeof row.wallet_index === "string" ||
    typeof row.wallet_index === "number";

  const signedPayloadValid =
    row.signed_payload === null ||
    (
      typeof row.signed_payload === "object" &&
      !Array.isArray(
        row.signed_payload,
      )
    );

  return (
    isNonEmptyString(
      row.queue_id,
    ) &&
    isNonEmptyString(
      row.liquidation_job_id,
    ) &&
    isNonEmptyString(
      row.user_id,
    ) &&
    isNonEmptyString(row.blockchain_code) &&
    /^[a-z0-9_-]+$/.test(row.blockchain_code) &&
    walletIndexValid &&
    isNonEmptyString(
      row.treasury_id,
    ) &&
    isNonEmptyString(
      row.sender_wallet_address,
    ) &&
    isNonEmptyString(
      row.collateral,
    ) &&
    isNonEmptyString(
      row.debt_repayment_amount,
    ) &&
    isNonEmptyString(
      row.penalty_amount,
    ) &&
    isNonEmptyString(
      row.total_liquidation_proceeds,
    ) &&
    isNonEmptyString(
      row.total_debt,
    ) &&
    isNonEmptyString(
      row.gold_price,
    ) &&
    isNonEmptyString(
      row.document_number,
    ) &&
    Number.isSafeInteger(
      row.fiscal_year,
    ) &&
    Number.isSafeInteger(
      row.period,
    ) &&
    isNonEmptyString(
      row.country_code,
    ) &&
    Number.isSafeInteger(
      row.retry_count,
    ) &&
    Number.isSafeInteger(
      row.attempt_count,
    ) &&
    typeof row.manual_review_required ===
      "boolean" &&
    row.queue_status ===
      "processing" &&
    isNullableTransactionHash(
      row.tx_hash,
    ) &&
    isNullableString(
      row.claimed_at,
    ) &&
    isNullableString(
      row.lease_expires_at,
    ) &&
    signedPayloadValid
  );
}


export async function claimLiquidationBlockchainJobs(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    countryCode: string;
    batchSize?: number;
  },
): Promise<ClaimedLiquidationJobs> {
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
    "claim_country_liquidation_blockchain_jobs",
    {
      p_country_code:
        countryCode,

      p_batch_size:
        batchSize,
    },
  );

  if (error) {
    console.error(
      "CLAIM_LIQUIDATION_BLOCKCHAIN_JOBS_RPC_FAILED",
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
        "FAILED_TO_CLAIM_LIQUIDATION_BLOCKCHAIN_JOBS",
    );
  }

  if (
    typeof data !== "object" ||
    data === null ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BLOCKCHAIN_CLAIM_RESPONSE",
    );
  }

  const result =
    data as
      Partial<ClaimedLiquidationJobs>;

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
      "INVALID_LIQUIDATION_BLOCKCHAIN_CLAIM_RESPONSE",
    );
  }

  if (
    claimed !==
    jobs.length
  ) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_CLAIM_COUNT_MISMATCH",
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
