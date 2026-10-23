import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import {
  createBlockchainClient,
  type BlockchainClientConfig,
} from "../blockchain/client.ts";

import {
  signTransfer,
  type BlockchainClient,
  type SignedTokenTransfer,
} from "../blockchain/permit.ts";

import {
  relayTrackedTransferWithPermit,
  waitForRelayedTokenTransfer,
} from "../blockchain/transfer.ts";

import {
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

/*
 * ==========================================================
 * VALIDATION HELPERS
 * ==========================================================
 */

function requiredString(
  value: unknown,
  errorCode: string,
): string {
  if (
    typeof value !== "string" ||
    !value.trim()
  ) {
    throw new AppError(errorCode);
  }

  return value.trim();
}

function requiredHttpUrl(
  value: unknown,
  errorCode: string,
): string {
  const text = requiredString(value, errorCode);

  try {
    const url = new URL(text);

    if (
      url.protocol !== "https:" &&
      url.protocol !== "http:"
    ) {
      throw new Error("Invalid protocol");
    }
  } catch {
    throw new AppError(errorCode);
  }

  return text;
}

function validateBlockchainCode(
  value: unknown,
): string {
  if (
    typeof value !== "string" ||
    !/^[a-z0-9_-]+$/.test(value)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BLOCKCHAIN_CODE",
    );
  }

  return value;
}

function validateWalletIndex(
  value: string | number,
): number {
  if (
    (typeof value !== "string" &&
      typeof value !== "number") ||
    String(value).trim() === ""
  ) {
    throw new AppError(
      "INVALID_USER_WALLET_INDEX",
    );
  }

  const walletIndex = Number(value);

  if (
    !Number.isSafeInteger(walletIndex) ||
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
  const amount = requiredString(
    value,
    "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
  );

  const numericAmount = Number(amount);

  if (
    !/^\d+(\.\d+)?$/.test(amount) ||
    !Number.isFinite(numericAmount) ||
    numericAmount <= 0
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
    );
  }

  return amount;
}

function validateTransactionHash(
  value: unknown,
): string {
  const txHash = requiredString(
    value,
    "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    throw new AppError(
      "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
    );
  }

  return txHash;
}

function readQueuedTransactionHash(
  job: ClaimedLiquidationBlockchainQueueJob,
): string | null {
  if (job.tx_hash === null) {
    return null;
  }

  return validateTransactionHash(job.tx_hash);
}

function validateClaimedJob(
  job: ClaimedLiquidationBlockchainQueueJob,
): void {
  requiredString(
    job.queue_id,
    "LIQUIDATION_QUEUE_ID_REQUIRED",
  );

  requiredString(
    job.liquidation_job_id,
    "LIQUIDATION_JOB_ID_REQUIRED",
  );

  validateBlockchainCode(job.blockchain_code);

  if (job.manual_review_required) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED",
    );
  }

  if (job.queue_status !== "processing") {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING",
    );
  }

  validateWalletIndex(job.wallet_index);
  validateCollateralAmount(job.collateral);
}

function buildExplorerUrl(
  explorerUrl: string,
  txHash: string,
): string {
  const base = requiredHttpUrl(
    explorerUrl,
    "INVALID_BLOCKCHAIN_EXPLORER_URL",
  ).replace(/\/+$/, "");

  const hash = validateTransactionHash(txHash);

  return base.toLowerCase().endsWith("/tx")
    ? `${base}/${hash}`
    : `${base}/tx/${hash}`;
}

/*
 * ==========================================================
 * BLOCKCHAIN CONFIGURATION
 * ==========================================================
 */

async function fetchLiquidationBlockchainConfig(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    job: ClaimedLiquidationBlockchainQueueJob;
  },
): Promise<{
  blockchain: BlockchainClientConfig;
  explorerUrl: string;
}> {
  const blockchainCode = validateBlockchainCode(
    input.job.blockchain_code,
  );

  const { data, error } = await input.supabase.rpc(
    "fetch_liquidation_blockchain_config",
    {
      p_queue_id: input.job.queue_id,
    },
  );

  if (error) {
    console.error(
      "FETCH_LIQUIDATION_BLOCKCHAIN_CONFIG_FAILED",
      {
        queueId: input.job.queue_id,
        blockchainCode,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );

    throw new AppError(
      error.message ||
        "LIQUIDATION_BLOCKCHAIN_CONFIG_FETCH_FAILED",
    );
  }

  if (
    !Array.isArray(data) ||
    data.length !== 1 ||
    data[0] === null ||
    typeof data[0] !== "object" ||
    Array.isArray(data[0])
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_BLOCKCHAIN_CONFIG_RESPONSE",
    );
  }

  const row = data[0] as Record<string, unknown>;

  if (row.code !== blockchainCode) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_CODE_MISMATCH",
    );
  }

  if (
    typeof row.chain_id !== "string" &&
    typeof row.chain_id !== "number"
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CHAIN_ID",
    );
  }

  const chainId = Number(row.chain_id);

  if (
    !Number.isSafeInteger(chainId) ||
    chainId <= 0
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CHAIN_ID",
    );
  }

  const blockchain: BlockchainClientConfig = {
    code: blockchainCode,

    chain_id: chainId,

    rpc_url: requiredHttpUrl(
      row.rpc_url,
      "INVALID_BLOCKCHAIN_RPC_URL",
    ),

    contract_address: requiredString(
      row.contract_address,
      "TOKEN_CONTRACT_ADDRESS_REQUIRED",
    ),

    native_currency_code: requiredString(
      row.native_currency_code,
      "NATIVE_CURRENCY_CODE_REQUIRED",
    ),

    treasury_wallet_address: requiredString(
      row.treasury_wallet_address,
      "LIQUIDATION_TREASURY_WALLET_REQUIRED",
    ),
  };

  const explorerUrl = requiredHttpUrl(
    row.explorer_url,
    "INVALID_BLOCKCHAIN_EXPLORER_URL",
  );

  return {
    blockchain,
    explorerUrl,
  };
}

