import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  executeGoldTokenAdjustment,
} from "../../_shared/blockchain/token-adjustments.ts";

import type {
  GoldTokenAdjustmentType,
} from "../../_shared/blockchain/token-adjustments.ts";

import type {
  BlockchainClientConfig,
} from "../../_shared/blockchain/client.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

/*
 * ==========================================================
 * TYPES
 * ==========================================================
 */

type PreparationResult = {
  success: boolean;
  adjustment_request_id: string;
  document_number: string | null;
  adjustment_type: GoldTokenAdjustmentType;
  quantity: string;
  uom: string;
  currency_code: string;
  country_code: string;
  executed_by: string;
  blockchain: BlockchainClientConfig;
  explorer_url: string;
};

type BlockchainRecordResult = {
  success: boolean;
  adjustment_request_id: string;
  blockchain_transaction_id: string;
  tx_hash: string;
  transaction_type: string;
  adjustment_type: GoldTokenAdjustmentType;
  quantity: string;
  status: string;
  explorer_url: string | null;
};

/*
 * ==========================================================
 * HELPERS
 * ==========================================================
 */

function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }

  return String(error);
}

function isRecord(
  value: unknown,
): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

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

function requiredQuantity(
  value: unknown,
): string {
  const quantity =
    typeof value === "string" ||
    typeof value === "number"
      ? String(value).trim()
      : "";

  if (
    !/^\d+(?:\.\d+)?$/.test(quantity) ||
    !/[1-9]/.test(quantity)
  ) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_AMOUNT",
    );
  }

  return quantity;
}

function parseAdjustmentType(
  value: unknown,
): GoldTokenAdjustmentType {
  if (
    value !== "minting" &&
    value !== "burning"
  ) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_TYPE",
    );
  }

  return value;
}

/*
 * ==========================================================
 * PARSE PREPARATION RESULT
 * ==========================================================
 */

function parsePreparationResult(
  value: unknown,
): PreparationResult {
  if (
    !isRecord(value) ||
    value.success !== true
  ) {
    throw new AppError(
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    );
  }

  const adjustmentRequestId =
    requiredString(
      value.adjustment_request_id,
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    );

  const adjustmentType =
    parseAdjustmentType(
      value.adjustment_type,
    );

  const quantity =
    requiredQuantity(
      value.quantity,
    );

  const countryCode =
    requiredString(
      value.country_code,
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    ).toLowerCase();

  if (countryCode !== "zw") {
    throw new AppError(
      "CENTRAL_MINTING_TREASURY_ONLY",
    );
  }

  const executedBy =
    requiredString(
      value.executed_by,
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    );

  /*
   * Original inventory purchase currency.
   *
   * This can be USD, ZIG, ZAR, etc.
   *
   * Do not require GOLD here.
   * The adjustment quantity represents GOLD grams,
   * independently of the purchase currency.
   */
  const currencyCode =
    requiredString(
      value.currency_code,
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    ).toLowerCase();

  const uom =
    requiredString(
      value.uom,
      "INVALID_TOKEN_ADJUSTMENT_UOM",
    ).toLowerCase();

  if (uom !== "gram") {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_UOM",
    );
  }

  /*
   * Blockchain configuration returned by SQL.
   *
   * The selected blockchain was supplied by Treasury
   * and saved by prepare_my_token_adjustment_execution.
   */
  const blockchainCode =
    requiredString(
      value.blockchain_code,
      "BLOCKCHAIN_CODE_REQUIRED",
    ).toLowerCase();

  const nativeCurrencyCode =
    requiredString(
      value.native_currency_code,
      "BLOCKCHAIN_NATIVE_CURRENCY_REQUIRED",
    ).toLowerCase();

  const rpcUrl =
    requiredString(
      value.rpc_url,
      "BLOCKCHAIN_RPC_URL_MISSING",
    );

  const contractAddress =
    requiredString(
      value.contract_address,
      "TOKEN_CONTRACT_ADDRESS_MISSING",
    );

  const treasuryWalletAddress =
    requiredString(
      value.treasury_wallet_address,
      "TREASURY_WALLET_ADDRESS_MISSING",
    );

  const explorerUrl =
    requiredString(
      value.explorer_url,
      "BLOCKCHAIN_EXPLORER_URL_MISSING",
    );

  const chainId =
    typeof value.chain_id === "number" ||
    typeof value.chain_id === "string"
      ? Number(value.chain_id)
      : NaN;

  if (
    !Number.isSafeInteger(chainId) ||
    chainId <= 0
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CHAIN_ID",
    );
  }

  /*
   * Use the existing BlockchainClientConfig.
   *
   * No name or blockchain_type properties.
   * No duplicate configuration interface.
   */
  const blockchain: BlockchainClientConfig = {
    code: blockchainCode,
    native_currency_code: nativeCurrencyCode,
    chain_id: chainId,
    rpc_url: rpcUrl,
    contract_address: contractAddress,
    treasury_wallet_address: treasuryWalletAddress,
  };

  return {
    success: true,
    adjustment_request_id: adjustmentRequestId,

    document_number:
      typeof value.document_number === "string"
        ? value.document_number
        : null,

    adjustment_type: adjustmentType,
    quantity,
    uom,
    currency_code: currencyCode,
    country_code: countryCode,
    executed_by: executedBy,
    blockchain,
    explorer_url: explorerUrl,
  };
}

