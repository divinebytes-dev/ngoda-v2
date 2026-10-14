import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  TransactionStatus,
  TransactionType,
} from "../../_shared/enums.ts";

import {
  FinancialActivityType,
} from "../../_shared/types/financial-activity-type.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

import type {
  Json,
} from "../../_shared/database.types.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import {
  signTransfer,
} from "../../_shared/blockchain/permit.ts";

import {
  relayTrackedTransferWithPermit,
} from "../../_shared/blockchain/transfer.ts";

import {
  createBlockchainClient,
} from "../../_shared/blockchain/client.ts";

import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";

type RpcError = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
};

type RpcResult = {
  data: unknown;
  error: RpcError | null;
};

type RpcClient = {
  rpc: (
    functionName: string,
    args?: Record<string, unknown>,
  ) => Promise<RpcResult>;
};

type NumericValue = string | number;

type GoldTransferContext = {
  sender_id: string;
  country_code: string;
  wallet_address: string;
  wallet_index: NumericValue;
  version_time: NumericValue;
};

type GoldTransferPreparation = {
  sender_id: string;
  sender_wallet_address: string;
  sender_wallet_index: NumericValue;
  receiver_id: string;
  receiver_wallet_address: string;
  treasury_id: string;
  treasury_wallet_address: string;
  country_code: string;
  blockchain_code: string;
  fiscal_year: number;
  period: number;
  document_prefix: string;
  amount: NumericValue;
  fee: NumericValue;
  total_amount: NumericValue;
};

type GoldTransferCompletion = {
  success: boolean;
  document_number: string;
  amount: string;
  fee: string;
  explorer_url: string;
  receiver_notification_id: string | null;
  device_tokens: string[] | null;
  push_title: string | null;
  push_body: string | null;
  push_reference: string | null;
};

type BlockchainRpcRow = {
  code: string;
  chain_id: NumericValue;
  rpc_url: string;
  contract_address: string;
  native_currency_code: string;
  explorer_url: string;
};

type BlockchainConfig =
  SupportedBlockchainConfig & {
    explorer_url: string;
  };

type TransferRequest = {
  transaction?: TransactionData;
  blockchain_code?: string;
};

function asRpcClient(
  client: unknown,
): RpcClient {
  return client as RpcClient;
}

function firstRow<T>(
  data: unknown,
): T | null {
  if (Array.isArray(data)) {
    return data.length > 0
      ? data[0] as T
      : null;
  }

  if (
    data !== null &&
    typeof data === "object"
  ) {
    return data as T;
  }

  return null;
}

function scalarValue(
  data: unknown,
): string | null {
  if (
    typeof data === "string" ||
    typeof data === "number"
  ) {
    return String(data);
  }

  if (
    Array.isArray(data) &&
    data.length > 0
  ) {
    const first = data[0];

    if (
      typeof first === "string" ||
      typeof first === "number"
    ) {
      return String(first);
    }

    if (
      first &&
      typeof first === "object"
    ) {
      const value =
        Object.values(first)[0];

      if (
        typeof value === "string" ||
        typeof value === "number"
      ) {
        return String(value);
      }
    }
  }

  return null;
}

function normalizeAddress(
  address: string,
): string {
  return address.trim().toLowerCase();
}

function validateBlockchainCode(
  value: unknown,
): string {
  if (typeof value !== "string") {
    throw new AppError(
      "BLOCKCHAIN_CODE_REQUIRED",
    );
  }

  const code =
    value.trim().toLowerCase();

  if (!code) {
    throw new AppError(
      "BLOCKCHAIN_CODE_REQUIRED",
    );
  }

  if (!/^[a-z0-9_-]+$/.test(code)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CODE",
    );
  }

  return code;
}

function validateChainId(
  value: NumericValue,
): number {
  const chainId = Number(value);

  if (
    !Number.isSafeInteger(chainId) ||
    chainId <= 0
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CHAIN_ID",
    );
  }

  return chainId;
}

function validatePositiveAmount(
  value: NumericValue,
  errorMessage: string,
): string {
  const amount = String(value);
  const parsed = Number(amount);

  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    throw new AppError(errorMessage);
  }

  return amount;
}

