import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  blockchainConfig,
} from "../../_shared/blockchain/client.ts";

import {
  executeGoldTokenAdjustment,
} from "../../_shared/blockchain/token-adjustment.ts";

import type {
  GoldTokenAdjustmentType,
} from "../../_shared/blockchain/token-adjustment.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


type PreparationResult = {
  success: boolean;
  adjustment_request_id: string;
  document_number: string | null;
  adjustment_type:
    GoldTokenAdjustmentType;
  quantity: string;
  uom: string;
  currency_code: string;
  country_code: string;
  executed_by: string;
};


type BlockchainRecordResult = {
  success: boolean;
  adjustment_request_id: string;
  blockchain_transaction_id: string;
  tx_hash: string;
  transaction_type: string;
  adjustment_type:
    GoldTokenAdjustmentType;
  quantity: string;
  status: string;
  explorer_url: string | null;
};


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
  return typeof value === "object" &&
    value !== null &&
    !Array.isArray(value);
}


function parsePreparationResult(
  value: unknown,
): PreparationResult {
  if (!isRecord(value)) {
    throw new AppError(
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    );
  }

  const adjustmentType =
    value.adjustment_type;

  if (
    adjustmentType !== "minting" &&
    adjustmentType !== "burning"
  ) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_TYPE",
    );
  }

  const adjustmentRequestId =
    typeof value.adjustment_request_id ===
        "string"
      ? value.adjustment_request_id.trim()
      : "";

  const quantity =
    typeof value.quantity === "string" ||
      typeof value.quantity === "number"
      ? String(value.quantity)
      : "";

  const countryCode =
    typeof value.country_code === "string"
      ? value.country_code.trim()
      : "";

  const executedBy =
    typeof value.executed_by === "string"
      ? value.executed_by.trim()
      : "";

  if (
    !adjustmentRequestId ||
    !quantity ||
    !countryCode ||
    !executedBy
  ) {
    throw new AppError(
      "INVALID_ADJUSTMENT_PREPARATION_RESULT",
    );
  }

  return {
    success:
      value.success === true,

    adjustment_request_id:
      adjustmentRequestId,

    document_number:
      typeof value.document_number ===
          "string"
        ? value.document_number
        : null,

    adjustment_type:
      adjustmentType,

    quantity,

    uom:
      typeof value.uom === "string"
        ? value.uom
        : "gram",

    currency_code:
      typeof value.currency_code ===
          "string"
        ? value.currency_code
        : "gold",

    country_code:
      countryCode,

    executed_by:
      executedBy,
  };
}


function parseBlockchainRecordResult(
  value: unknown,
): BlockchainRecordResult {
  if (!isRecord(value)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );
  }

  const blockchainTransactionId =
    typeof value.blockchain_transaction_id ===
        "string"
      ? value.blockchain_transaction_id.trim()
      : "";

  const adjustmentRequestId =
    typeof value.adjustment_request_id ===
        "string"
      ? value.adjustment_request_id.trim()
      : "";

  const txHash =
    typeof value.tx_hash === "string"
      ? value.tx_hash.trim()
      : "";

  const adjustmentType =
    value.adjustment_type;

  if (
    !blockchainTransactionId ||
    !adjustmentRequestId ||
    !txHash ||
    (
      adjustmentType !== "minting" &&
      adjustmentType !== "burning"
    )
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_RECORD_RESULT",
    );
  }

  return {
    success:
      value.success === true,

    adjustment_request_id:
      adjustmentRequestId,

    blockchain_transaction_id:
      blockchainTransactionId,

    tx_hash:
      txHash,

    transaction_type:
      typeof value.transaction_type ===
          "string"
        ? value.transaction_type
        : "",

    adjustment_type:
      adjustmentType,

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


function getExplorerUrl(
  transactionHash: string,
): string {
  const baseUrl =
    Deno.env
      .get(
        "BLOCKCHAIN_EXPLORER_URL",
      )
      ?.trim();

  if (!baseUrl) {
    throw new AppError(
      "ENV_BLOCKCHAIN_EXPLORER_URL_MISSING",
    );
  }

  return baseUrl.endsWith("/")
    ? `${baseUrl}${transactionHash}`
    : `${baseUrl}/${transactionHash}`;
}


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

    let requestClaimed =
      false;

    let blockchainConfirmed =
      false;

    let postingCommitted =
      false;

    try {
      const body =
        await request.json();

      adjustmentRequestId =
        typeof body.adjustment_request_id ===
            "string"
          ? body.adjustment_request_id.trim()
          : "";

      if (!adjustmentRequestId) {
        return errorResponse(
          "ADJUSTMENT_REQUEST_ID_REQUIRED",
        );
      }

      const forwardedFor =
        request.headers.get(
          "x-forwarded-for",
        );

      const realIp =
        request.headers.get(
          "x-real-ip",
        );

      const ipAddress =
        forwardedFor ||
        realIp ||
        "unknown";

      const supabase =
        createSupabaseClient(request);

      /*
       * Validate and claim the approved request.
       */
      const preparationResponse =
        await supabase.rpc(
          "prepare_my_token_adjustment_execution",
          {
            p_adjustment_request_id:
              adjustmentRequestId,
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
          },
        );

        throw new AppError(
          preparationResponse.error.message,
        );
      }

      const preparation =
        parsePreparationResult(
          preparationResponse.data,
        );

      requestClaimed =
        true;

      /*
       * Execute and confirm the irreversible blockchain
       * transaction.
       */
      const blockchainResult =
        await executeGoldTokenAdjustment(
          {
            adjustment_type:
              preparation.adjustment_type,

            amount:
              preparation.quantity,
          },
        );

      blockchainTransactionHash =
        blockchainResult.tx_hash;

      blockchainConfirmed =
        true;

      const explorerUrl =
        getExplorerUrl(
          blockchainTransactionHash,
        );

      /*
       * Persist the confirmed blockchain transaction before
       * beginning accounting.
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
              blockchainConfig.treasuryAddress,

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

      blockchainTransactionId =
        blockchainRecord
          .blockchain_transaction_id;

      /*
       * Complete all accounting in one PostgreSQL transaction.
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
            blockchainTransactionId,
            blockchainTransactionHash,
          },
        );

        throw new AppError(
          completionResponse.error.message,
        );
      }

      postingCommitted =
        true;

      return successResponse(
        completionResponse.data,
      );
    } catch (error) {
      const message =
        getErrorMessage(error);

      /*
       * Release the database claim only if blockchain
       * execution was never confirmed.
       *
       * Once blockchain execution succeeds, releasing the
       * request could allow the same adjustment to be executed
       * twice.
       */
      if (
        requestClaimed &&
        !blockchainConfirmed &&
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
              },
            );
          }
        } catch (releaseError) {
          console.error(
            "TOKEN_ADJUSTMENT_RELEASE_ERROR",
            {
              adjustmentRequestId,

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
          blockchainTransactionId,
          blockchainTransactionHash,
          blockchainConfirmed,
          postingCommitted,
          error:
            message,
        },
      );

      return errorResponse(
        message ||
          "FAILED_TO_ADJUST_TOKENS",
      );
    }
  },
);