/*
 * ==========================================================
 * PARSE BLOCKCHAIN RECORD RESULT
 * ==========================================================
 */

function parseBlockchainRecordResult(
  value: unknown,
): BlockchainRecordResult {
  if (
    !isRecord(value) ||
    value.success !== true
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );
  }

  const adjustmentRequestId =
    requiredString(
      value.adjustment_request_id,
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );

  const blockchainTransactionId =
    requiredString(
      value.blockchain_transaction_id,
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );

  const txHash =
    requiredString(
      value.tx_hash,
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );

  const adjustmentType =
    parseAdjustmentType(
      value.adjustment_type,
    );

  return {
    success: true,
    adjustment_request_id: adjustmentRequestId,
    blockchain_transaction_id: blockchainTransactionId,
    tx_hash: txHash,

    transaction_type:
      typeof value.transaction_type === "string"
        ? value.transaction_type
        : "",

    adjustment_type: adjustmentType,

    quantity:
      typeof value.quantity === "string" ||
      typeof value.quantity === "number"
        ? String(value.quantity)
        : "0",

    status:
      typeof value.status === "string"
        ? value.status
        : "pending",

    explorer_url:
      typeof value.explorer_url === "string"
        ? value.explorer_url
        : null,
  };
}

/*
 * ==========================================================
 * BUILD EXPLORER URL
 * ==========================================================
 */

function getExplorerUrl(
  baseUrl: string,
  transactionHash: string,
): string {
  const normalizedBaseUrl =
    baseUrl.trim().replace(/\/+$/, "");

  if (!normalizedBaseUrl) {
    throw new AppError(
      "BLOCKCHAIN_EXPLORER_URL_MISSING",
    );
  }

  return `${normalizedBaseUrl}/tx/${transactionHash}`;
}

