import { AppError } from "./app-error.ts";
import { createSupabaseServiceClient } from "./supabase-client.ts";
import { relayTransferWithPermit } from "./blockchain/transfer.ts";
import { ClaimedLiquidationBlockchainQueueJob, prepareSignedLiquidationTransfer } from "./signed-liquidation-transfer.ts";

function buildExplorerUrl(
  txHash: string,
): string | null {
  const baseUrl =
    Deno.env
      .get("CHIADO_EXPLORER")
      ?.trim();

  if (!baseUrl) {
    return null;
  }

  return `${
    baseUrl.replace(
      /\/+$/,
      "",
    )
  }/tx/${txHash}`;
}


async function markLiquidationBlockchainFailed(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    queueId: string;
    error: unknown;
  },
): Promise<void> {
  const message =
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
        message,
    },
  );

  if (error) {
    console.error(
      "FAIL_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
      {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
        queueId:
          input.queueId,
      },
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
): Promise<{
  queue_id: string;
  success: boolean;
  tx_hash: string | null;
  error: string | null;
}> {
  try {
const signedTransfer =
  await prepareSignedLiquidationTransfer({
    supabase:
      input.supabase,

    job:
      input.job,
  });

    /*
     * The previously stored signature is used for both
     * the first attempt and every retry.
     */
const blockchainResult =
  await relayTransferWithPermit(
    signedTransfer,
  );

    const txHash =
      blockchainResult.txHash;

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
     * relayTransferWithPermit must only return after the
     * blockchain transaction has been confirmed.
     */
    const {
      error: confirmationError,
    } = await input.supabase.rpc(
      "confirm_liquidation_blockchain_transfer",
      {
        p_queue_id:
          input.job.queue_id,

        p_tx_hash:
          txHash,

        p_explorer_url:
          buildExplorerUrl(
            txHash,
          ),
      },
    );

    if (confirmationError) {
      console.error(
        "CONFIRM_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
        {
          code:
            confirmationError.code,

          message:
            confirmationError.message,

          details:
            confirmationError.details,

          hint:
            confirmationError.hint,

          queueId:
            input.job.queue_id,

          txHash,
        },
      );

      throw new AppError(
        confirmationError.message ||
          "FAILED_TO_CONFIRM_LIQUIDATION_BLOCKCHAIN_TRANSFER",
      );
    }

    return {
      queue_id:
        input.job.queue_id,

      success:
        true,

      tx_hash:
        txHash,

      error:
        null,
    };
  } catch (error) {
    await markLiquidationBlockchainFailed({
      supabase:
        input.supabase,

      queueId:
        input.job.queue_id,

      error,
    });

    return {
      queue_id:
        input.job.queue_id,

      success:
        false,

      tx_hash:
        null,

      error:
        error instanceof Error
          ? error.message
          : String(error),
    };
  }
}