/*
 * ==========================================================
 * SIGNATURE PREPARATION AND RECOVERY
 * ==========================================================
 */

async function fetchSignedTransfer(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    job: ClaimedLiquidationBlockchainQueueJob;
    client: BlockchainClient;
    blockchain: BlockchainClientConfig;
  },
): Promise<{
  signed: SignedTokenTransfer;
  payload: Record<string, unknown>;
}> {
  if (
    input.job.blockchain_code !==
      input.client.blockchainCode ||
    input.blockchain.code !==
      input.client.blockchainCode ||
    input.blockchain.chain_id !==
      input.client.chainId
  ) {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_CLIENT_MISMATCH",
    );
  }

  function restoreForBlockchain(
    payload: Record<string, unknown>,
  ): SignedTokenTransfer {
    if (
      payload.blockchain_code !==
        input.client.blockchainCode ||
      String(payload.chain_id) !==
        String(input.client.chainId) ||
      typeof payload.contract_address !== "string" ||
      payload.contract_address.toLowerCase() !==
        input.client.contractAddress.toLowerCase()
    ) {
      throw new AppError(
        "LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH",
      );
    }

    const signed = restoreSignedTransfer(
      payload,
      input.job,
      input.client.treasuryAddress,
    );

    if (
      signed.to.toLowerCase() !==
      input.client.treasuryAddress.toLowerCase()
    ) {
      throw new AppError(
        "LIQUIDATION_TREASURY_ADDRESS_MISMATCH",
      );
    }

    return signed;
  }

  /*
   * Reuse a saved signature on its original blockchain.
   * Never silently replace it with a new signature.
   */
  if (input.job.signed_payload) {
    return {
      signed: restoreForBlockchain(
        input.job.signed_payload,
      ),
      payload: input.job.signed_payload,
    };
  }

  const signedTransfer = await signTransfer({
    fromIndex: validateWalletIndex(
      input.job.wallet_index,
    ),

    expectedOwner:
      input.job.sender_wallet_address,

    to: input.client.treasuryAddress,

    amount: validateCollateralAmount(
      input.job.collateral,
    ),

    fee: "0",

    client: input.client,

    blockchain: input.blockchain,
  });

  validateSignedTransferForJob(
    signedTransfer,
    input.job,
    input.client.treasuryAddress,
  );

  /*
   * Save the blockchain identity with the signature.
   * Configuration recovery uses these fields.
   */
  const payload = {
    ...storeSignedTransfer(signedTransfer),

    blockchain_code:
      input.client.blockchainCode,

    chain_id:
      String(input.client.chainId),

    contract_address:
      input.client.contractAddress,
  };

  const { data, error } = await input.supabase.rpc(
    "save_liquidation_blockchain_signed_payload",
    {
      p_queue_id: input.job.queue_id,
      p_signed_payload: payload,
    },
  );

  if (error) {
    console.error(
      "SAVE_LIQUIDATION_SIGNED_PAYLOAD_RPC_FAILED",
      {
        queueId: input.job.queue_id,
        liquidationJobId:
          input.job.liquidation_job_id,
        blockchainCode:
          input.client.blockchainCode,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_SAVE_LIQUIDATION_SIGNED_PAYLOAD",
    );
  }

  const result = data as SaveSignedPayloadResult | null;

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
   * Another invocation may have saved first.
   * Use only the signature returned by PostgreSQL.
   */
  return {
    signed: restoreForBlockchain(
      result.signed_payload,
    ),
    payload: result.signed_payload,
  };
}

/*
 * ==========================================================
 * RECORD SUBMISSION
 * ==========================================================
 */

async function recordBlockchainSubmission(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    queueId: string;
    txHash: string;
  },
): Promise<void> {
  const txHash = validateTransactionHash(
    input.txHash,
  );

  let lastError: string | null = null;

  /*
   * Retry only the database update.
   * Do not resubmit the blockchain transfer.
   */
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const { error } = await input.supabase.rpc(
      "record_liquidation_blockchain_submission",
      {
        p_queue_id: input.queueId,
        p_tx_hash: txHash,
      },
    );

    if (!error) {
      return;
    }

    lastError = error.message;

    console.error(
      "RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION_RPC_FAILED",
      {
        attempt,
        queueId: input.queueId,
        txHash,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );
  }

  throw new AppError(
    lastError ||
      "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION",
  );
}