function validateNonNegativeAmount(
  value: NumericValue,
  errorMessage: string,
): string {
  const amount = String(value);
  const parsed = Number(amount);

  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    throw new AppError(errorMessage);
  }

  return amount;
}

function clientIpAddress(
  request: Request,
): string {
  const forwardedFor =
    request.headers.get("x-forwarded-for");

  if (forwardedFor) {
    const firstAddress =
      forwardedFor.split(",")[0]?.trim();

    if (firstAddress) {
      return firstAddress;
    }
  }

  return (
    request.headers
      .get("x-real-ip")
      ?.trim() ?? "unknown"
  );
}

function buildExplorerUrl(
  explorerUrl: string,
  txHash: string,
): string {
  const base = explorerUrl.trim();

  if (!base) {
    throw new AppError(
      "BLOCKCHAIN_EXPLORER_URL_NOT_CONFIGURED",
    );
  }

  if (!/^https?:\/\//i.test(base)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_EXPLORER_URL",
    );
  }

  const url =
    base.replace(/\/+$/, "");

  return `${url}/tx/${txHash}`;
}

function logRpcError(
  label: string,
  error: RpcError,
  context: Record<string, unknown> = {},
): void {
  console.error(label, {
    code: error.code,
    message: error.message,
    details: error.details,
    hint: error.hint,
    ...context,
  });
}

async function rpcRow<T>(
  client: RpcClient,
  functionName: string,
  args: Record<string, unknown>,
  errorMessage: string,
): Promise<T> {
  const { data, error } =
    await client.rpc(
      functionName,
      args,
    );

  if (error) {
    logRpcError(
      errorMessage,
      error,
      { functionName },
    );

    throw new AppError(
      error.message || errorMessage,
    );
  }

  const row = firstRow<T>(data);

  if (!row) {
    throw new AppError(errorMessage);
  }

  return row;
}

