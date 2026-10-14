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

import { AppError } from "../../_shared/app-error.ts";

import {
  TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

import type { Json } from "../../_shared/database.types.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import {
  createBlockchainClient,
} from "../../_shared/blockchain/client.ts";

import type {
  BlockchainClientConfig,
} from "../../_shared/blockchain/client.ts";

import {
  signTransfer,
} from "../../_shared/blockchain/permit.ts";

import {
  relayTransferWithPermit,
} from "../../_shared/blockchain/transfer.ts";

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

type GoldSellContext = {
  seller_id: string;
  country_code: string;
  wallet_address: string;
  wallet_index: NumericValue;
  version_time: NumericValue;
};

type SupportedBlockchain = {
  code: string;
  chain_id: NumericValue;
  rpc_url: string;
  contract_address: string;
  native_currency_code: string;
  explorer_url: string;
};

type GoldSellPreparation = {
  seller_id: string;
  seller_wallet_address: string;
  seller_wallet_index: NumericValue;

  treasury_id: string;
  treasury_wallet_address: string;

  country_code: string;
  blockchain_code: string;

  fiscal_year: number;
  period: number;
  document_prefix: string;

  input_amount: NumericValue;
  input_currency: string;

  token_quantity: NumericValue;
  token_fee_equivalent: NumericValue;

  gross_amount: NumericValue;
  net_amount: NumericValue;
  fiat_fee: NumericValue;
  trading_spread: NumericValue;
  government_tax: NumericValue;
};

type GoldSellCompletion = {
  success: boolean;

  document_number: string;
  token_document_number: string;

  quantity: string;
  gross_amount: string;
  net_amount: string;
  fee: string;

  explorer_url: string;

  receiver_notification_id: string | null;
  device_tokens: string[] | null;

  push_title: string | null;
  push_body: string | null;
  push_reference: string | null;
};

function asRpcClient(client: unknown): RpcClient {
  return client as RpcClient;
}

function firstRow<T>(data: unknown): T | null {
  if (Array.isArray(data)) {
    return data.length > 0 ? data[0] as T : null;
  }

  if (data !== null && typeof data === "object") {
    return data as T;
  }

  return null;
}

function scalarValue(data: unknown): string | null {
  if (
    typeof data === "string" ||
    typeof data === "number"
  ) {
    return String(data);
  }

  if (Array.isArray(data) && data.length > 0) {
    const first = data[0];

    if (
      typeof first === "string" ||
      typeof first === "number"
    ) {
      return String(first);
    }

    if (first && typeof first === "object") {
      const value = Object.values(first)[0];

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

function normalizeAddress(address: string): string {
  return address.trim().toLowerCase();
}

function normalizeBlockchainCode(value: unknown): string {
  if (typeof value !== "string") {
    throw new AppError("BLOCKCHAIN_CODE_REQUIRED");
  }

  const code = value.trim().toLowerCase();

  if (!code) {
    throw new AppError("BLOCKCHAIN_CODE_REQUIRED");
  }

  return code;
}

function buildExplorerUrl(
  explorerBase: string,
  transactionHash: string,
): string {
  const base = explorerBase?.trim();

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

  if (!/^0x[0-9a-fA-F]{64}$/.test(transactionHash)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_TRANSACTION_HASH",
    );
  }

  return `${base.replace(/\/+$/, "")}/tx/${transactionHash}`;
}

function clientIpAddress(request: Request): string {
  const forwardedFor = request.headers.get("x-forwarded-for");

  if (forwardedFor) {
    const first = forwardedFor.split(",")[0]?.trim();

    if (first) {
      return first;
    }
  }

  return request.headers.get("x-real-ip")?.trim() ??
    "unknown";
}

function positiveNumericString(
  value: NumericValue,
  errorCode: string,
): string {
  const normalized = String(value);
  const parsed = Number(normalized);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new AppError(errorCode);
  }

  return normalized;
}

function nonNegativeNumericString(
  value: NumericValue,
  errorCode: string,
): string {
  const normalized = String(value);
  const parsed = Number(normalized);

  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new AppError(errorCode);
  }

  return normalized;
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
  errorCode: string,
): Promise<T> {
  const { data, error } = await client.rpc(
    functionName,
    args,
  );

  if (error) {
    logRpcError(errorCode, error, { functionName });

    throw new AppError(error.message || errorCode);
  }

  const row = firstRow<T>(data);

  if (!row) {
    throw new AppError(errorCode);
  }

  return row;
}

