import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import {
  finaliseLiquidationAccountingJob,
} from "./finalise-liquidation-accounting-job.ts";

import {
  markLiquidationAccountingFailed,
} from "./mark-liquidation-accounting-failed.ts";

import type {
  ClaimedLiquidationAccountingJob,
} from "../types/claimed-liquidation-accounting-job.ts";


export type ProcessedLiquidationAccountingJob = {
  job_id: string;
  success: boolean;
  already_completed: boolean;
  failure_recorded: boolean;
  error: string | null;
};


export type ProcessedLiquidationAccountingJobsResult = {
  processed: number;
  succeeded: number;
  failed: number;
  results: ProcessedLiquidationAccountingJob[];
};


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

  return (
    String(error).trim() ||
    "UNKNOWN_LIQUIDATION_ACCOUNTING_ERROR"
  );
}


function validateJobs(
  jobs: ClaimedLiquidationAccountingJob[],
): ClaimedLiquidationAccountingJob[] {
  if (!Array.isArray(jobs)) {
    throw new AppError(
      "INVALID_CLAIMED_LIQUIDATION_ACCOUNTING_JOBS",
    );
  }

  const jobIds =
    new Set<string>();

  for (const job of jobs) {
    if (
      typeof job !== "object" ||
      job === null
    ) {
      throw new AppError(
        "INVALID_CLAIMED_LIQUIDATION_ACCOUNTING_JOB",
      );
    }

    if (
      typeof job.job_id !== "string" ||
      job.job_id.trim() === ""
    ) {
      throw new AppError(
        "CLAIMED_LIQUIDATION_ACCOUNTING_JOB_ID_REQUIRED",
      );
    }

    if (
      typeof job.country_code !== "string" ||
      job.country_code.trim() === ""
    ) {
      throw new AppError(
        "CLAIMED_LIQUIDATION_ACCOUNTING_COUNTRY_REQUIRED",
      );
    }

    const jobId =
      job.job_id.trim();

    if (jobIds.has(jobId)) {
      throw new AppError(
        "DUPLICATE_CLAIMED_LIQUIDATION_ACCOUNTING_JOB",
      );
    }

    jobIds.add(jobId);
  }

  return jobs;
}


export async function processLiquidationAccountingJobs(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    jobs:
      ClaimedLiquidationAccountingJob[];
  },
): Promise<ProcessedLiquidationAccountingJobsResult> {
  const jobs =
    validateJobs(
      input.jobs,
    );

  let succeeded = 0;
  let failed = 0;

  const results:
    ProcessedLiquidationAccountingJob[] =
      [];

  /*
   * These are jobs where accounting finalization failed
   * and the failure itself could not be recorded.
   */
  const unrecordedFailures: Array<{
    job_id: string;
    accounting_error: string;
    failure_recording_error: string;
  }> = [];

  /*
   * Process accounting sequentially. Every finalization
   * RPC executes in its own atomic PostgreSQL transaction.
   */
  for (const job of jobs) {
    const jobId =
      job.job_id.trim();

    try {
      const finalisedResult =
        await finaliseLiquidationAccountingJob({
          supabase:
            input.supabase,

          jobId,
        });

      succeeded += 1;

      results.push({
        job_id:
          jobId,

        success:
          true,

        already_completed:
          finalisedResult.already_completed,

        failure_recorded:
          false,

        error:
          null,
      });
    } catch (accountingError) {
      const accountingErrorMessage =
        getErrorMessage(
          accountingError,
        );

      try {
        const failureResult =
          await markLiquidationAccountingFailed({
            supabase:
              input.supabase,

            jobId,

            error:
              accountingError,
          });

        /*
         * The database transaction may have committed while
         * the Edge Function failed to receive the original
         * finalization response.
         *
         * In that case the failure RPC reports completed.
         * Count it as success and never retry it.
         */
        if (failureResult.already_completed) {
          succeeded += 1;

          results.push({
            job_id:
              jobId,

            success:
              true,

            already_completed:
              true,

            failure_recorded:
              false,

            error:
              null,
          });

          continue;
        }

        /*
         * Accounting genuinely failed and the job was safely
         * changed to accounting_failed for a later retry.
         */
        failed += 1;

        results.push({
          job_id:
            jobId,

          success:
            false,

          already_completed:
            false,

          failure_recorded:
            true,

          error:
            failureResult.error_message,
        });
      } catch (failureRecordingError) {
        failed += 1;

        const failureRecordingErrorMessage =
          getErrorMessage(
            failureRecordingError,
          );

        console.error(
          "LIQUIDATION_ACCOUNTING_FAILURE_COULD_NOT_BE_RECORDED",
          {
            jobId,

            accountingError:
              accountingErrorMessage,

            failureRecordingError:
              failureRecordingErrorMessage,
          },
        );

        unrecordedFailures.push({
          job_id:
            jobId,

          accounting_error:
            accountingErrorMessage,

          failure_recording_error:
            failureRecordingErrorMessage,
        });

        results.push({
          job_id:
            jobId,

          success:
            false,

          already_completed:
            false,

          failure_recorded:
            false,

          error:
            `${accountingErrorMessage}; ` +
            `FAILURE_RECORDING_FAILED: ` +
            failureRecordingErrorMessage,
        });
      }
    }
  }

  /*
   * Do not let the cron report success when a job may have
   * remained in accounting_processing without a recorded
   * error.
   */
  if (unrecordedFailures.length > 0) {
    console.error(
      "UNRECORDED_LIQUIDATION_ACCOUNTING_FAILURES",
      {
        failures:
          unrecordedFailures,
      },
    );

    throw new AppError(
      "LIQUIDATION_ACCOUNTING_FAILURE_STATE_NOT_RECORDED",
    );
  }

  return {
    processed:
      succeeded + failed,

    succeeded,

    failed,

    results,
  };
}