async function updateFailedState(
  authRpc: RpcClient,
  transactionId: string,
  failureMessage: string,
): Promise<boolean> {
  try {
    const { error } =
      await authRpc.rpc(
        "update_my_transaction_state",
        {
          p_transaction_id:
            transactionId,
          p_status:
            TransactionStatus.failed,
          p_message:
            failureMessage,
        },
      );

    if (error) {
      logRpcError(
        "Gold-transfer state update failed",
        error,
        { transactionId },
      );

      return false;
    }

    return true;
  } catch (error) {
    console.error(
      "Gold-transfer state update failed",
      {
        transactionId,
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return false;
  }
}

/*
 * ==========================================================
 * BLOCKCHAIN CONFIGURATION
 * ==========================================================
 *
 * Uses the existing:
 *
 * public.fetch_active_supported_blockchain
 *
 * No direct database table access.
 */
async function fetchBlockchainConfig(
  authRpc: RpcClient,
  blockchainCode: string,
): Promise<BlockchainConfig> {
  const row =
    await rpcRow<BlockchainRpcRow>(
      authRpc,
      "fetch_active_supported_blockchain",
      {
        p_blockchain_code:
          blockchainCode,
      },
      "BLOCKCHAIN_CONFIG_FETCH_FAILED",
    );

  if (
    row.code?.toLowerCase() !==
    blockchainCode
  ) {
    throw new AppError(
      "BLOCKCHAIN_CONFIG_CODE_MISMATCH",
    );
  }

  if (
    !row.rpc_url ||
    !row.contract_address
  ) {
    throw new AppError(
      "BLOCKCHAIN_CONFIG_INCOMPLETE",
    );
  }

  if (!row.explorer_url?.trim()) {
    throw new AppError(
      "BLOCKCHAIN_EXPLORER_URL_NOT_CONFIGURED",
    );
  }

  return {
    code: blockchainCode,
    chain_id:
      validateChainId(row.chain_id),
    rpc_url: row.rpc_url,
    contract_address:
      row.contract_address,
    native_currency_code:
      row.native_currency_code,
    explorer_url:
      row.explorer_url.trim(),
  };
}

/*
 * ==========================================================
 * FINANCIAL INTELLIGENCE
 * ==========================================================
 */
async function recordTransferFinancialActivities(
  serviceSupabase:
    ReturnType<
      typeof createSupabaseServiceClient
    >,
  context: GoldTransferContext,
  preparation: GoldTransferPreparation,
  completion: GoldTransferCompletion,
  totalAmount: string,
  transactionId: string,
): Promise<void> {
  try {
    const result =
      await recordFinancialActivity(
        serviceSupabase,
        {
          reference:
            completion.document_number,
          userId:
            context.sender_id,
          countryCode:
            context.country_code,
          currencyCode: "gold",
          transactionType:
            TransactionType
              .gold_token_transfer,
          activityType:
            FinancialActivityType
              .investment_transfer_out,
          amount: totalAmount,
          amountUsd: "0.000000",
          cashAmount: "0.000000",
          cashAmountUsd: "0.000000",
          goldQuantity: totalAmount,
          investmentCostUsd:
            "0.000000",
        },
      );

    if (result.status === "failed") {
      console.error(
        "GOLD_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_FAILED",
        {
          transactionId,
          reference:
            completion.document_number,
          senderId:
            context.sender_id,
          totalGoldOut:
            totalAmount,
          error: result.error,
        },
      );
    }
  } catch (error) {
    console.error(
      "GOLD_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_EXCEPTION",
      {
        transactionId,
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  }

  try {
    const result =
      await recordFinancialActivity(
        serviceSupabase,
        {
          reference:
            completion.document_number,
          userId:
            preparation.receiver_id,
          countryCode:
            context.country_code,
          currencyCode: "gold",
          transactionType:
            TransactionType
              .gold_token_transfer,
          activityType:
            FinancialActivityType
              .investment_transfer_in,
          amount:
            completion.amount,
          amountUsd: "0.000000",
          cashAmount: "0.000000",
          cashAmountUsd: "0.000000",
          goldQuantity:
            completion.amount,
          investmentCostUsd:
            "0.000000",
        },
      );

    if (result.status === "failed") {
      console.error(
        "GOLD_TRANSFER_RECEIVER_FINANCIAL_INTELLIGENCE_FAILED",
        {
          transactionId,
          reference:
            completion.document_number,
          receiverId:
            preparation.receiver_id,
          goldQuantity:
            completion.amount,
          error: result.error,
        },
      );
    }
  } catch (error) {
    console.error(
      "GOLD_TRANSFER_RECEIVER_FINANCIAL_INTELLIGENCE_EXCEPTION",
      {
        transactionId,
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  }
}

/*
 * ==========================================================
 * PUSH NOTIFICATION
 * ==========================================================
 */
async function sendTransferNotification(
  completion: GoldTransferCompletion,
  transaction: TransactionData,
  transactionId: string,
  blockchainTransactionId:
    string | null,
): Promise<void> {
  const deviceTokens = (
    completion.device_tokens ?? []
  ).filter(
    (token): token is string =>
      typeof token === "string" &&
      token.trim().length > 0,
  );

  if (
    deviceTokens.length === 0 ||
    !completion.push_title ||
    !completion.push_body
  ) {
    return;
  }

  try {
    await sendPushNotification({
      tokens: deviceTokens,
      title: completion.push_title,
      body: completion.push_body,
      data: {
        notification_id:
          completion
            .receiver_notification_id ?? "",
        reference:
          completion.push_reference ??
          transaction.r,
        transaction_type:
          TransactionType
            .gold_token_transfer,
        document_number:
          completion.document_number,
      },
    });
  } catch (error) {
    console.error(
      "GOLD_TRANSFER_PUSH_NOTIFICATION_FAILED",
      {
        transactionId,
        blockchainTransactionId,
        notificationId:
          completion
            .receiver_notification_id,
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  }
}

/*
 * ==========================================================
 * GOLD TRANSFER EDGE FUNCTION
 * ==========================================================
 */
Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    let authRpc: RpcClient | null = null;

    let transactionId:
      string | null = null;

    let blockchainTransactionId:
      string | null = null;

    let blockchainTransactionHash:
      string | null = null;

    let blockchainCode:
      string | null = null;

    let postingCommitted = false;
    let submissionAttempted = false;

    try {
      if (request.method !== "POST") {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
        );
      }

      const authSupabase =
        createSupabaseClient(request);

      authRpc =
        asRpcClient(authSupabase);

      /*
       * REQUEST VALIDATION
       */
      let body: TransferRequest;

      try {
        body = await request.json();
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      if (
        !body ||
        typeof body !== "object" ||
        !body.transaction
      ) {
        throw new AppError(
          "TRANSACTION_DATA_IS_MISSING",
        );
      }

      blockchainCode =
        validateBlockchainCode(
          body.blockchain_code,
        );

      const transaction =
        body.transaction;

      if (transaction.v !== "v6") {
        throw new AppError(
          "OPERATION_NOT_ALLOWED",
        );
      }

      const transactionJson =
        transaction as unknown as Json;

      /*
       * FETCH AUTHENTICATED CONTEXT
       */
      const context =
        await rpcRow<GoldTransferContext>(
          authRpc,
          "fetch_my_gold_transfer_context",
          {
            p_v: transaction.v,
          },
          "GOLD_TRANSFER_CONTEXT_FAILED",
        );

      if (!context.sender_id) {
        throw new AppError(
          "SENDER_NOT_FOUND",
        );
      }

      if (!context.country_code) {
        throw new AppError(
          "USER_COUNTRY_NOT_CONFIGURED",
        );
      }

      if (!context.wallet_address) {
        throw new AppError(
          "USER_WALLET_NOT_CONFIGURED",
        );
      }

      const versionTime =
        Number(context.version_time);

      if (
        !Number.isFinite(versionTime) ||
        versionTime <= 0
      ) {
        throw new AppError(
          "INVALID_TRANSACTION_VERSION_TIME",
        );
      }

      /*
       * EXISTING BLOCKCHAIN RPC
       *
       * fetch_active_supported_blockchain
       *
       * Now includes explorer_url.
       */
      const blockchain =
        await fetchBlockchainConfig(
          authRpc,
          blockchainCode,
        );

      /*
       * CREATE TRANSACTION STATE
       */
      const {
        data: stateData,
        error: stateError,
      } = await authRpc.rpc(
        "create_my_gold_transfer_state",
        {
          p_transaction:
            transactionJson,
          p_blockchain_code:
            blockchainCode,
        },
      );

      if (stateError) {
        logRpcError(
          "Gold-transfer state creation failed",
          stateError,
        );

        if (
          stateError.code === "23505" ||
          stateError.message?.includes(
            "TRANSACTION_REPLAY",
          )
        ) {
          throw new AppError(
            "TRANSACTION_REPLAY",
            409,
          );
        }

        throw new AppError(
          stateError.message ||
            "TRANSACTION_STATE_CREATE_FAILED",
        );
      }

      transactionId =
        scalarValue(stateData);

      if (!transactionId) {
        throw new AppError(
          "TRANSACTION_STATE_CREATE_FAILED",
        );
      }

      /*
       * VERIFY SIGNED TRANSACTION
       */
      TransactionVerificationService
        .validateTransactionFields(
          transaction,
        );

      TransactionVerificationService
        .validateTransactionTimestamp(
          transaction,
          versionTime,
        );

      const validSignature =
        TransactionVerificationService
          .verifyTransactionSignature(
            transaction,
            context.wallet_address,
          );

      if (!validSignature) {
        throw new AppError(
          "USER_SIGNATURE_VERIFICATION_FAILED",
        );
      }

      /*
       * SERVICE CLIENT
       */
      const serviceSupabase =
        createSupabaseServiceClient();

      const serviceRpc =
        asRpcClient(
          serviceSupabase,
        );

      /*
       * PREPARE GOLD TRANSFER
       */
      const preparation =
        await rpcRow<GoldTransferPreparation>(
          serviceRpc,
          "prepare_gold_transfer",
          {
            p_sender_id:
              context.sender_id,
            p_transaction:
              transactionJson,
            p_country_code:
              context.country_code,
            p_transaction_state_id:
              transactionId,
            p_blockchain_code:
              blockchainCode,
          },
          "GOLD_TRANSFER_PREPARATION_FAILED",
        );

      /*
       * VALIDATE PREPARATION
       */
      if (
        preparation.sender_id !==
        context.sender_id
      ) {
        throw new AppError(
          "GOLD_TRANSFER_SENDER_MISMATCH",
        );
      }

      if (
        normalizeAddress(
          preparation
            .sender_wallet_address,
        ) !==
        normalizeAddress(
          context.wallet_address,
        )
      ) {
        throw new AppError(
          "GOLD_TRANSFER_SENDER_WALLET_MISMATCH",
        );
      }

      if (
        preparation.country_code !==
        context.country_code
      ) {
        throw new AppError(
          "GOLD_TRANSFER_COUNTRY_MISMATCH",
        );
      }

      if (
        preparation.blockchain_code !==
        blockchainCode
      ) {
        throw new AppError(
          "BLOCKCHAIN_CODE_MISMATCH",
        );
      }

      if (
        !preparation.receiver_id ||
        !preparation
          .receiver_wallet_address
      ) {
        throw new AppError(
          "RECEIVER_WALLET_NOT_CONFIGURED",
        );
      }

      if (
        !preparation.treasury_id ||
        !preparation
          .treasury_wallet_address
      ) {
        throw new AppError(
          "TREASURY_WALLET_NOT_CONFIGURED",
        );
      }

      const senderWalletIndex =
        Number(
          preparation
            .sender_wallet_index,
        );

      if (
        !Number.isSafeInteger(
          senderWalletIndex,
        ) ||
        senderWalletIndex < 0
      ) {
        throw new AppError(
          "INVALID_SENDER_WALLET_INDEX",
        );
      }

      /*
       * CREATE BLOCKCHAIN CLIENT
       */
      const blockchainClient =
        createBlockchainClient({
          ...blockchain,
          treasury_wallet_address:
            preparation
              .treasury_wallet_address,
        });

      if (
        normalizeAddress(
          preparation
            .treasury_wallet_address,
        ) !==
        normalizeAddress(
          blockchainClient
            .treasuryAddress,
        )
      ) {
        throw new AppError(
          "TREASURY_BLOCKCHAIN_ADDRESS_MISMATCH",
        );
      }

      /*
       * Explorer URL from existing RPC.
       *
       * No additional table query.
       */
      const explorerBaseUrl =
        blockchain.explorer_url;

      /*
       * VALIDATE AMOUNTS
       */
      const amount =
        validatePositiveAmount(
          preparation.amount,
          "INVALID_TRANSFER_AMOUNT",
        );

      const fee =
        validateNonNegativeAmount(
          preparation.fee,
          "INVALID_TRANSFER_FEE",
        );

      const totalAmount =
        validatePositiveAmount(
          preparation.total_amount,
          "INVALID_TOTAL_TRANSFER_AMOUNT",
        );

      /*
       * SIGN BLOCKCHAIN TRANSFER
       */
      const signedTransfer =
        await signTransfer({
          fromIndex:
            senderWalletIndex,
          expectedOwner:
            preparation
              .sender_wallet_address,
          to:
            preparation
              .receiver_wallet_address,
          amount,
          fee,
          client:
            blockchainClient,
          blockchain: {
            ...blockchain,
            treasury_wallet_address:
              preparation
                .treasury_wallet_address,
          },
        });

      /*
       * VERIFY TOKEN QUANTITIES
       */
      const tokenDecimals =
        await blockchainClient
          .providerContract
          .decimals();

      const { parseUnits } =
        await import("ethers");

      const expectedTotal =
        parseUnits(
          totalAmount,
          Number(tokenDecimals),
        );

      if (
        signedTransfer.parsedAmount +
          signedTransfer.parsedFee !==
        expectedTotal
      ) {
        throw new AppError(
          "BLOCKCHAIN_TRANSFER_TOTAL_MISMATCH",
        );
      }

      /*
       * SUBMIT BLOCKCHAIN TRANSFER
       */
      submissionAttempted = true;

      const blockchainResult =
        await relayTrackedTransferWithPermit(
          signedTransfer,
          blockchainClient,
          {
            onSubmitted: async (
              txHash: string,
            ) => {
              blockchainTransactionHash =
                txHash;

              const explorerUrl =
                buildExplorerUrl(
                  explorerBaseUrl,
                  txHash,
                );

              /*
               * RECORD THROUGH RPC
               */
              const {
                data: recordData,
                error: recordError,
              } = await serviceRpc.rpc(
                "record_gold_transfer_blockchain_transaction",
                {
                  p_sender_id:
                    context.sender_id,
                  p_transaction:
                    transactionJson,
                  p_country_code:
                    context.country_code,
                  p_transaction_state_id:
                    transactionId,
                  p_tx_hash:
                    txHash,
                  p_explorer_url:
                    explorerUrl,
                  p_blockchain_code:
                    blockchainCode,
                },
              );

              if (recordError) {
                logRpcError(
                  "GOLD_TRANSFER_BLOCKCHAIN_RECORD_FAILED",
                  recordError,
                  {
                    transactionId,
                    blockchainCode,
                    txHash,
                  },
                );

                throw new AppError(
                  "GOLD_TRANSFER_BLOCKCHAIN_RECORD_FAILED",
                );
              }

              blockchainTransactionId =
                scalarValue(
                  recordData,
                );

              if (
                !blockchainTransactionId
              ) {
                throw new AppError(
                  "BLOCKCHAIN_TRANSACTION_RECORD_NOT_FOUND",
                );
              }
            },
          },
        );

      blockchainTransactionHash =
        blockchainResult.txHash;

      if (
        !blockchainTransactionId ||
        !blockchainTransactionHash
      ) {
        throw new AppError(
          "BLOCKCHAIN_TRANSACTION_RECORD_NOT_FOUND",
        );
      }

      /*
       * COMPLETE ACCOUNTING POSTINGS
       */
      const {
        data: completionData,
        error: completionError,
      } = await serviceRpc.rpc(
        "complete_gold_transfer",
        {
          p_sender_id:
            context.sender_id,
          p_transaction:
            transactionJson,
          p_country_code:
            context.country_code,
          p_transaction_state_id:
            transactionId,
          p_blockchain_transaction_id:
            blockchainTransactionId,
          p_ip_address:
            clientIpAddress(request),
          p_blockchain_code:
            blockchainCode,
        },
      );

      if (completionError) {
        logRpcError(
          "GOLD_TRANSFER_POSTING_FAILED",
          completionError,
          {
            transactionId,
            blockchainTransactionId,
            blockchainTransactionHash,
            blockchainCode,
          },
        );

        throw new AppError(
          completionError.message ||
            "GOLD_TRANSFER_POSTING_FAILED",
        );
      }

      postingCommitted = true;

      const completion =
        firstRow<GoldTransferCompletion>(
          completionData,
        );

      if (!completion) {
        console.error(
          "GOLD_TRANSFER_COMPLETION_RESPONSE_MISSING",
          {
            transactionId,
            blockchainTransactionId,
            blockchainTransactionHash,
          },
        );

        return successResponse({
          success: true,
        });
      }

      /*
       * FINANCIAL INTELLIGENCE
       */
      await recordTransferFinancialActivities(
        serviceSupabase,
        context,
        preparation,
        completion,
        totalAmount,
        transactionId,
      );

      /*
       * PUSH NOTIFICATION
       */
      await sendTransferNotification(
        completion,
        transaction,
        transactionId,
        blockchainTransactionId,
      );

      return successResponse({
        success: true,
      });
    } catch (error) {
      /*
       * FAILURE HANDLING
       */
      if (
        authRpc &&
        transactionId &&
        !postingCommitted &&
        !submissionAttempted
      ) {
        const failureMessage =
          error instanceof Error
            ? error.message
            : "GOLD_TRANSFER_FAILED";

        await updateFailedState(
          authRpc,
          transactionId,
          failureMessage,
        );
      }

      console.error(
        "GOLD_TRANSFER_ERROR",
        {
          transactionId,
          blockchainCode,
          blockchainTransactionId,
          blockchainTransactionHash,
          submissionAttempted,
          postingCommitted,
          requiresReconciliation:
            submissionAttempted &&
            !postingCommitted,
          error:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );

      return errorResponse(
        error,
        "GOLD_TRANSFER_FAILED",
      );
    }
  },
);