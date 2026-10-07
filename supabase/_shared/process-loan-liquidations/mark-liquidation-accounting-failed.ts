import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";


type AccountingFailureRecordedResult = {
  success: true;
  already_completed: false;
  job_id: string;
  status: "accounting_failed";
  error_message: string;
  retryable: true;
  blockchain_transfer_required: false;
};


type AccountingAlreadyCompletedResult = {
  success: true;
  already_completed: true;
  job_id: string;
  status: "completed";
  error_message: null;
  retryable: false;
  blockchain_transfer_required: false;
};


export type LiquidationAccountingFailureResult =
  | AccountingFailureRecordedResult
  | AccountingAlreadyCompletedResult;


function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return (
      error.message.trim() ||
      "UNKNOWN_LIQUIDATION_ACCOUNTING_ERROR"
    );
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return (
      error.message.trim() ||
      "UNKNOWN_LIQUIDATION_ACCOUNTING_ERROR"
    );
  }

  const message =
    String(error).trim();

  return (
    message ||
    "UNKNOWN_LIQUIDATION_ACCOUNTING_ERROR"
  );
}


function validateFailureResult(
  value: unknown,
  expectedJobId: string,
): LiquidationAccountingFailureResult {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_FAILURE_RESULT",
    );
  }

  const result =
    value as Record<string, unknown>;

  if (result.success !== true) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_FAILURE_NOT_RECORDED",
    );
  }

  if (
    typeof result.job_id !== "string" ||
    result.job_id.trim() !==
      expectedJobId
  ) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_FAILURE_JOB_ID_MISMATCH",
    );
  }

  if (
    typeof result.already_completed !==
      "boolean"
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_COMPLETION_STATE",
    );
  }

  /*
   * Accounting retry must never require another
   * blockchain transfer.
   */
  if (
    result.blockchain_transfer_required !==
      false
  ) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_BLOCKCHAIN_RETRY_NOT_BLOCKED",
    );
  }

  /*
   * The accounting transaction may have committed while
   * the Edge Function failed to receive its response.
   *
   * In that case, the SQL function returns completed and
   * must not downgrade the job to accounting_failed.
   */
  if (result.already_completed === true) {
    if (result.status !== "completed") {
      throw new AppError(
        "INVALID_COMPLETED_LIQUIDATION_ACCOUNTING_STATUS",
      );
    }

    if (result.retryable !== false) {
      throw new AppError(
        "COMPLETED_LIQUIDATION_ACCOUNTING_MUST_NOT_BE_RETRIED",
      );
    }

    if (result.error_message !== null) {
      throw new AppError(
        "COMPLETED_LIQUIDATION_ACCOUNTING_HAS_ERROR",
      );
    }

    return {
      success:
        true,

      already_completed:
        true,

      job_id:
        result.job_id.trim(),

      status:
        "completed",

      error_message:
        null,

      retryable:
        false,

      blockchain_transfer_required:
        false,
    };
  }

  /*
   * Normal accounting failure result.
   */
  if (
    result.status !==
      "accounting_failed"
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_FAILURE_STATUS",
    );
  }

  if (
    typeof result.error_message !==
      "string" ||
    result.error_message.trim() === ""
  ) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_FAILURE_MESSAGE_NOT_RECORDED",
    );
  }

  if (result.retryable !== true) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_FAILURE_NOT_RETRYABLE",
    );
  }

  return {
    success:
      true,

    already_completed:
      false,

    job_id:
      result.job_id.trim(),

    status:
      "accounting_failed",

    error_message:
      result.error_message.trim(),

    retryable:
      true,

    blockchain_transfer_required:
      false,
  };
}


export async function markLiquidationAccountingFailed(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    jobId: string;
    error: unknown;
  },
): Promise<LiquidationAccountingFailureResult> {
  const jobId =
    input.jobId?.trim();

  if (!jobId) {
    throw new AppError(
      "LIQUIDATION_JOB_ID_REQUIRED",
    );
  }

  const originalErrorMessage =
    getErrorMessage(
      input.error,
    );

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "fail_liquidation_accounting_job",
    {
      p_job_id:
        jobId,

      p_error_message:
        originalErrorMessage,
    },
  );

  if (error) {
    console.error(
      "FAIL_LIQUIDATION_ACCOUNTING_JOB_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        jobId,

        originalError:
          originalErrorMessage,
      },
    );

    /*
     * Do not swallow this error. The job may otherwise
     * remain in accounting_processing without a recorded
     * explanation.
     */
    throw new AppError(
      error.message ||
        "FAILED_TO_RECORD_LIQUIDATION_ACCOUNTING_FAILURE",
    );
  }

  const result =
    validateFailureResult(
      data,
      jobId,
    );

  if (result.already_completed) {
    /*
     * Finalization committed successfully, but the caller
     * did not receive the original RPC response.
     */
    console.log(
      "LIQUIDATION_ACCOUNTING_ALREADY_COMPLETED",
      {
        jobId,

        originalError:
          originalErrorMessage,
      },
    );

    return result;
  }

  console.error(
    "LIQUIDATION_ACCOUNTING_JOB_MARKED_FAILED",
    {
      jobId,

      error:
        result.error_message,
    },
  );

  return result;
}