/*
 * ==========================================================
 * RECORD CONFIRMATION
 * ==========================================================
 */

async function confirmBlockchainTransfer(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    job: ClaimedLiquidationBlockchainQueueJob;
    txHash: string;
    explorerUrl: string;
  },
): Promise<void> {
  const txHash = validateTransactionHash(
    input.txHash,
  );

  const explorerUrl = buildExplorerUrl(
    input.explorerUrl,
    txHash,
  );

  let lastError: string | null = null;

  /*
   * Retry only database confirmation.
   * The blockchain transfer has already completed.
   */
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const { error } = await input.supabase.rpc(
      "confirm_liquidation_blockchain_transfer",
      {
        p_queue_id: input.job.queue_id,
        p_tx_hash: txHash,
        p_explorer_url: explorerUrl,
      },
    );

    if (!error) {
      return;
    }

    lastError = error.message;

    console.error(
      "CONFIRM_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
      {
        attempt,
        queueId: input.job.queue_id,
        liquidationJobId:
          input.job.liquidation_job_id,
        blockchainCode:
          input.job.blockchain_code,
        txHash,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );
  }

  throw new AppError(
    lastError ||
      "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_CONFIRMATION",
  );
}

/*
 * ==========================================================
 * RECORD FAILURE
 * ==========================================================
 */

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
  const errorMessage = input.error instanceof Error
    ? input.error.message
    : String(input.error);

  const { error } = await input.supabase.rpc(
    "fail_liquidation_blockchain_transfer",
    {
      p_queue_id: input.queueId,
      p_error_message: errorMessage,

      /*
       * Preserve a submitted transaction for recovery.
       */
      p_tx_hash: input.txHash,
    },
  );

  if (error) {
    console.error(
      "FAIL_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
      {
        queueId: input.queueId,
        txHash: input.txHash,
        originalError: errorMessage,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_FAILURE",
    );
  }
}

/*
 * ==========================================================
 * PROCESS ONE CLAIMED LIQUIDATION JOB
 * ==========================================================
 */

export async function processLiquidationBlockchainJob(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    job: ClaimedLiquidationBlockchainQueueJob;
  },
): Promise<ProcessedLiquidationBlockchainJob> {
  let blockchainConfirmed = false;
  let blockchainSubmitted = false;
  let submissionAuthorizationRequested = false;
  let txHash: string | null = null;

  try {
    /*
     * Retain a known hash before configuration or other
     * validation can fail.
     */
    txHash = readQueuedTransactionHash(input.job);
    blockchainSubmitted = txHash !== null;

    validateClaimedJob(input.job);

    const {
      blockchain,
      explorerUrl,
    } = await fetchLiquidationBlockchainConfig({
      supabase: input.supabase,
      job: input.job,
    });

    const client = createBlockchainClient(blockchain);

    let confirmedHash: string;

    if (txHash !== null) {
      /*
       * Recover the exact submitted transaction.
       * Do not sign or submit another transfer.
       */
      const blockchainResult =
        await waitForRelayedTokenTransfer(
          txHash,
          client,
        );

      confirmedHash = validateTransactionHash(
        blockchainResult.txHash,
      );
    } else {
      /*
       * Returns both the restored transfer and the exact
       * JSON payload saved by PostgreSQL.
       */
      const preparedTransfer = await fetchSignedTransfer({
        supabase: input.supabase,
        job: input.job,
        client,
        blockchain,
      });

      /*
       * The gate may commit even if its response is lost.
       * Do not automatically retry authorization.
       */
      submissionAuthorizationRequested = true;

      await beginBlockchainSubmission({
        supabase: input.supabase,
        queueId: input.job.queue_id,
        payload: preparedTransfer.payload,
      });

      const blockchainResult =
        await relayTrackedTransferWithPermit(
          preparedTransfer.signed,
          client,
          {
            onSubmitted: async (
              submittedHash: string,
            ) => {
              txHash = validateTransactionHash(
                submittedHash,
              );

              blockchainSubmitted = true;

              await recordBlockchainSubmission({
                supabase: input.supabase,
                queueId: input.job.queue_id,
                txHash,
              });
            },
          },
        );

      confirmedHash = validateTransactionHash(
        blockchainResult.txHash,
      );
    }

    if (
      txHash !== null &&
      txHash.toLowerCase() !== confirmedHash.toLowerCase()
    ) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_HASH_MISMATCH",
      );
    }

    txHash = confirmedHash;
    blockchainSubmitted = true;
    blockchainConfirmed = true;

    /*
     * Accounting remains blocked until PostgreSQL
     * records blockchain confirmation.
     */
    await confirmBlockchainTransfer({
      supabase: input.supabase,
      job: input.job,
      txHash,
      explorerUrl,
    });

    return {
      queue_id: input.job.queue_id,
      liquidation_job_id: input.job.liquidation_job_id,
      success: true,
      blockchain_confirmed: true,
      database_confirmed: true,
      tx_hash: txHash,
      error: null,
    };
  } catch (error) {
    const originalError = error instanceof Error
      ? error.message
      : String(error);

    try {
      /*
       * The updated failure RPC preserves the signature,
       * hash and submission marker.
       */
      await markLiquidationBlockchainFailed({
        supabase: input.supabase,
        queueId: input.job.queue_id,
        txHash,
        error,
      });
    } catch (stateError) {
      const stateErrorMessage = stateError instanceof Error
        ? stateError.message
        : String(stateError);

      console.error(
        "LIQUIDATION_BLOCKCHAIN_FAILURE_STATE_NOT_RECORDED",
        {
          queueId: input.job.queue_id,
          liquidationJobId: input.job.liquidation_job_id,
          blockchainCode: input.job.blockchain_code,
          txHash,
          submissionAuthorizationRequested,
          originalError,
          stateError: stateErrorMessage,
        },
      );

      throw stateError;
    }

    if (txHash !== null) {
      console.error(
        "LIQUIDATION_BLOCKCHAIN_REQUIRES_RECEIPT_RECOVERY",
        {
          queueId: input.job.queue_id,
          liquidationJobId: input.job.liquidation_job_id,
          blockchainCode: input.job.blockchain_code,
          txHash,
          blockchainConfirmed,
          error: originalError,
        },
      );
    } else if (submissionAuthorizationRequested) {
      console.error(
        "LIQUIDATION_SUBMISSION_AUTHORIZATION_OR_OUTCOME_UNCERTAIN",
        {
          queueId: input.job.queue_id,
          liquidationJobId: input.job.liquidation_job_id,
          blockchainCode: input.job.blockchain_code,
          error: originalError,
        },
      );
    }

    return {
      queue_id: input.job.queue_id,
      liquidation_job_id: input.job.liquidation_job_id,
      success: false,
      blockchain_confirmed: blockchainConfirmed,
      database_confirmed: false,
      tx_hash: txHash,
      error: originalError,
    };
  }
}

