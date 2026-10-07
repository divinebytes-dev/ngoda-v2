import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import {
  AppError,
} from "../app-error.ts";

import type {
  FinalisedLiquidationAccountingResult,
} from "../types/finalised-liquidation-accounting-result.ts";


function isNonEmptyString(
  value: unknown,
): value is string {
  return (
    typeof value === "string" &&
    value.trim() !== ""
  );
}


function isDecimalString(
  value: unknown,
): value is string {
  if (
    typeof value !== "string"
  ) {
    return false;
  }

  const normalizedValue =
    value.trim();

  return (
    /^\d+(\.\d+)?$/.test(
      normalizedValue,
    ) &&
    Number.isFinite(
      Number(normalizedValue),
    )
  );
}


function validateFinalisationResult(
  value: unknown,
): value is FinalisedLiquidationAccountingResult {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return false;
  }

  const result =
    value as
      Record<string, unknown>;

  if (
    result.success !== true ||
    typeof result.already_completed !==
      "boolean" ||
    !isNonEmptyString(
      result.job_id,
    ) ||
    !isNonEmptyString(
      result.document_number,
    ) ||
    result.status !==
      "completed"
  ) {
    return false;
  }

  /*
   * An idempotent response does not return the detailed
   * accounting totals again.
   */
  if (
    result.already_completed === true
  ) {
    return true;
  }

  return (
    isNonEmptyString(
      result.blockchain_tx_hash,
    ) &&
    /^0x[0-9a-fA-F]{64}$/.test(
      result.blockchain_tx_hash,
    ) &&
    isDecimalString(
      result.principal_paid,
    ) &&
    isDecimalString(
      result.interest_paid,
    ) &&
    isDecimalString(
      result.debt_repayment,
    ) &&
    isDecimalString(
      result.penalty_amount,
    ) &&
    isDecimalString(
      result.total_proceeds,
    ) &&
    isDecimalString(
      result.collateral_transferred,
    )
  );
}


export async function finaliseLiquidationAccountingJob(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    jobId: string;
  },
): Promise<FinalisedLiquidationAccountingResult> {
  const jobId =
    input.jobId
      .trim();

  if (!jobId) {
    throw new AppError(
      "LIQUIDATION_JOB_ID_REQUIRED",
    );
  }

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "finalise_liquidation_accounting_job",
    {
      p_job_id:
        jobId,
    },
  );

  if (error) {
    console.error(
      "FINALISE_LIQUIDATION_ACCOUNTING_RPC_FAILED",
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
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_FINALISE_LIQUIDATION_ACCOUNTING",
    );
  }

  if (
    !validateFinalisationResult(
      data,
    )
  ) {
    console.error(
      "INVALID_LIQUIDATION_ACCOUNTING_RESULT",
      {
        jobId,
        data,
      },
    );

    throw new AppError(
      "INVALID_LIQUIDATION_ACCOUNTING_RESULT",
    );
  }

  if (
    data.job_id !== jobId
  ) {
    throw new AppError(
      "LIQUIDATION_ACCOUNTING_JOB_ID_MISMATCH",
    );
  }

  return data;
}
