import {
  AppError,
} from "../app-error.ts";

import {
  signTransfer,
} from "../blockchain/permit.ts";

import type {
  SignedTokenTransfer,
} from "../blockchain/permit.ts";

import {
  relayTrackedTransferWithPermit,
  waitForRelayedTokenTransfer,
} from "../blockchain/transfer.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import {
  fetchGlobalTreasuryAddress,
  restoreSignedTransfer,
  storeSignedTransfer,
  validateSignedTransferForJob,
} from "./liquidation-blockchain-queue-job.ts";

import type {
  ClaimedLiquidationBlockchainQueueJob,
} from "../types/claimed-liquidation-blockchain-queue-job.ts";

import type {
  ProcessedLiquidationBlockchainJob,
} from "../types/processed-liquidation-blockchain-job.ts";

import type {
  SaveSignedPayloadResult,
} from "../types/save-signed-payload-result.ts";


function buildExplorerUrl(
  txHash: string,
): string | null {
  const configuredUrl =
    Deno.env
      .get("CHIADO_EXPLORER")
      ?.trim();

  if (!configuredUrl) {
    return null;
  }

  const baseUrl =
    configuredUrl.replace(
      /\/+$/,
      "",
    );

  if (
    baseUrl
      .toLowerCase()
      .endsWith("/tx")
  ) {
    return `${baseUrl}/${txHash}`;
  }

  return `${baseUrl}/tx/${txHash}`;
}


function validateWalletIndex(
  value: string | number,
): number {
  const walletIndex =
    Number(value);

  if (
    !Number.isSafeInteger(
      walletIndex,
    ) ||
    walletIndex < 0
  ) {
    throw new AppError(
      "INVALID_USER_WALLET_INDEX",
    );
  }

  return walletIndex;
}


function validateCollateralAmount(
  value: string,
): string {
  const amount =
    value
      .toString()
      .trim();

  const numericAmount =
    Number(amount);

  if (
    !/^\d+(\.\d+)?$/.test(
      amount,
    ) ||
    !Number.isFinite(
      numericAmount,
    ) ||
    numericAmount <= 0
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
    );
  }

  return amount;
}


function readQueuedTransactionHash(
  job:
    ClaimedLiquidationBlockchainQueueJob,
): string | null {
  if (job.tx_hash === null) {
    return null;
  }

  const txHash =
    job.tx_hash.trim();

  if (
    !/^0x[0-9a-fA-F]{64}$/.test(
      txHash,
    )
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
    );
  }

  return txHash;
}


function validateClaimedJob(
  job:
    ClaimedLiquidationBlockchainQueueJob,
): void {
  if (
    !job.queue_id?.trim()
  ) {
    throw new AppError(
      "LIQUIDATION_QUEUE_ID_REQUIRED",
    );
  }

  if (
    !job.liquidation_job_id?.trim()
  ) {
    throw new AppError(
      "LIQUIDATION_JOB_ID_REQUIRED",
    );
  }

  if (
    job.manual_review_required
  ) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED",
    );
  }

  if (
    job.queue_status !==
    "processing"
  ) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING",
    );
  }

  validateWalletIndex(
    job.wallet_index,
  );

  validateCollateralAmount(
    job.collateral,
  );
}