async function beginBlockchainSubmission(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;
    queueId: string;
    payload: Record<string, unknown>;
  },
): Promise<void> {
  /*
   * Do not retry this RPC automatically.
   * If its response is lost, submission authorization
   * may already have committed.
   */
  const { data, error } = await input.supabase.rpc(
    "begin_liquidation_blockchain_submission",
    {
      p_queue_id: input.queueId,
      p_signed_payload: input.payload,
    },
  );

  if (error) {
    console.error(
      "BEGIN_LIQUIDATION_BLOCKCHAIN_SUBMISSION_FAILED",
      {
        queueId: input.queueId,
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      },
    );

    throw new AppError(
      error.message ||
        "LIQUIDATION_SUBMISSION_AUTHORIZATION_FAILED",
    );
  }

  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_SUBMISSION_AUTHORIZATION",
    );
  }

  const result = data as Record<string, unknown>;

  if (
    result.success !== true ||
    result.queue_id !== input.queueId
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_SUBMISSION_AUTHORIZATION",
    );
  }
}

// import {
//   AppError,
// } from "../app-error.ts";

// import {
//   createSupabaseServiceClient,
// } from "../supabase-client.ts";

// import {
//   createBlockchainClient,
//   type BlockchainClientConfig,
// } from "../blockchain/client.ts";

// import {
//   signTransfer,
//   type BlockchainClient,
//   type SignedTokenTransfer,
// } from "../blockchain/permit.ts";

// import {
//   relayTrackedTransferWithPermit,
//   waitForRelayedTokenTransfer,
// } from "../blockchain/transfer.ts";

// import {
//   restoreSignedTransfer,
//   storeSignedTransfer,
//   validateSignedTransferForJob,
// } from "./liquidation-blockchain-queue-job.ts";

// import type {
//   ClaimedLiquidationBlockchainQueueJob,
// } from "../types/claimed-liquidation-blockchain-queue-job.ts";

// import type {
//   ProcessedLiquidationBlockchainJob,
// } from "../types/processed-liquidation-blockchain-job.ts";

// import type {
//   SaveSignedPayloadResult,
// } from "../types/save-signed-payload-result.ts";

// /*
//  * ==========================================================
//  * VALIDATION HELPERS
//  * ==========================================================
//  */

// function requiredString(
//   value: unknown,
//   errorCode: string,
// ): string {
//   if (
//     typeof value !== "string" ||
//     !value.trim()
//   ) {
//     throw new AppError(errorCode);
//   }

//   return value.trim();
// }

// function requiredHttpUrl(
//   value: unknown,
//   errorCode: string,
// ): string {
//   const text = requiredString(value, errorCode);

//   try {
//     const url = new URL(text);

//     if (
//       url.protocol !== "https:" &&
//       url.protocol !== "http:"
//     ) {
//       throw new Error("Invalid protocol");
//     }
//   } catch {
//     throw new AppError(errorCode);
//   }

//   return text;
// }

// function validateBlockchainCode(
//   value: unknown,
// ): string {
//   if (
//     typeof value !== "string" ||
//     !/^[a-z0-9_-]+$/.test(value)
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_BLOCKCHAIN_CODE",
//     );
//   }

//   return value;
// }