async function fetchBlockchainConfig(
  authRpc: RpcClient,
  blockchainCode: string,
): Promise<SupportedBlockchain> {
  const blockchain = await rpcRow<SupportedBlockchain>(
    authRpc,
    "fetch_active_supported_blockchain",
    {
      p_blockchain_code: blockchainCode,
    },
    "BLOCKCHAIN_NOT_FOUND_OR_INACTIVE",
  );

  if (normalizeBlockchainCode(blockchain.code) !== blockchainCode) {
    throw new AppError("BLOCKCHAIN_CODE_MISMATCH");
  }

  const chainId = Number(blockchain.chain_id);

  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    throw new AppError("INVALID_BLOCKCHAIN_CHAIN_ID");
  }

  if (
    !blockchain.rpc_url ||
    !blockchain.contract_address ||
    !blockchain.explorer_url
  ) {
    throw new AppError("BLOCKCHAIN_CONFIG_INCOMPLETE");
  }

  return blockchain;
}

async function updateFailedState(
  authRpc: RpcClient,
  transactionId: string,
  failureMessage: string,
): Promise<boolean> {
  try {
    const { error } = await authRpc.rpc(
      "update_my_transaction_state",
      {
        p_transaction_id: transactionId,
        p_status: TransactionStatus.failed,
        p_message: failureMessage,
      },
    );

    if (error) {
      logRpcError(
        "GOLD_SELL_STATE_UPDATE_FAILED",
        error,
        { transactionId },
      );

      return false;
    }

    return true;
  } catch (error) {
    console.error("GOLD_SELL_STATE_UPDATE_FAILED", {
      transactionId,
      error: error instanceof Error
        ? error.message
        : String(error),
    });

    return false;
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  let authRpc: RpcClient | null = null;

  let transactionId: string | null = null;
  let blockchainTransactionId: string | null = null;
  let blockchainTransactionHash: string | null = null;

  let blockchainCode: string | null = null;
  let transactionReference: string | null = null;

  let postingCommitted = false;
  let submissionAttempted = false;
  let requiresReconciliation = false;
  let failureStateUpdated = false;

  let stage = "initialization";

  try {
    if (request.method !== "POST") {
      throw new AppError("METHOD_NOT_ALLOWED");
    }

    /*
     * ========================================================
     * 1. AUTHENTICATED CLIENT AND REQUEST
     * ========================================================
     */
    stage = "read request";

    const authSupabase = createSupabaseClient(request);
    authRpc = asRpcClient(authSupabase);

    let body: {
      transaction?: TransactionData;
      blockchain_code?: string;
    };

    try {
      body = await request.json();
    } catch {
      throw new AppError("INVALID_REQUEST_BODY");
    }

    if (!body.transaction) {
      throw new AppError("TRANSACTION_DATA_IS_MISSING");
    }

    const transaction = body.transaction;

    blockchainCode = normalizeBlockchainCode(
      body.blockchain_code,
    );

    transactionReference = transaction.r;

    if (transaction.v !== "v7") {
      throw new AppError("OPERATION_NOT_ALLOWED");
    }

    const transactionJson = transaction as unknown as Json;

    /*
     * ========================================================
     * 2. AUTHENTICATED SELLER CONTEXT
     * ========================================================
     */
    stage = "fetch seller context";

const context = await rpcRow<GoldSellContext>(
  authSupabase,
  "fetch_my_gold_sell_context",
  {
    p_v: transaction.v,
    p_blockchain_code: blockchainCode,
  },
  "GOLD_SELL_CONTEXT_FAILED",
);

    if (!context.seller_id) {
      throw new AppError("SELLER_NOT_FOUND");
    }

    if (!context.country_code) {
      throw new AppError("USER_COUNTRY_NOT_CONFIGURED");
    }

    if (!context.wallet_address) {
      throw new AppError("USER_WALLET_NOT_CONFIGURED");
    }

    const versionTime = Number(context.version_time);

    if (!Number.isFinite(versionTime) || versionTime <= 0) {
      throw new AppError(
        "INVALID_TRANSACTION_VERSION_TIME",
      );
    }

    /*
     * ========================================================
     * 3. ACTIVE BLOCKCHAIN CONFIGURATION
     * ========================================================
     */
    stage = "fetch blockchain configuration";

    const blockchain = await fetchBlockchainConfig(
      authRpc,
      blockchainCode,
    );

    /*
     * ========================================================
     * 4. CREATE PROCESSING TRANSACTION STATE
     * ========================================================
     */
    stage = "create transaction state";

    const {
      data: transactionStateData,
      error: transactionStateError,
    } = await authRpc.rpc(
      "create_my_gold_sell_state",
      {
        p_transaction: transactionJson,
        p_blockchain_code: blockchainCode,
      },
    );

    if (transactionStateError) {
      logRpcError(
        "GOLD_SELL_STATE_CREATE_FAILED",
        transactionStateError,
      );

      if (
        transactionStateError.code === "23505" ||
        transactionStateError.message?.includes(
          "TRANSACTION_REPLAY",
        )
      ) {
        throw new AppError("TRANSACTION_REPLAY", 409);
      }

      throw new AppError(
        transactionStateError.message ||
          "TRANSACTION_STATE_CREATE_FAILED",
      );
    }

    transactionId = scalarValue(transactionStateData);

    if (!transactionId) {
      throw new AppError("TRANSACTION_STATE_CREATE_FAILED");
    }

    /*
     * ========================================================
     * 5. VERIFY SIGNED TRANSACTION
     * ========================================================
     */
    stage = "verify transaction signature";

    TransactionVerificationService
      .validateTransactionFields(transaction);

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
     * ========================================================
     * 6. PREPARE GOLD SELL
     * ========================================================
     */
    stage = "prepare gold sell";

    const serviceSupabase =
      createSupabaseServiceClient();

    const serviceRpc = asRpcClient(serviceSupabase);

    const preparation = await rpcRow<GoldSellPreparation>(
      serviceRpc,
      "prepare_gold_sell",
      {
        p_seller_id: context.seller_id,
        p_transaction: transactionJson,
        p_country_code: context.country_code,
        p_transaction_state_id: transactionId,
        p_blockchain_code: blockchainCode,
      },
      "GOLD_SELL_PREPARATION_FAILED",
    );

    if (preparation.seller_id !== context.seller_id) {
      throw new AppError("GOLD_SELL_USER_MISMATCH");
    }

    if (preparation.country_code !== context.country_code) {
      throw new AppError("GOLD_SELL_COUNTRY_MISMATCH");
    }

    if (
      normalizeBlockchainCode(preparation.blockchain_code) !==
        blockchainCode
    ) {
      throw new AppError("BLOCKCHAIN_CODE_MISMATCH");
    }

    if (
      normalizeAddress(preparation.seller_wallet_address) !==
        normalizeAddress(context.wallet_address)
    ) {
      throw new AppError("GOLD_SELL_WALLET_MISMATCH");
    }

    if (
      !preparation.treasury_id ||
      !preparation.treasury_wallet_address
    ) {
      throw new AppError(
        "TREASURY_WALLET_NOT_CONFIGURED",
      );
    }

    const sellerWalletIndex = Number(
      preparation.seller_wallet_index,
    );

    if (
      !Number.isSafeInteger(sellerWalletIndex) ||
      sellerWalletIndex < 0
    ) {
      throw new AppError("INVALID_SELLER_WALLET_INDEX");
    }

    const tokenQuantity = positiveNumericString(
      preparation.token_quantity,
      "INVALID_TOKEN_QUANTITY",
    );

    positiveNumericString(
      preparation.gross_amount,
      "INVALID_GROSS_AMOUNT",
    );

    positiveNumericString(
      preparation.net_amount,
      "INVALID_NET_AMOUNT",
    );

    nonNegativeNumericString(
      preparation.fiat_fee,
      "INVALID_FIAT_FEE",
    );

    nonNegativeNumericString(
      preparation.token_fee_equivalent,
      "INVALID_TOKEN_FEE_EQUIVALENT",
    );

    /*
     * ========================================================
     * 7. CREATE BLOCKCHAIN CLIENT
     * ========================================================
     */
    stage = "create blockchain client";

/*
 * ========================================================
 * 7. CREATE BLOCKCHAIN CLIENT
 * ========================================================
 */
stage = "create blockchain client";

const blockchainConfig: BlockchainClientConfig = {
  code: blockchain.code,
  chain_id: Number(blockchain.chain_id),
  rpc_url: blockchain.rpc_url,
  contract_address: blockchain.contract_address,
  native_currency_code: blockchain.native_currency_code,
  treasury_wallet_address:
    preparation.treasury_wallet_address,
};

const blockchainClient =
  createBlockchainClient(blockchainConfig);

if (
  normalizeAddress(blockchainClient.treasuryAddress) !==
  normalizeAddress(preparation.treasury_wallet_address)
) {
  throw new AppError(
    "TREASURY_BLOCKCHAIN_ADDRESS_MISMATCH",
  );
}

    /*
     * ========================================================
     * 8. SIGN BLOCKCHAIN TRANSFER
     * ========================================================
     *
     * Seller -> Treasury: tokenQuantity
     *
     * Blockchain fee = zero.
     *
     * The fiat fee equivalent remains part of the pricing
     * calculation and is not transferred again as Gold.
     */
    stage = "sign blockchain transfer";

    const signedTransfer = await signTransfer({
      fromIndex: sellerWalletIndex,
      expectedOwner: preparation.seller_wallet_address,
      to: preparation.treasury_wallet_address,
      amount: tokenQuantity,
      fee: "0",
      client: blockchainClient,
      blockchain: blockchainConfig,
    });

    /*
     * ========================================================
     * 9. RELAY BLOCKCHAIN TRANSFER
     * ========================================================
     *
     * Once submission begins, a failure or timeout may
     * represent an unknown on-chain outcome.
     *
     * Do not mark the transaction failed automatically.
     */
    stage = "relay blockchain transfer";

    submissionAttempted = true;

    const blockchainResult =
      await relayTransferWithPermit(
        signedTransfer,
        blockchainClient,
      );

    blockchainTransactionHash = blockchainResult.txHash;

    if (!blockchainTransactionHash) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_HASH_MISSING",
      );
    }

    requiresReconciliation = true;

    const explorerUrl = buildExplorerUrl(
      blockchain.explorer_url,
      blockchainTransactionHash,
    );

    /*
     * ========================================================
     * 10. RECORD BLOCKCHAIN TRANSACTION
     * ========================================================
     */
    stage = "record blockchain transaction";

    const {
      data: blockchainRecordData,
      error: blockchainRecordError,
    } = await serviceRpc.rpc(
      "record_gold_sell_blockchain_transaction",
      {
        p_seller_id: context.seller_id,
        p_transaction: transactionJson,
        p_country_code: context.country_code,
        p_transaction_state_id: transactionId,
        p_tx_hash: blockchainTransactionHash,
        p_explorer_url: explorerUrl,
        p_blockchain_code: blockchainCode,
      },
    );

    if (blockchainRecordError) {
      logRpcError(
        "GOLD_SELL_BLOCKCHAIN_RECORD_FAILED",
        blockchainRecordError,
        {
          transactionId,
          blockchainCode,
          blockchainTransactionHash,
          explorerUrl,
        },
      );

      throw new AppError(
        blockchainRecordError.message ||
          "GOLD_SELL_BLOCKCHAIN_RECORD_FAILED",
      );
    }

    blockchainTransactionId =
      scalarValue(blockchainRecordData);

    if (!blockchainTransactionId) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_RECORD_NOT_FOUND",
      );
    }

    /*
     * ========================================================
     * 11. COMPLETE ACCOUNTING
     * ========================================================
     *
     * This RPC atomically:
     * - Posts USD GL entries
     * - Moves USD treasury -> seller
     * - Posts Gold GL entries
     * - Moves Gold seller -> treasury on selected blockchain
     * - Completes blockchain transaction
     * - Marks transaction state successful
     */
    stage = "complete gold sell accounting";

    const {
      data: completionData,
      error: completionError,
    } = await serviceRpc.rpc(
      "complete_gold_sell",
      {
        p_seller_id: context.seller_id,
        p_transaction: transactionJson,
        p_country_code: context.country_code,
        p_transaction_state_id: transactionId,
        p_blockchain_transaction_id:
          blockchainTransactionId,
        p_blockchain_code: blockchainCode,
        p_ip_address: clientIpAddress(request),
      },
    );

    if (completionError) {
      logRpcError(
        "GOLD_SELL_POSTING_FAILED",
        completionError,
        {
          transactionId,
          blockchainCode,
          blockchainTransactionId,
          blockchainTransactionHash,
        },
      );

      throw new AppError(
        completionError.message ||
          "GOLD_SELL_POSTING_FAILED",
      );
    }

    postingCommitted = true;
    requiresReconciliation = false;

    const completion =
      firstRow<GoldSellCompletion>(completionData);

    if (!completion) {
      console.error("GOLD_SELL_COMPLETION_RESPONSE_MISSING", {
        transactionId,
        blockchainCode,
        blockchainTransactionId,
        blockchainTransactionHash,
      });

      return successResponse({ success: true });
    }

    /*
     * ========================================================
     * 12. FINANCIAL INTELLIGENCE
     * ========================================================
     *
     * Best effort after accounting has committed.
     */
    stage = "record financial activity";

    try {
      const outcome = await recordFinancialActivity(
        serviceSupabase,
        {
          reference: completion.document_number,
          userId: context.seller_id,
          countryCode: context.country_code,
          currencyCode: "usd",

          transactionType:
            TransactionType.gold_token_sell,

          activityType:
            FinancialActivityType.investment_sell,

          amount: completion.gross_amount,
          amountUsd: completion.gross_amount,

          cashAmount: completion.net_amount,
          cashAmountUsd: completion.net_amount,

          goldQuantity: completion.quantity,
          investmentCostUsd: "0.000000",
        },
      );

      if (outcome.status === "failed") {
        console.error(
          "GOLD_SELL_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,
            blockchainCode,
            documentNumber: completion.document_number,
            error: outcome.error,
          },
        );
      }
    } catch (error) {
      console.error(
        "GOLD_SELL_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,
          blockchainCode,
          error: error instanceof Error
            ? error.message
            : String(error),
        },
      );
    }

    /*
     * ========================================================
     * 13. PUSH NOTIFICATION
     * ========================================================
     *
     * Best effort after accounting has committed.
     */
    stage = "send push notification";

    const deviceTokens = (
      completion.device_tokens ?? []
    ).filter(
      (token): token is string =>
        typeof token === "string" &&
        token.trim().length > 0,
    );

    if (
      deviceTokens.length > 0 &&
      completion.push_title &&
      completion.push_body
    ) {
      try {
        await sendPushNotification({
          tokens: deviceTokens,
          title: completion.push_title,
          body: completion.push_body,
          data: {
            notification_id:
              completion.receiver_notification_id ?? "",

            reference:
              completion.push_reference ?? transaction.r,

            transaction_type:
              TransactionType.gold_token_sell,

            document_number:
              completion.document_number,

            token_document_number:
              completion.token_document_number,

            blockchain_code: blockchainCode,
          },
        });
      } catch (error) {
        console.error(
          "GOLD_SELL_PUSH_NOTIFICATION_FAILED",
          {
            transactionId,
            blockchainCode,
            error: error instanceof Error
              ? error.message
              : String(error),
          },
        );
      }
    }

    return successResponse({
      success: true,
    });
  } catch (error) {
    /*
     * ========================================================
     * ERROR HANDLING AND RECONCILIATION
     * ========================================================
     *
     * Before blockchain submission:
     *   Mark transaction failed.
     *
     * After blockchain submission:
     *   Preserve processing state.
     *   The blockchain outcome may require reconciliation.
     *
     * After accounting commit:
     *   Never mark the transaction failed.
     */
    if (submissionAttempted && !postingCommitted) {
      requiresReconciliation = true;
    }

    if (
      authRpc &&
      transactionId &&
      !postingCommitted &&
      !requiresReconciliation
    ) {
      failureStateUpdated = await updateFailedState(
        authRpc,
        transactionId,
        error instanceof Error
          ? error.message
          : "GOLD_SELL_FAILED",
      );
    }

    console.error("GOLD_SELL_ERROR", {
      stage,
      transactionId,
      transactionReference,
      blockchainCode,
      blockchainTransactionId,
      blockchainTransactionHash,
      submissionAttempted,
      postingCommitted,
      requiresReconciliation,
      failureStateUpdated,
      error: error instanceof Error
        ? error.message
        : String(error),
    });

    return errorResponse(
      error,
      "GOLD_SELL_FAILED",
    );
  }
});