async function fetchSignedTransfer(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    job:
      ClaimedLiquidationBlockchainQueueJob;
  },
): Promise<SignedTokenTransfer> {
  /*
   * Reuse an existing signed payload when no blockchain
   * transaction has been submitted yet.
   */
  if (
    input.job.signed_payload
  ) {
    return restoreSignedTransfer(
      input.job.signed_payload,
      input.job,
    );
  }

  const signedTransfer =
    await signTransfer({
      fromIndex:
        validateWalletIndex(
          input.job.wallet_index,
        ),

      expectedOwner:
        input.job
          .sender_wallet_address,

      to:
        fetchGlobalTreasuryAddress(),

      amount:
        validateCollateralAmount(
          input.job.collateral,
        ),

      fee:
        "0",
    });

  validateSignedTransferForJob(
    signedTransfer,
    input.job,
  );

  /*
   * Persist the signature before submitting the
   * transaction.
   */
  const {
    data,
    error,
  } = await input.supabase.rpc(
    "save_liquidation_blockchain_signed_payload",
    {
      p_queue_id:
        input.job.queue_id,

      p_signed_payload:
        storeSignedTransfer(
          signedTransfer,
        ),
    },
  );

  if (error) {
    console.error(
      "SAVE_LIQUIDATION_SIGNED_PAYLOAD_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        queueId:
          input.job.queue_id,

        liquidationJobId:
          input.job
            .liquidation_job_id,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_SAVE_LIQUIDATION_SIGNED_PAYLOAD",
    );
  }

  const result =
    data as
      SaveSignedPayloadResult | null;

  if (
    !result ||
    result.success !== true ||
    !result.signed_payload
  ) {
    throw new AppError(
      "SIGNED_LIQUIDATION_PAYLOAD_NOT_RETURNED",
    );
  }

  /*
   * Another invocation may have stored its signed payload
   * first. Always use the payload returned by PostgreSQL.
   */
  return restoreSignedTransfer(
    result.signed_payload,
    input.job,
  );
}


async function recordBlockchainSubmission(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    queueId: string;
    txHash: string;
  },
): Promise<void> {
  let lastError:
    string | null =
      null;

  /*
   * Retry only the database update.
   *
   * The blockchain transfer must never be submitted again.
   */
  for (
    let attempt = 1;
    attempt <= 3;
    attempt += 1
  ) {
    const {
      error,
    } = await input.supabase.rpc(
      "record_liquidation_blockchain_submission",
      {
        p_queue_id:
          input.queueId,

        p_tx_hash:
          input.txHash,
      },
    );

    if (!error) {
      return;
    }

    lastError =
      error.message;

    console.error(
      "RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION_RPC_FAILED",
      {
        attempt,

        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        queueId:
          input.queueId,

        txHash:
          input.txHash,
      },
    );
  }

  throw new AppError(
    lastError ||
      "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION",
  );
}


async function confirmBlockchainTransfer(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    job:
      ClaimedLiquidationBlockchainQueueJob;

    txHash: string;
  },
): Promise<void> {
  let lastError:
    string | null =
      null;

  /*
   * Retry only the database confirmation.
   *
   * The blockchain transfer has already completed.
   */
  for (
    let attempt = 1;
    attempt <= 3;
    attempt += 1
  ) {
    const {
      error,
    } = await input.supabase.rpc(
      "confirm_liquidation_blockchain_transfer",
      {
        p_queue_id:
          input.job.queue_id,

        p_tx_hash:
          input.txHash,

        p_explorer_url:
          buildExplorerUrl(
            input.txHash,
          ),
      },
    );

    if (!error) {
      return;
    }

    lastError =
      error.message;

    console.error(
      "CONFIRM_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
      {
        attempt,

        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        queueId:
          input.job.queue_id,

        liquidationJobId:
          input.job
            .liquidation_job_id,

        txHash:
          input.txHash,
      },
    );
  }

  throw new AppError(
    lastError ||
      "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_CONFIRMATION",
  );
}


async function markLiquidationBlockchainFailed(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    queueId: string;
    txHash: string | null;
    error: unknown;
  },
): Promise<void> {
  const errorMessage =
    input.error instanceof Error
      ? input.error.message
      : String(input.error);

  const {
    error,
  } = await input.supabase.rpc(
    "fail_liquidation_blockchain_transfer",
    {
      p_queue_id:
        input.queueId,

      p_error_message:
        errorMessage,

      /*
       * When this hash exists, PostgreSQL keeps the queue
       * resumable instead of allowing another transfer.
       */
      p_tx_hash:
        input.txHash,
    },
  );

  if (error) {
    console.error(
      "FAIL_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        queueId:
          input.queueId,

        txHash:
          input.txHash,

        originalError:
          errorMessage,
      },
    );

    /*
     * Never hide a failure to update the processing state.
     * The caller must surface this as a cron-stage failure.
     */
    throw new AppError(
      error.message ||
        "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_FAILURE",
    );
  }
}