// function validateWalletIndex(
//   value: string | number,
// ): number {
//   if (
//     (typeof value !== "string" &&
//       typeof value !== "number") ||
//     String(value).trim() === ""
//   ) {
//     throw new AppError(
//       "INVALID_USER_WALLET_INDEX",
//     );
//   }

//   const walletIndex = Number(value);

//   if (
//     !Number.isSafeInteger(walletIndex) ||
//     walletIndex < 0
//   ) {
//     throw new AppError(
//       "INVALID_USER_WALLET_INDEX",
//     );
//   }

//   return walletIndex;
// }

// function validateCollateralAmount(
//   value: string,
// ): string {
//   const amount = requiredString(
//     value,
//     "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
//   );

//   const numericAmount = Number(amount);

//   if (
//     !/^\d+(\.\d+)?$/.test(amount) ||
//     !Number.isFinite(numericAmount) ||
//     numericAmount <= 0
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
//     );
//   }

//   return amount;
// }

// function validateTransactionHash(
//   value: unknown,
// ): string {
//   const txHash = requiredString(
//     value,
//     "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
//   );

//   if (!/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_BLOCKCHAIN_TRANSACTION_HASH",
//     );
//   }

//   return txHash;
// }

// function readQueuedTransactionHash(
//   job: ClaimedLiquidationBlockchainQueueJob,
// ): string | null {
//   if (job.tx_hash === null) {
//     return null;
//   }

//   return validateTransactionHash(job.tx_hash);
// }

// function validateClaimedJob(
//   job: ClaimedLiquidationBlockchainQueueJob,
// ): void {
//   requiredString(
//     job.queue_id,
//     "LIQUIDATION_QUEUE_ID_REQUIRED",
//   );

//   requiredString(
//     job.liquidation_job_id,
//     "LIQUIDATION_JOB_ID_REQUIRED",
//   );

//   validateBlockchainCode(job.blockchain_code);

//   if (job.manual_review_required) {
//     throw new AppError(
//       "LIQUIDATION_BLOCKCHAIN_MANUAL_REVIEW_REQUIRED",
//     );
//   }

//   if (job.queue_status !== "processing") {
//     throw new AppError(
//       "LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_PROCESSING",
//     );
//   }

//   validateWalletIndex(job.wallet_index);
//   validateCollateralAmount(job.collateral);
// }

// function buildExplorerUrl(
//   explorerUrl: string,
//   txHash: string,
// ): string {
//   const base = requiredHttpUrl(
//     explorerUrl,
//     "INVALID_BLOCKCHAIN_EXPLORER_URL",
//   ).replace(/\/+$/, "");

//   const hash = validateTransactionHash(txHash);

//   return base.toLowerCase().endsWith("/tx")
//     ? `${base}/${hash}`
//     : `${base}/tx/${hash}`;
// }

// /*
//  * ==========================================================
//  * BLOCKCHAIN CONFIGURATION
//  * ==========================================================
//  */

// async function fetchLiquidationBlockchainConfig(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     job: ClaimedLiquidationBlockchainQueueJob;
//   },
// ): Promise<{
//   blockchain: BlockchainClientConfig;
//   explorerUrl: string;
// }> {
//   const blockchainCode = validateBlockchainCode(
//     input.job.blockchain_code,
//   );

//   const { data, error } = await input.supabase.rpc(
//     "fetch_liquidation_blockchain_config",
//     {
//       p_queue_id: input.job.queue_id,
//     },
//   );

//   if (error) {
//     console.error(
//       "FETCH_LIQUIDATION_BLOCKCHAIN_CONFIG_FAILED",
//       {
//         queueId: input.job.queue_id,
//         blockchainCode,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );

//     throw new AppError(
//       error.message ||
//         "LIQUIDATION_BLOCKCHAIN_CONFIG_FETCH_FAILED",
//     );
//   }

//   if (
//     !Array.isArray(data) ||
//     data.length !== 1 ||
//     data[0] === null ||
//     typeof data[0] !== "object" ||
//     Array.isArray(data[0])
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_BLOCKCHAIN_CONFIG_RESPONSE",
//     );
//   }

//   const row = data[0] as Record<string, unknown>;

//   if (row.code !== blockchainCode) {
//     throw new AppError(
//       "LIQUIDATION_BLOCKCHAIN_CODE_MISMATCH",
//     );
//   }

//   if (
//     typeof row.chain_id !== "string" &&
//     typeof row.chain_id !== "number"
//   ) {
//     throw new AppError(
//       "INVALID_BLOCKCHAIN_CHAIN_ID",
//     );
//   }

//   const chainId = Number(row.chain_id);

//   if (
//     !Number.isSafeInteger(chainId) ||
//     chainId <= 0
//   ) {
//     throw new AppError(
//       "INVALID_BLOCKCHAIN_CHAIN_ID",
//     );
//   }

//   const blockchain: BlockchainClientConfig = {
//     code: blockchainCode,

//     chain_id: chainId,

//     rpc_url: requiredHttpUrl(
//       row.rpc_url,
//       "INVALID_BLOCKCHAIN_RPC_URL",
//     ),

