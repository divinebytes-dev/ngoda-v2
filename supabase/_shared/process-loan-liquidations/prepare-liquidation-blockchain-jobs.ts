import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import type {
  PreparedLiquidationBlockchainJob,
  PreparedLiquidationBlockchainJobsResult,
} from "../types/prepared-liquidation-blockchain-jobs-result.ts";


function normalizeCountryCode(
  value: string,
): string {
  const countryCode =
    value?.trim().toLowerCase();

  if (!countryCode) {
    throw new AppError(
      "COUNTRY_CODE_REQUIRED",
    );
  }

  return countryCode;
}


function validateBatchSize(
  value: number | undefined,
): number {
  const batchSize =
    value ?? 25;

  if (
    !Number.isSafeInteger(batchSize) ||
    batchSize < 1 ||
    batchSize > 100
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BATCH_SIZE",
    );
  }

  return batchSize;
}


function requiredString(
  value: unknown,
  errorCode: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return value.trim();
}


function requiredNonNegativeInteger(
  value: unknown,
  errorCode: string,
): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return value;
}


function requiredPositiveDecimal(
  value: unknown,
  errorCode: string,
): string {
  const decimalValue =
    requiredString(
      value,
      errorCode,
    );

  if (
    !/^\d+(\.\d+)?$/.test(
      decimalValue,
    ) ||
    Number(decimalValue) <= 0
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return decimalValue;
}


function validatePreparedJob(
  value: unknown,
): PreparedLiquidationBlockchainJob {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "INVALID_PREPARED_LIQUIDATION_BLOCKCHAIN_JOB",
    );
  }

  const job =
    value as Record<string, unknown>;

  const currencyCode =
    requiredString(
      job.currency_code,
      "PREPARED_LIQUIDATION_CURRENCY_REQUIRED",
    ).toLowerCase();

  if (currencyCode !== "gold") {
    throw new AppError(
      "INVALID_PREPARED_LIQUIDATION_CURRENCY",
    );
  }

  return {
    job_id:
      requiredString(
        job.job_id,
        "PREPARED_LIQUIDATION_JOB_ID_REQUIRED",
      ),

    queue_id:
      requiredString(
        job.queue_id,
        "PREPARED_LIQUIDATION_QUEUE_ID_REQUIRED",
      ),

    document_number:
      requiredString(
        job.document_number,
        "PREPARED_LIQUIDATION_DOCUMENT_NUMBER_REQUIRED",
      ),

    user_id:
      requiredString(
        job.user_id,
        "PREPARED_LIQUIDATION_USER_ID_REQUIRED",
      ),

    currency_code:
      currencyCode,

    collateral:
      requiredPositiveDecimal(
        job.collateral,
        "INVALID_PREPARED_LIQUIDATION_COLLATERAL",
      ),

    sender_wallet_address:
      requiredString(
        job.sender_wallet_address,
        "PREPARED_LIQUIDATION_SENDER_WALLET_REQUIRED",
      ),

    receiver_wallet_address:
      requiredString(
        job.receiver_wallet_address,
        "PREPARED_LIQUIDATION_RECEIVER_WALLET_REQUIRED",
      ),
  };
}


function validatePreparationResult(
  value: unknown,
  expectedCountryCode: string,
): PreparedLiquidationBlockchainJobsResult {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_QUEUE_PREPARATION_RESPONSE",
    );
  }

  const result =
    value as Record<string, unknown>;

  if (typeof result.success !== "boolean") {
    throw new AppError(
      "INVALID_LIQUIDATION_QUEUE_PREPARATION_SUCCESS",
    );
  }

  const countryCode =
    requiredString(
      result.country_code,
      "LIQUIDATION_PREPARATION_COUNTRY_REQUIRED",
    ).toLowerCase();

  if (countryCode !== expectedCountryCode) {
    throw new AppError(
      "LIQUIDATION_PREPARATION_COUNTRY_MISMATCH",
    );
  }

  const prepared =
    requiredNonNegativeInteger(
      result.prepared,
      "INVALID_PREPARED_LIQUIDATION_COUNT",
    );

  const alreadyPrepared =
    requiredNonNegativeInteger(
      result.already_prepared,
      "INVALID_EXISTING_LIQUIDATION_COUNT",
    );

  const failed =
    requiredNonNegativeInteger(
      result.failed,
      "INVALID_FAILED_LIQUIDATION_COUNT",
    );

  if (!Array.isArray(result.jobs)) {
    throw new AppError(
      "INVALID_PREPARED_LIQUIDATION_JOBS",
    );
  }

  const jobs =
    result.jobs.map(
      validatePreparedJob,
    );

  if (prepared !== jobs.length) {
    throw new AppError(
      "PREPARED_LIQUIDATION_JOB_COUNT_MISMATCH",
    );
  }

  let errorMessage: string | null =
    null;

  if (result.error_message != null) {
    if (
      typeof result.error_message !== "string"
    ) {
      throw new AppError(
        "INVALID_LIQUIDATION_PREPARATION_ERROR_MESSAGE",
      );
    }

    errorMessage =
      result.error_message.trim() ||
      null;
  }

  if (
    result.success === false &&
    !errorMessage
  ) {
    throw new AppError(
      "LIQUIDATION_PREPARATION_ERROR_MESSAGE_REQUIRED",
    );
  }

  return {
    success:
      result.success,

    country_code:
      countryCode,

    prepared,

    already_prepared:
      alreadyPrepared,

    failed,

    error_message:
      errorMessage,

    jobs,
  };
}


export async function prepareLiquidationBlockchainJobs(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    countryCode: string;
    batchSize?: number;
  },
): Promise<PreparedLiquidationBlockchainJobsResult> {
  const countryCode =
    normalizeCountryCode(
      input.countryCode,
    );

  const batchSize =
    validateBatchSize(
      input.batchSize,
    );

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "prepare_country_liquidation_blockchain_jobs",
    {
      p_country_code:
        countryCode,

      p_batch_size:
        batchSize,
    },
  );

  if (error) {
    console.error(
      "PREPARE_LIQUIDATION_BLOCKCHAIN_JOBS_RPC_FAILED",
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
        "FAILED_TO_PREPARE_LIQUIDATION_BLOCKCHAIN_JOBS",
    );
  }

  const result =
    validatePreparationResult(
      data,
      countryCode,
    );

  /*
   * Configuration failures are returned by PostgreSQL
   * instead of raised so its liquidation_job error update
   * can commit. Throw only after receiving that result.
   */
  if (!result.success) {
    console.error(
      "LIQUIDATION_QUEUE_PREPARATION_REPORTED_FAILURE",
      {
        countryCode:
          result.country_code,

        prepared:
          result.prepared,

        alreadyPrepared:
          result.already_prepared,

        failed:
          result.failed,

        error:
          result.error_message,
      },
    );

    throw new AppError(
      result.error_message ||
        "LIQUIDATION_QUEUE_PREPARATION_FAILED",
    );
  }

  return result;
}