/*
 * ==========================================================
 * EDGE FUNCTION
 * ==========================================================
 */

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    let adjustmentRequestId:
      string | null = null;

    let blockchainTransactionId:
      string | null = null;

    let blockchainTransactionHash:
      string | null = null;

    let blockchainCode:
      string | null = null;

    let requestClaimed = false;
    let blockchainExecutionStarted = false;
    let blockchainConfirmed = false;
    let postingCommitted = false;

    try {
      /*
       * ======================================================
       * STEP 1: VALIDATE REQUEST
       * ======================================================
       *
       * Flutter sends:
       *
       * {
       *   adjustment_request_id: string,
       *   blockchain_code: string
       * }
       */
      const body: unknown =
        await request.json();

      if (!isRecord(body)) {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      adjustmentRequestId =
        requiredString(
          body.adjustment_request_id,
          "ADJUSTMENT_REQUEST_ID_REQUIRED",
        );

      blockchainCode =
        requiredString(
          body.blockchain_code,
          "BLOCKCHAIN_CODE_REQUIRED",
        ).toLowerCase();

      const selectedBlockchainCode =
        blockchainCode;

      const forwardedFor =
        request.headers.get(
          "x-forwarded-for",
        );

      const realIp =
        request.headers.get(
          "x-real-ip",
        );

      const ipAddress =
        forwardedFor?.split(",")[0]?.trim() ||
        realIp?.trim() ||
        "unknown";

      const supabase =
        createSupabaseClient(request);

      /*
       * ======================================================
       * STEP 2: PREPARE APPROVED ADJUSTMENT
       * ======================================================
       *
       * Finance created the request without a blockchain.
       * Accounts approved it without a blockchain.
       *
       * Treasury selects the blockchain at execution.
       *
       * SQL validates the selection and atomically sets:
       *
       * executed_by = treasury user ID
       * blockchain_code = selected blockchain code
       */
      const preparationResponse =
        await supabase.rpc(
          "prepare_my_token_adjustment_execution",
          {
            p_adjustment_request_id:
              adjustmentRequestId,

            p_blockchain_code:
              selectedBlockchainCode,
          },
        );

      if (preparationResponse.error) {
        console.error(
          "TOKEN_ADJUSTMENT_PREPARATION_RPC_FAILED",
          {
            code:
              preparationResponse.error.code,

            message:
              preparationResponse.error.message,

            details:
              preparationResponse.error.details,

            hint:
              preparationResponse.error.hint,

            adjustmentRequestId,
            blockchainCode,
          },
        );

        throw new AppError(
          preparationResponse.error.message,
        );
      }

      /*
       * The preparation RPC has committed its claim.
       * Mark it before parsing so a parsing error can
       * safely release the claim.
       */
      requestClaimed = true;

      const preparation =
        parsePreparationResult(
          preparationResponse.data,
        );

      if (
        preparation.adjustment_request_id !==
        adjustmentRequestId
      ) {
        throw new AppError(
          "ADJUSTMENT_REQUEST_ID_MISMATCH",
        );
      }

      /*
       * Ensure SQL returned the blockchain Treasury
       * selected, not another configured blockchain.
       */
      if (
        preparation.blockchain.code !==
        selectedBlockchainCode
      ) {
        throw new AppError(
          "BLOCKCHAIN_CODE_MISMATCH",
        );
      }

      blockchainCode =
        preparation.blockchain.code;

      /*
       * ======================================================
       * STEP 3: EXECUTE BLOCKCHAIN TRANSACTION
       * ======================================================
       *
       * Once execution starts, never automatically release
       * the request claim.
       *
       * A failed or timed-out execution may already have
       * broadcast a blockchain transaction.
       */
      blockchainExecutionStarted = true;

      const blockchainResult =
        await executeGoldTokenAdjustment({
          adjustment_type:
            preparation.adjustment_type,

          amount:
            preparation.quantity,

          blockchain:
            preparation.blockchain,
        });

      blockchainTransactionHash =
        requiredString(
          blockchainResult.tx_hash,
          "BLOCKCHAIN_TRANSACTION_HASH_REQUIRED",
        );

      /*
       * The shared execution helper must return only
       * after the transaction has been confirmed.
       */
      blockchainConfirmed = true;

      /*
       * ======================================================
       * STEP 4: BUILD EXPLORER URL
       * ======================================================
       */
      const explorerUrl =
        getExplorerUrl(
          preparation.explorer_url,
          blockchainTransactionHash,
        );

      /*
       * ======================================================
       * STEP 5: RECORD BLOCKCHAIN TRANSACTION
       * ======================================================
       *
       * The SQL function reads blockchain_code from the
       * adjustment request.
       *
       * It must record GOLD as the blockchain token currency,
       * independently of the original inventory purchase
       * currency.
       */
      const blockchainRecordResponse =
        await supabase.rpc(
          "record_my_token_adjustment_blockchain_transaction",
          {
            p_adjustment_request_id:
              adjustmentRequestId,

            p_tx_hash:
              blockchainTransactionHash,

            p_treasury_address:
              preparation.blockchain
                .treasury_wallet_address,

            p_explorer_url:
              explorerUrl,
          },
        );

      if (blockchainRecordResponse.error) {
        console.error(
          "TOKEN_ADJUSTMENT_BLOCKCHAIN_RECORD_RPC_FAILED",
          {
            code:
              blockchainRecordResponse.error.code,

            message:
              blockchainRecordResponse.error.message,

            details:
              blockchainRecordResponse.error.details,

            hint:
              blockchainRecordResponse.error.hint,

            adjustmentRequestId,
            blockchainCode,
            blockchainTransactionHash,
          },
        );

        throw new AppError(
          blockchainRecordResponse.error.message,
        );
      }

      const blockchainRecord =
        parseBlockchainRecordResult(
          blockchainRecordResponse.data,
        );

      if (
        blockchainRecord.adjustment_request_id !==
          adjustmentRequestId ||
        blockchainRecord.tx_hash.toLowerCase() !==
          blockchainTransactionHash.toLowerCase()
      ) {
        throw new AppError(
          "BLOCKCHAIN_RECORD_MISMATCH",
        );
      }

      blockchainTransactionId =
        blockchainRecord.blockchain_transaction_id;

      /*
       * ======================================================
       * STEP 6: COMPLETE FINANCIAL ACCOUNTING
       * ======================================================
       *
       * This RPC handles financial entries, treasury
       * GOLD wallet balances, wallet snapshots and
       * final adjustment status in one SQL transaction.
       *
       * Zimbabwe is the central minting/burning country.
       * Blockchain-specific balances remain separate.
       */
      const completionResponse =
        await supabase.rpc(
          "complete_my_token_adjustment_execution",
          {
            p_adjustment_request_id:
              adjustmentRequestId,

            p_blockchain_transaction_id:
              blockchainTransactionId,

            p_ip_address:
              ipAddress,
          },
        );

      if (completionResponse.error) {
        console.error(
          "TOKEN_ADJUSTMENT_POSTING_FAILED",
          {
            code:
              completionResponse.error.code,

            message:
              completionResponse.error.message,

            details:
              completionResponse.error.details,

            hint:
              completionResponse.error.hint,

            adjustmentRequestId,
            blockchainCode,
            blockchainTransactionId,
            blockchainTransactionHash,
          },
        );

        throw new AppError(
          completionResponse.error.message,
        );
      }

      postingCommitted = true;

      return successResponse(
        completionResponse.data,
      );
    } catch (error) {
      const message =
        getErrorMessage(error);

      /*
       * ======================================================
       * RELEASE CLAIM ONLY BEFORE BLOCKCHAIN EXECUTION
       * ======================================================
       *
       * release_my_token_adjustment_execution clears
       * executed_by only.
       *
       * It does not clear blockchain_code.
       */
      if (
        requestClaimed &&
        !blockchainExecutionStarted &&
        adjustmentRequestId
      ) {
        try {
          const supabase =
            createSupabaseClient(request);

          const releaseResponse =
            await supabase.rpc(
              "release_my_token_adjustment_execution",
              {
                p_adjustment_request_id:
                  adjustmentRequestId,
              },
            );

          if (releaseResponse.error) {
            console.error(
              "TOKEN_ADJUSTMENT_RELEASE_FAILED",
              {
                code:
                  releaseResponse.error.code,

                message:
                  releaseResponse.error.message,

                details:
                  releaseResponse.error.details,

                hint:
                  releaseResponse.error.hint,

                adjustmentRequestId,
                blockchainCode,
              },
            );
          }
        } catch (releaseError) {
          console.error(
            "TOKEN_ADJUSTMENT_RELEASE_ERROR",
            {
              adjustmentRequestId,
              blockchainCode,

              error:
                getErrorMessage(
                  releaseError,
                ),
            },
          );
        }
      }

      console.error(
        "TOKEN_ADJUSTMENT_ERROR",
        {
          adjustmentRequestId,
          blockchainCode,
          blockchainTransactionId,
          blockchainTransactionHash,
          blockchainExecutionStarted,
          blockchainConfirmed,
          postingCommitted,
          error: message,
        },
      );

      return errorResponse(
        message ||
          "FAILED_TO_ADJUST_TOKENS",
      );
    }
  },
);