//     contract_address: requiredString(
//       row.contract_address,
//       "TOKEN_CONTRACT_ADDRESS_REQUIRED",
//     ),

//     native_currency_code: requiredString(
//       row.native_currency_code,
//       "NATIVE_CURRENCY_CODE_REQUIRED",
//     ),

//     treasury_wallet_address: requiredString(
//       row.treasury_wallet_address,
//       "LIQUIDATION_TREASURY_WALLET_REQUIRED",
//     ),
//   };

//   const explorerUrl = requiredHttpUrl(
//     row.explorer_url,
//     "INVALID_BLOCKCHAIN_EXPLORER_URL",
//   );

//   return {
//     blockchain,
//     explorerUrl,
//   };
// }

// /*
//  * ==========================================================
//  * SIGNATURE PREPARATION AND RECOVERY
//  * ==========================================================
//  */

// async function fetchSignedTransfer(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     job: ClaimedLiquidationBlockchainQueueJob;
//     client: BlockchainClient;
//     blockchain: BlockchainClientConfig;
//   },
// ): Promise<{
//   signed: SignedTokenTransfer;
//   payload: Record<string, unknown>;
// }> {
//   if (
//     input.job.blockchain_code !==
//       input.client.blockchainCode ||
//     input.blockchain.code !==
//       input.client.blockchainCode ||
//     input.blockchain.chain_id !==
//       input.client.chainId
//   ) {
//     throw new AppError(
//       "LIQUIDATION_BLOCKCHAIN_CLIENT_MISMATCH",
//     );
//   }

//   function restoreForBlockchain(
//     payload: Record<string, unknown>,
//   ): SignedTokenTransfer {
//     if (
//       payload.blockchain_code !==
//         input.client.blockchainCode ||
//       String(payload.chain_id) !==
//         String(input.client.chainId) ||
//       typeof payload.contract_address !== "string" ||
//       payload.contract_address.toLowerCase() !==
//         input.client.contractAddress.toLowerCase()
//     ) {
//       throw new AppError(
//         "LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH",
//       );
//     }

//     const signed = restoreSignedTransfer(
//       payload,
//       input.job,
//     );

//     if (
//       signed.to.toLowerCase() !==
//       input.client.treasuryAddress.toLowerCase()
//     ) {
//       throw new AppError(
//         "LIQUIDATION_TREASURY_ADDRESS_MISMATCH",
//       );
//     }

//     return signed;
//   }

//   /*
//    * Reuse a saved signature on its original blockchain.
//    * Never silently replace it with a new signature.
//    */
//   if (input.job.signed_payload) {
//     return {
//       signed: restoreForBlockchain(
//         input.job.signed_payload,
//       ),
//       payload: input.job.signed_payload,
//     };
//   }

//   const signedTransfer = await signTransfer({
//     fromIndex: validateWalletIndex(
//       input.job.wallet_index,
//     ),

//     expectedOwner:
//       input.job.sender_wallet_address,

//     to: input.client.treasuryAddress,

//     amount: validateCollateralAmount(
//       input.job.collateral,
//     ),

//     fee: "0",

//     client: input.client,

//     blockchain: input.blockchain,
//   });

//   validateSignedTransferForJob(
//     signedTransfer,
//     input.job,
//   );

//   /*
//    * Save the blockchain identity with the signature.
//    * Configuration recovery uses these fields.
//    */
//   const payload = {
//     ...storeSignedTransfer(signedTransfer),

//     blockchain_code:
//       input.client.blockchainCode,

//     chain_id:
//       String(input.client.chainId),

//     contract_address:
//       input.client.contractAddress,
//   };

//   const { data, error } = await input.supabase.rpc(
//     "save_liquidation_blockchain_signed_payload",
//     {
//       p_queue_id: input.job.queue_id,
//       p_signed_payload: payload,
//     },
//   );

//   if (error) {
//     console.error(
//       "SAVE_LIQUIDATION_SIGNED_PAYLOAD_RPC_FAILED",
//       {
//         queueId: input.job.queue_id,
//         liquidationJobId:
//           input.job.liquidation_job_id,
//         blockchainCode:
//           input.client.blockchainCode,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );

//     throw new AppError(
//       error.message ||
//         "FAILED_TO_SAVE_LIQUIDATION_SIGNED_PAYLOAD",
//     );
//   }

//   const result = data as SaveSignedPayloadResult | null;

//   if (
//     !result ||
//     result.success !== true ||
//     !result.signed_payload
//   ) {
//     throw new AppError(
//       "SIGNED_LIQUIDATION_PAYLOAD_NOT_RETURNED",
//     );
//   }

//   /*
//    * Another invocation may have saved first.
//    * Use only the signature returned by PostgreSQL.
//    */
//   return {
//     signed: restoreForBlockchain(
//       result.signed_payload,
//     ),
//     payload: result.signed_payload,
//   };
// }

// /*
//  * ==========================================================
//  * RECORD SUBMISSION
//  * ==========================================================
//  */

// async function recordBlockchainSubmission(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     queueId: string;
//     txHash: string;
//   },
// ): Promise<void> {
//   const txHash = validateTransactionHash(
//     input.txHash,
//   );