export async function processLiquidationBlockchainJob(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    job:
      ClaimedLiquidationBlockchainQueueJob;
  },
): Promise<ProcessedLiquidationBlockchainJob> {
  let blockchainConfirmed =
    false;

  let blockchainSubmitted =
    false;

  let txHash:
    string | null =
      null;

  try {
    validateClaimedJob(
      input.job,
    );

    txHash =
      readQueuedTransactionHash(
        input.job,
      );

    blockchainSubmitted =
      txHash !== null;

    /*
     * Existing hash:
     * wait for the previously submitted transaction.
     *
     * No hash:
     * sign and submit a new transaction.
     */
    const blockchainResult =
      txHash
        ? await waitForRelayedTokenTransfer(
            txHash,
          )
        : await relayTrackedTransferWithPermit(
            await fetchSignedTransfer(
              input,
            ),
            {
              onSubmitted:
                async (
                  submittedHash,
                ) => {
                  txHash =
                    submittedHash;

                  blockchainSubmitted =
                    true;

                  await recordBlockchainSubmission({
                    supabase:
                      input.supabase,

                    queueId:
                      input.job.queue_id,

                    txHash:
                      submittedHash,
                  });
                },
            },
          );

    txHash =
      blockchainResult
        .txHash
        ?.trim() ??
      null;

    if (
      !txHash ||
      !/^0x[0-9a-fA-F]{64}$/.test(
        txHash,
      )
    ) {
      throw new AppError(
        "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
      );
    }

    /*
     * The receipt exists, but accounting remains blocked
     * until PostgreSQL records the confirmation.
     */
    blockchainConfirmed =
      true;

    await confirmBlockchainTransfer({
      supabase:
        input.supabase,

      job:
        input.job,

      txHash,
    });

    return {
      queue_id:
        input.job.queue_id,

      liquidation_job_id:
        input.job
          .liquidation_job_id,

      success:
        true,

      blockchain_confirmed:
        true,

      database_confirmed:
        true,

      tx_hash:
        txHash,

      error:
        null,
    };
  } catch (error) {
    const originalError =
      error instanceof Error
        ? error.message
        : String(error);

    /*
     * This RPC must succeed. If it fails, throw so the
     * whole blockchain stage is reported as failed.
     */
    try {
      await markLiquidationBlockchainFailed({
        supabase:
          input.supabase,

        queueId:
          input.job.queue_id,

        txHash,

        error,
      });
    } catch (stateError) {
      const stateErrorMessage =
        stateError instanceof Error
          ? stateError.message
          : String(stateError);

      console.error(
        "LIQUIDATION_BLOCKCHAIN_FAILURE_STATE_NOT_RECORDED",
        {
          queueId:
            input.job.queue_id,

          liquidationJobId:
            input.job
              .liquidation_job_id,

          txHash,

          originalError,

          stateError:
            stateErrorMessage,
        },
      );

      throw stateError;
    }

    if (
      blockchainSubmitted ||
      blockchainConfirmed
    ) {
      /*
       * A submitted transaction hash is retained by the
       * failure RPC. A later cron run waits for this exact
       * transaction and never submits Gold again.
       */
      console.error(
        "LIQUIDATION_BLOCKCHAIN_SUBMITTED_OR_CONFIRMED_REQUIRES_RESUME",
        {
          queueId:
            input.job.queue_id,

          liquidationJobId:
            input.job
              .liquidation_job_id,

          txHash,

          error:
            originalError,
        },
      );
    }

    return {
      queue_id:
        input.job.queue_id,

      liquidation_job_id:
        input.job
          .liquidation_job_id,

      success:
        false,

      blockchain_confirmed:
        blockchainConfirmed,

      database_confirmed:
        false,

      tx_hash:
        txHash,

      error:
        originalError,
    };
  }
}