import {
  getAddress,
  isAddress,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  blockchainConfig,
  relayerContract,
} from "./client.ts";

import type {
  SignedTokenTransfer,
} from "./permit.ts";


export type RelayedTokenTransfer = {
  txHash: string;
};


export type TrackedTokenTransferLifecycle = {
  onSubmitted?: (
    txHash: string,
  ) => Promise<void>;
};


type ValidatedTokenTransfer = {
  owner: string;
  receiver: string;
};


const TRANSACTION_CONFIRMATIONS = 1;
const TRANSACTION_WAIT_TIMEOUT_MS = 45_000;


function validateTransactionHash(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string"
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  const txHash =
    value.trim();

  if (
    !/^0x[0-9a-fA-F]{64}$/.test(
      txHash,
    )
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return txHash;
}


function validateSignedTransfer(
  signed: SignedTokenTransfer,
): ValidatedTokenTransfer {
  if (
    !signed.owner ||
    !isAddress(
      signed.owner,
    )
  ) {
    throw new AppError(
      "INVALID_OWNER_ADDRESS",
    );
  }

  if (
    !signed.to ||
    !isAddress(
      signed.to,
    )
  ) {
    throw new AppError(
      "INVALID_RECEIVER_ADDRESS",
    );
  }

  if (
    signed.parsedAmount <= 0n
  ) {
    throw new AppError(
      "INVALID_TRANSFER_AMOUNT",
    );
  }

  if (
    signed.parsedFee < 0n
  ) {
    throw new AppError(
      "INVALID_TRANSFER_FEE",
    );
  }

  const now =
    BigInt(
      Math.floor(
        Date.now() / 1000,
      ),
    );

  if (
    signed.deadline < now
  ) {
    throw new AppError(
      "SIGNATURE_EXPIRED",
    );
  }

  return {
    owner:
      getAddress(
        signed.owner,
      ),

    receiver:
      getAddress(
        signed.to,
      ),
  };
}


async function simulateTransfer(
  signed: SignedTokenTransfer,
  transfer: ValidatedTokenTransfer,
): Promise<void> {
  try {
    await relayerContract
      .transferWithPermitAndFee
      .staticCall(
        transfer.owner,
        transfer.receiver,

        blockchainConfig
          .treasuryAddress,

        signed.parsedAmount,
        signed.parsedFee,
        signed.deadline,
        signed.v,
        signed.r,
        signed.s,
      );
  } catch (error) {
    console.error(
      "TOKEN_TRANSFER_SIMULATION_FAILED",
      {
        owner:
          transfer.owner,

        receiver:
          transfer.receiver,

        amount:
          signed.parsedAmount
            .toString(),

        fee:
          signed.parsedFee
            .toString(),

        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    throw new AppError(
      "TOKEN_TRANSFER_WOULD_FAIL",
    );
  }
}


/*
 * Existing transfer path used by Gold buy, Gold sell and
 * Gold transfer.
 *
 * Its external behavior remains unchanged: it simulates,
 * submits, waits for a receipt, and returns the receipt
 * hash. Liquidation-specific persistence is not introduced
 * into these processes.
 */
export async function relayTransferWithPermit(
  signed: SignedTokenTransfer,
): Promise<RelayedTokenTransfer> {
  const transfer =
    validateSignedTransfer(
      signed,
    );

  await simulateTransfer(
    signed,
    transfer,
  );

  const transaction =
    await relayerContract
      .transferWithPermitAndFee(
        transfer.owner,
        transfer.receiver,

        blockchainConfig
          .treasuryAddress,

        signed.parsedAmount,
        signed.parsedFee,
        signed.deadline,
        signed.v,
        signed.r,
        signed.s,
      );

  const receipt =
    await transaction.wait();

  if (!receipt?.hash) {
    throw new AppError(
      "BLOCKCHAIN_RECEIPT_NOT_FOUND",
    );
  }

  return {
    txHash:
      receipt.hash,
  };
}


/*
 * Liquidation-only transfer path.
 *
 * It exposes the submitted transaction hash before waiting
 * for confirmation. The liquidation processor stores that
 * hash immediately, so a later cron execution resumes the
 * same blockchain transaction instead of transferring the
 * Gold again.
 */
export async function relayTrackedTransferWithPermit(
  signed: SignedTokenTransfer,
  lifecycle:
    TrackedTokenTransferLifecycle = {},
): Promise<RelayedTokenTransfer> {
  const transfer =
    validateSignedTransfer(
      signed,
    );

  await simulateTransfer(
    signed,
    transfer,
  );

  const transaction =
    await relayerContract
      .transferWithPermitAndFee(
        transfer.owner,
        transfer.receiver,

        blockchainConfig
          .treasuryAddress,

        signed.parsedAmount,
        signed.parsedFee,
        signed.deadline,
        signed.v,
        signed.r,
        signed.s,
      );

  const submittedHash =
    validateTransactionHash(
      transaction.hash,
      "BLOCKCHAIN_SUBMISSION_HASH_NOT_FOUND",
    );

  /*
   * This callback must finish before waiting for the
   * receipt. If it fails, the caller still receives the
   * submitted hash through its callback scope and records
   * the job as resumable without submitting again.
   */
  if (lifecycle.onSubmitted) {
    await lifecycle.onSubmitted(
      submittedHash,
    );
  }

  const receipt =
    await transaction.wait();

  if (!receipt) {
    throw new AppError(
      "BLOCKCHAIN_RECEIPT_NOT_FOUND",
    );
  }

  if (receipt.status !== 1) {
    throw new AppError(
      "TOKEN_TRANSFER_REVERTED",
    );
  }

  const confirmedHash =
    validateTransactionHash(
      receipt.hash,
      "BLOCKCHAIN_RECEIPT_HASH_NOT_FOUND",
    );

  if (
    confirmedHash.toLowerCase() !==
    submittedHash.toLowerCase()
  ) {
    throw new AppError(
      "BLOCKCHAIN_TRANSACTION_HASH_MISMATCH",
    );
  }

  return {
    txHash:
      confirmedHash,
  };
}


/*
 * Resume a liquidation transfer that was submitted by an
 * earlier cron execution. This function never submits a
 * new blockchain transaction.
 */
export async function waitForRelayedTokenTransfer(
  txHash: string,
): Promise<RelayedTokenTransfer> {
  const normalizedHash =
    validateTransactionHash(
      txHash,
      "INVALID_BLOCKCHAIN_TRANSACTION_HASH",
    );

  const provider =
    relayerContract
      .runner
      ?.provider;

  if (!provider) {
    throw new AppError(
      "BLOCKCHAIN_PROVIDER_NOT_CONFIGURED",
    );
  }

  const receipt =
    await provider.waitForTransaction(
      normalizedHash,
      TRANSACTION_CONFIRMATIONS,
      TRANSACTION_WAIT_TIMEOUT_MS,
    );

  if (!receipt) {
    throw new AppError(
      "BLOCKCHAIN_TRANSACTION_RECEIPT_PENDING",
    );
  }

  if (receipt.status !== 1) {
    throw new AppError(
      "TOKEN_TRANSFER_REVERTED",
    );
  }

  const confirmedHash =
    validateTransactionHash(
      receipt.hash,
      "BLOCKCHAIN_RECEIPT_HASH_NOT_FOUND",
    );

  if (
    confirmedHash.toLowerCase() !==
    normalizedHash.toLowerCase()
  ) {
    throw new AppError(
      "BLOCKCHAIN_TRANSACTION_HASH_MISMATCH",
    );
  }

  return {
    txHash:
      confirmedHash,
  };
}