//   let lastError: string | null = null;

//   /*
//    * Retry only the database update.
//    * Do not resubmit the blockchain transfer.
//    */
//   for (let attempt = 1; attempt <= 3; attempt += 1) {
//     const { error } = await input.supabase.rpc(
//       "record_liquidation_blockchain_submission",
//       {
//         p_queue_id: input.queueId,
//         p_tx_hash: txHash,
//       },
//     );

//     if (!error) {
//       return;
//     }

//     lastError = error.message;

//     console.error(
//       "RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION_RPC_FAILED",
//       {
//         attempt,
//         queueId: input.queueId,
//         txHash,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );
//   }

//   throw new AppError(
//     lastError ||
//       "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_SUBMISSION",
//   );
// }

// /*
//  * ==========================================================
//  * RECORD CONFIRMATION
//  * ==========================================================
//  */

// async function confirmBlockchainTransfer(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     job: ClaimedLiquidationBlockchainQueueJob;
//     txHash: string;
//     explorerUrl: string;
//   },
// ): Promise<void> {
//   const txHash = validateTransactionHash(
//     input.txHash,
//   );

//   const explorerUrl = buildExplorerUrl(
//     input.explorerUrl,
//     txHash,
//   );

//   let lastError: string | null = null;

//   /*
//    * Retry only database confirmation.
//    * The blockchain transfer has already completed.
//    */
//   for (let attempt = 1; attempt <= 3; attempt += 1) {
//     const { error } = await input.supabase.rpc(
//       "confirm_liquidation_blockchain_transfer",
//       {
//         p_queue_id: input.job.queue_id,
//         p_tx_hash: txHash,
//         p_explorer_url: explorerUrl,
//       },
//     );

//     if (!error) {
//       return;
//     }

//     lastError = error.message;

//     console.error(
//       "CONFIRM_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
//       {
//         attempt,
//         queueId: input.job.queue_id,
//         liquidationJobId:
//           input.job.liquidation_job_id,
//         blockchainCode:
//           input.job.blockchain_code,
//         txHash,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );
//   }

//   throw new AppError(
//     lastError ||
//       "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_CONFIRMATION",
//   );
// }

// /*
//  * ==========================================================
//  * RECORD FAILURE
//  * ==========================================================
//  */

// async function markLiquidationBlockchainFailed(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     queueId: string;
//     txHash: string | null;
//     error: unknown;
//   },
// ): Promise<void> {
//   const errorMessage = input.error instanceof Error
//     ? input.error.message
//     : String(input.error);

//   const { error } = await input.supabase.rpc(
//     "fail_liquidation_blockchain_transfer",
//     {
//       p_queue_id: input.queueId,
//       p_error_message: errorMessage,

//       /*
//        * Preserve a submitted transaction for recovery.
//        */
//       p_tx_hash: input.txHash,
//     },
//   );

//   if (error) {
//     console.error(
//       "FAIL_LIQUIDATION_BLOCKCHAIN_TRANSFER_RPC_FAILED",
//       {
//         queueId: input.queueId,
//         txHash: input.txHash,
//         originalError: errorMessage,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );

//     throw new AppError(
//       error.message ||
//         "FAILED_TO_RECORD_LIQUIDATION_BLOCKCHAIN_FAILURE",
//     );
//   }
// }

// /*
//  * ==========================================================
//  * PROCESS ONE CLAIMED LIQUIDATION JOB
//  * ==========================================================
//  */

// export async function processLiquidationBlockchainJob(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     job: ClaimedLiquidationBlockchainQueueJob;
//   },
// ): Promise<ProcessedLiquidationBlockchainJob> {
//   let blockchainConfirmed = false;
//   let blockchainSubmitted = false;
//   let submissionAuthorizationRequested = false;
//   let txHash: string | null = null;

//   try {
//     /*
//      * Retain a known hash before configuration or other
//      * validation can fail.
//      */
//     txHash = readQueuedTransactionHash(input.job);
//     blockchainSubmitted = txHash !== null;

//     validateClaimedJob(input.job);

//     const {
//       blockchain,
//       explorerUrl,
//     } = await fetchLiquidationBlockchainConfig({
//       supabase: input.supabase,
//       job: input.job,
//     });

//     const client = createBlockchainClient(blockchain);

//     let confirmedHash: string;

//     if (txHash !== null) {
//       /*
//        * Recover the exact submitted transaction.
//        * Do not sign or submit another transfer.
//        */
//       const blockchainResult =
//         await waitForRelayedTokenTransfer(
//           txHash,
//           client,
//         );

//       confirmedHash = validateTransactionHash(
//         blockchainResult.txHash,
//       );
//     } else {
//       /*
//        * Returns both the restored transfer and the exact
//        * JSON payload saved by PostgreSQL.
//        */
//       const preparedTransfer = await fetchSignedTransfer({
//         supabase: input.supabase,
//         job: input.job,
//         client,
//         blockchain,
//       });

//       /*
//        * The gate may commit even if its response is lost.
//        * Do not automatically retry authorization.
//        */
//       submissionAuthorizationRequested = true;

//       await beginBlockchainSubmission({
//         supabase: input.supabase,
//         queueId: input.job.queue_id,
//         payload: preparedTransfer.payload,
//       });

//       const blockchainResult =
//         await relayTrackedTransferWithPermit(
//           preparedTransfer.signed,
//           client,
//           {
//             onSubmitted: async (
//               submittedHash: string,
//             ) => {
//               txHash = validateTransactionHash(
//                 submittedHash,
//               );

//               blockchainSubmitted = true;

//               await recordBlockchainSubmission({
//                 supabase: input.supabase,
//                 queueId: input.job.queue_id,
//                 txHash,
//               });
//             },
//           },
//         );

//       confirmedHash = validateTransactionHash(
//         blockchainResult.txHash,
//       );
//     }

//     if (
//       txHash !== null &&
//       txHash.toLowerCase() !== confirmedHash.toLowerCase()
//     ) {
//       throw new AppError(
//         "BLOCKCHAIN_TRANSACTION_HASH_MISMATCH",
//       );
//     }

//     txHash = confirmedHash;
//     blockchainSubmitted = true;
//     blockchainConfirmed = true;

//     /*
//      * Accounting remains blocked until PostgreSQL
//      * records blockchain confirmation.
//      */
//     await confirmBlockchainTransfer({
//       supabase: input.supabase,
//       job: input.job,
//       txHash,
//       explorerUrl,
//     });

//     return {
//       queue_id: input.job.queue_id,
//       liquidation_job_id: input.job.liquidation_job_id,
//       success: true,
//       blockchain_confirmed: true,
//       database_confirmed: true,
//       tx_hash: txHash,
//       error: null,
//     };
//   } catch (error) {
//     const originalError = error instanceof Error
//       ? error.message
//       : String(error);

//     try {
//       /*
//        * The updated failure RPC preserves the signature,
//        * hash and submission marker.
//        */
//       await markLiquidationBlockchainFailed({
//         supabase: input.supabase,
//         queueId: input.job.queue_id,
//         txHash,
//         error,
//       });
//     } catch (stateError) {
//       const stateErrorMessage = stateError instanceof Error
//         ? stateError.message
//         : String(stateError);

//       console.error(
//         "LIQUIDATION_BLOCKCHAIN_FAILURE_STATE_NOT_RECORDED",
//         {
//           queueId: input.job.queue_id,
//           liquidationJobId: input.job.liquidation_job_id,
//           blockchainCode: input.job.blockchain_code,
//           txHash,
//           submissionAuthorizationRequested,
//           originalError,
//           stateError: stateErrorMessage,
//         },
//       );

//       throw stateError;
//     }

//     if (txHash !== null) {
//       console.error(
//         "LIQUIDATION_BLOCKCHAIN_REQUIRES_RECEIPT_RECOVERY",
//         {
//           queueId: input.job.queue_id,
//           liquidationJobId: input.job.liquidation_job_id,
//           blockchainCode: input.job.blockchain_code,
//           txHash,
//           blockchainConfirmed,
//           error: originalError,
//         },
//       );
//     } else if (submissionAuthorizationRequested) {
//       console.error(
//         "LIQUIDATION_SUBMISSION_AUTHORIZATION_OR_OUTCOME_UNCERTAIN",
//         {
//           queueId: input.job.queue_id,
//           liquidationJobId: input.job.liquidation_job_id,
//           blockchainCode: input.job.blockchain_code,
//           error: originalError,
//         },
//       );
//     }

//     return {
//       queue_id: input.job.queue_id,
//       liquidation_job_id: input.job.liquidation_job_id,
//       success: false,
//       blockchain_confirmed: blockchainConfirmed,
//       database_confirmed: false,
//       tx_hash: txHash,
//       error: originalError,
//     };
//   }
// }

// async function beginBlockchainSubmission(
//   input: {
//     supabase: ReturnType<
//       typeof createSupabaseServiceClient
//     >;
//     queueId: string;
//     payload: Record<string, unknown>;
//   },
// ): Promise<void> {
//   /*
//    * Do not retry this RPC automatically.
//    * If its response is lost, submission authorization
//    * may already have committed.
//    */
//   const { data, error } = await input.supabase.rpc(
//     "begin_liquidation_blockchain_submission",
//     {
//       p_queue_id: input.queueId,
//       p_signed_payload: input.payload,
//     },
//   );

//   if (error) {
//     console.error(
//       "BEGIN_LIQUIDATION_BLOCKCHAIN_SUBMISSION_FAILED",
//       {
//         queueId: input.queueId,
//         code: error.code,
//         message: error.message,
//         details: error.details,
//         hint: error.hint,
//       },
//     );

//     throw new AppError(
//       error.message ||
//         "LIQUIDATION_SUBMISSION_AUTHORIZATION_FAILED",
//     );
//   }

//   if (
//     data === null ||
//     typeof data !== "object" ||
//     Array.isArray(data)
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_SUBMISSION_AUTHORIZATION",
//     );
//   }

//   const result = data as Record<string, unknown>;

//   if (
//     result.success !== true ||
//     result.queue_id !== input.queueId
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_SUBMISSION_AUTHORIZATION",
//     );
//   }
// }