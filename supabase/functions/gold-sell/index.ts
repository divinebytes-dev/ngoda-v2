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


type NumericValue =
  | string
  | number;


type GoldSellContext = {
  seller_id: string;
  country_code: string;
  wallet_address: string;
  wallet_index: NumericValue;
  version_time: NumericValue;
};


type GoldSellPreparation = {
  seller_id: string;
  seller_wallet_address: string;
  seller_wallet_index: NumericValue;

  treasury_id: string;
  treasury_wallet_address: string;

  country_code: string;
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

  receiver_notification_id:
    | string
    | null;

  device_tokens:
    | string[]
    | null;

  push_title:
    | string
    | null;

  push_body:
    | string
    | null;

  push_reference:
    | string
    | null;
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
    const first =
      data[0];

    if (
      typeof first === "string" ||
      typeof first === "number"
    ) {
      return String(first);
    }

    if (
      first !== null &&
      typeof first === "object"
    ) {
      const values =
        Object.values(first);

      const value =
        values[0];

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
  return address
    .trim()
    .toLowerCase();
}


function requiredEnvironment(
  name: string,
): string {
  const value =
    Deno.env.get(name)?.trim();

  if (!value) {
    throw new AppError(
      `ENV_${name}_MISSING`,
    );
  }

  return value;
}


function buildExplorerUrl(
  transactionHash: string,
): string {
  const explorerPrefix =
    requiredEnvironment(
      "CHIADO_EXPLORER",
    );

  return (
    `${explorerPrefix}${transactionHash}`
  );
}


function clientIpAddress(
  request: Request,
): string {
  const forwardedFor =
    request.headers.get(
      "x-forwarded-for",
    );

  if (forwardedFor) {
    const firstAddress =
      forwardedFor
        .split(",")[0]
        ?.trim();

    if (firstAddress) {
      return firstAddress;
    }
  }

  return (
    request.headers
      .get("x-real-ip")
      ?.trim() ??
    "unknown"
  );
}


function positiveNumericString(
  value: NumericValue,
  errorMessage: string,
): string {
  const normalized =
    String(value);

  const parsed =
    Number(normalized);

  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return normalized;
}


function nonNegativeNumericString(
  value: NumericValue,
  errorMessage: string,
): string {
  const normalized =
    String(value);

  const parsed =
    Number(normalized);

  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return normalized;
}


async function updateFailedState(
  authRpc: RpcClient,
  transactionId: string,
  failureMessage: string,
): Promise<boolean> {
  try {
    const {
      error,
    } = await authRpc.rpc(
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
      console.error(
        "Gold-sell state update failed",
        {
          transactionId,
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      return false;
    }

    return true;
  } catch (error) {
    console.error(
      "Gold-sell state update failed",
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


Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    let authRpc:
      | RpcClient
      | null = null;

    let transactionId:
      | string
      | null = null;

    let blockchainTransactionId:
      | string
      | null = null;

    let blockchainTransactionHash:
      | string
      | null = null;

    let failureStateUpdated =
      false;

    let postingCommitted =
      false;

    try {
      if (
        request.method !== "POST"
      ) {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
        );
      }

      /*
       * Authenticated client carrying the caller's JWT.
       */
      const authSupabase =
        createSupabaseClient(
          request,
        );

      authRpc =
        asRpcClient(
          authSupabase,
        );

      let body: {
        transaction?: TransactionData;
      };

      try {
        body =
          await request.json();
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      if (
        !body.transaction
      ) {
        throw new AppError(
          "TRANSACTION_DATA_IS_MISSING",
        );
      }

      const transaction =
        body.transaction;

      /*
       * Preserve the existing Gold Sell version.
       */
      if (
        transaction.v !== "v7"
      ) {
        throw new AppError(
          "OPERATION_NOT_ALLOWED",
        );
      }

      const transactionJson =
        transaction as unknown as Json;

      /*
       * Resolve authenticated seller context.
       *
       * The RPC validates the customer, agent or vendor role.
       */
      const {
        data: contextData,
        error: contextError,
      } = await authRpc.rpc(
        "fetch_my_gold_sell_context",
        {
          p_v:
            transaction.v,
        },
      );

      if (contextError) {
        console.error(
          "Gold-sell context failed",
          {
            code:
              contextError.code,

            message:
              contextError.message,

            details:
              contextError.details,

            hint:
              contextError.hint,
          },
        );

        throw new AppError(
          contextError.message ||
            "GOLD_SELL_CONTEXT_FAILED",
        );
      }

      const context =
        firstRow<GoldSellContext>(
          contextData,
        );

      if (!context) {
        throw new AppError(
          "GOLD_SELL_CONTEXT_NOT_FOUND",
        );
      }

      if (!context.seller_id) {
        throw new AppError(
          "SELLER_NOT_FOUND",
        );
      }

      if (
        !context.country_code
      ) {
        throw new AppError(
          "USER_COUNTRY_NOT_CONFIGURED",
        );
      }

      if (
        !context.wallet_address
      ) {
        throw new AppError(
          "USER_WALLET_NOT_CONFIGURED",
        );
      }

      const versionTime =
        Number(
          context.version_time,
        );

      if (
        !Number.isFinite(
          versionTime,
        ) ||
        versionTime <= 0
      ) {
        throw new AppError(
          "INVALID_TRANSACTION_VERSION_TIME",
        );
      }

      /*
       * Create processing state with the authenticated client.
       */
      const {
        data:
          transactionStateData,

        error:
          transactionStateError,
      } = await authRpc.rpc(
        "create_my_gold_sell_state",
        {
          p_transaction:
            transactionJson,
        },
      );

      if (
        transactionStateError
      ) {
        console.error(
          "Gold-sell state creation failed",
          {
            code:
              transactionStateError.code,

            message:
              transactionStateError.message,

            details:
              transactionStateError.details,

            hint:
              transactionStateError.hint,
          },
        );

        if (
          transactionStateError
            .code === "23505" ||
          transactionStateError
            .message
            ?.includes(
              "TRANSACTION_REPLAY",
            )
        ) {
          throw new AppError(
            "TRANSACTION_REPLAY",
            409,
          );
        }

        throw new AppError(
          transactionStateError
            .message ||
            "TRANSACTION_STATE_CREATE_FAILED",
        );
      }

      transactionId =
        scalarValue(
          transactionStateData,
        );

      if (!transactionId) {
        throw new AppError(
          "TRANSACTION_STATE_CREATE_FAILED",
        );
      }

      /*
       * Canonical transaction and signature validation.
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
       * Privileged preparation and posting use the
       * service-role client.
       */
      const serviceSupabase =
        createSupabaseServiceClient();

      const serviceRpc =
        asRpcClient(
          serviceSupabase,
        );

      /*
       * PostgreSQL recalculates the sell quantity, gross
       * value, net value, fee, spread, tax and components.
       *
       * This supports both:
       *
       *   input currency = usd
       *   input currency = gold
       *
       * The Edge Function therefore never calculates
       * conversion or pricing itself.
       */
      const {
        data:
          preparationData,

        error:
          preparationError,
      } = await serviceRpc.rpc(
        "prepare_gold_sell",
        {
          p_seller_id:
            context.seller_id,

          p_transaction:
            transactionJson,

          p_country_code:
            context.country_code,

          p_transaction_state_id:
            transactionId,
        },
      );

      if (preparationError) {
        console.error(
          "Gold-sell preparation failed",
          {
            code:
              preparationError.code,

            message:
              preparationError.message,

            details:
              preparationError.details,

            hint:
              preparationError.hint,

            transactionId,

            sellerId:
              context.seller_id,
          },
        );

        throw new AppError(
          preparationError.message ||
            "GOLD_SELL_PREPARATION_FAILED",
        );
      }

      const preparation =
        firstRow<GoldSellPreparation>(
          preparationData,
        );

      if (!preparation) {
        throw new AppError(
          "GOLD_SELL_PREPARATION_NOT_FOUND",
        );
      }

      if (
        preparation.seller_id !==
        context.seller_id
      ) {
        throw new AppError(
          "GOLD_SELL_USER_MISMATCH",
        );
      }

      if (
        preparation.country_code !==
        context.country_code
      ) {
        throw new AppError(
          "GOLD_SELL_COUNTRY_MISMATCH",
        );
      }

      if (
        normalizeAddress(
          preparation
            .seller_wallet_address,
        ) !==
        normalizeAddress(
          context.wallet_address,
        )
      ) {
        throw new AppError(
          "GOLD_SELL_WALLET_MISMATCH",
        );
      }

      if (
        !preparation
          .treasury_id ||
        !preparation
          .treasury_wallet_address
      ) {
        throw new AppError(
          "TREASURY_WALLET_NOT_CONFIGURED",
        );
      }

      const sellerWalletIndex =
        Number(
          preparation
            .seller_wallet_index,
        );

      if (
        !Number.isSafeInteger(
          sellerWalletIndex,
        ) ||
        sellerWalletIndex < 0
      ) {
        throw new AppError(
          "INVALID_SELLER_WALLET_INDEX",
        );
      }

      const tokenQuantity =
        positiveNumericString(
          preparation
            .token_quantity,

          "INVALID_TOKEN_QUANTITY",
        );

      /*
       * Validate committed-pricing candidates returned by
       * PostgreSQL preparation.
       */
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
        preparation
          .token_fee_equivalent,

        "INVALID_TOKEN_FEE_EQUIVALENT",
      );

      /*
       * Sign a transfer from the seller to treasury.
       *
       * Blockchain fee is zero.
       *
       * The Gold-equivalent fiat fee is informational for
       * pricing/accounting and is not added to the on-chain
       * quantity.
       *
       * Therefore the customer's Gold position decreases by
       * tokenQuantity only.
       */
      const signedTransfer =
        await signTransfer({
          fromIndex:
            sellerWalletIndex,

          expectedOwner:
            preparation
              .seller_wallet_address,

          to:
            preparation
              .treasury_wallet_address,

          amount:
            tokenQuantity,

          fee:
            "0",
        });

      /*
       * Relay and wait for confirmation.
       */
      const blockchainResult =
        await relayTransferWithPermit(
          signedTransfer,
        );

      blockchainTransactionHash =
        blockchainResult.txHash;

      if (
        !blockchainTransactionHash
      ) {
        throw new AppError(
          "BLOCKCHAIN_TRANSACTION_HASH_MISSING",
        );
      }

      const explorerUrl =
        buildExplorerUrl(
          blockchainTransactionHash,
        );

      /*
       * Record the confirmed chain transaction as pending.
       */
      const {
        data:
          blockchainRecordData,

        error:
          blockchainRecordError,
      } = await serviceRpc.rpc(
        "record_gold_sell_blockchain_transaction",
        {
          p_seller_id:
            context.seller_id,

          p_transaction:
            transactionJson,

          p_country_code:
            context.country_code,

          p_transaction_state_id:
            transactionId,

          p_tx_hash:
            blockchainTransactionHash,

          p_explorer_url:
            explorerUrl,
        },
      );

      if (
        blockchainRecordError
      ) {
        console.error(
          "GOLD_SELL_BLOCKCHAIN_RECORD_FAILED",
          {
            code:
              blockchainRecordError.code,

            message:
              blockchainRecordError.message,

            details:
              blockchainRecordError.details,

            hint:
              blockchainRecordError.hint,

            transactionId,

            transactionReference:
              transaction.r,

            blockchainTransactionHash,

            explorerUrl,
          },
        );

        throw new AppError(
          blockchainRecordError
            .message ||
            "GOLD_SELL_BLOCKCHAIN_RECORD_FAILED",
        );
      }

      blockchainTransactionId =
        scalarValue(
          blockchainRecordData,
        );

      if (
        !blockchainTransactionId
      ) {
        console.error(
          "Gold-sell blockchain record ID missing",
          {
            transactionId,

            transactionReference:
              transaction.r,

            blockchainTransactionHash,

            explorerUrl,
          },
        );

        throw new AppError(
          "BLOCKCHAIN_TRANSACTION_RECORD_NOT_FOUND",
        );
      }

      const ipAddress =
        clientIpAddress(
          request,
        );

      /*
       * Complete the fiat and Gold accounting atomically.
       */
      const {
        data:
          completionData,

        error:
          completionError,
      } = await serviceRpc.rpc(
        "complete_gold_sell",
        {
          p_seller_id:
            context.seller_id,

          p_transaction:
            transactionJson,

          p_country_code:
            context.country_code,

          p_transaction_state_id:
            transactionId,

          p_blockchain_transaction_id:
            blockchainTransactionId,

          p_ip_address:
            ipAddress,
        },
      );

      if (completionError) {
        console.error(
          "GOLD_SELL_POSTING_FAILED",
          {
            code:
              completionError.code,

            message:
              completionError.message,

            details:
              completionError.details,

            hint:
              completionError.hint,

            transactionId,

            blockchainTransactionId,

            blockchainTransactionHash,

            sellerId:
              context.seller_id,
          },
        );

        /*
         * Attempt the failed-state update immediately.
         */
        failureStateUpdated =
          await updateFailedState(
            authRpc,
            transactionId,
            completionError.message ||
              "GOLD_SELL_POSTING_FAILED",
          );

        throw new AppError(
          completionError.message ||
            "GOLD_SELL_POSTING_FAILED",
        );
      }

      /*
       * PostgreSQL has now committed the accounting and
       * marked the transaction successful.
       *
       * Nothing below this point may change the successful
       * transaction back to failed.
       */
      postingCommitted =
        true;

      const completion =
        firstRow<GoldSellCompletion>(
          completionData,
        );

      /*
       * Missing response data must not change an already
       * successful transaction back to failed.
       */
      if (!completion) {
        console.error(
          "Gold-sell completion response missing",
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
       * ==========================================================
       * FINANCIAL INTELLIGENCE
       * ==========================================================
       *
       * Gold Sell can originate from either:
       *
       *   - a USD amount entered by the customer; or
       *   - a Gold quantity entered by the customer.
       *
       * Financial Intelligence must not use the original
       * transaction input because its unit therefore varies.
       *
       * complete_gold_sell is the committed source of truth.
       *
       *
       * Investment activity:
       *
       *   amount         = gross USD sale value
       *   amountUsd      = gross USD sale value
       *
       *
       * Savings:
       *
       *   cashAmount     = net USD credited to wallet
       *   cashAmountUsd  = net USD credited to wallet
       *
       *
       * Gold:
       *
       *   goldQuantity   = exact Gold quantity sold
       *
       *
       * No loyalty points are awarded for Gold Sell.
       */
      try {
        const financialActivityOutcome =
          await recordFinancialActivity(
            serviceSupabase,
            {
              reference:
                completion.document_number,

              userId:
                context.seller_id,

              /*
               * Country is used by the Financial Intelligence
               * RPC to determine the applicable fiscal period.
               */
              countryCode:
                context.country_code,

              /*
               * Gold Sell settles to USD regardless of whether
               * the customer originally entered USD or Gold.
               */
              currencyCode:
                "usd",

              transactionType:
                TransactionType
                  .gold_token_sell,

              activityType:
                FinancialActivityType
                  .investment_sell,

              /*
               * Gross investment-sale value.
               *
               * This represents the value of the Gold sale
               * before the customer's sell charges reduce
               * the fiat credited to the wallet.
               */
              amount:
                completion.gross_amount,

              amountUsd:
                completion.gross_amount,

              /*
               * The savings pot increases only by the exact
               * USD amount actually credited to the customer's
               * fiat wallet.
               *
               * Fees/tax/spread must therefore not increase
               * savings.
               */
              cashAmount:
                completion.net_amount,

              cashAmountUsd:
                completion.net_amount,

              /*
               * Exact Gold quantity removed from the customer's
               * Gold position.
               */
              goldQuantity:
                completion.quantity,

              /*
               * A sell does not establish new acquisition cost.
               * Existing cost basis is handled by Financial
               * Intelligence when the Gold position is reduced.
               */
              investmentCostUsd:
                "0.000000",
            },
          );

        if (
          financialActivityOutcome.status ===
          "failed"
        ) {
          console.error(
            "GOLD_SELL_FINANCIAL_INTELLIGENCE_FAILED",
            {
              transactionId,

              reference:
                completion.document_number,

              sellerId:
                context.seller_id,

              grossAmount:
                completion.gross_amount,

              netAmount:
                completion.net_amount,

              goldQuantity:
                completion.quantity,

              error:
                financialActivityOutcome.error,
            },
          );
        }
      } catch (financialActivityError) {
        /*
         * Financial Intelligence runs after the committed
         * transaction.
         *
         * A failure here must never fail the Gold Sell.
         */
        console.error(
          "GOLD_SELL_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            transactionId,

            reference:
              completion.document_number,

            sellerId:
              context.seller_id,

            grossAmount:
              completion.gross_amount,

            netAmount:
              completion.net_amount,

            goldQuantity:
              completion.quantity,

            error:
              financialActivityError instanceof Error
                ? financialActivityError.message
                : String(
                  financialActivityError,
                ),
          },
        );
      }

      /*
       * ==========================================================
       * PUSH NOTIFICATION
       * ==========================================================
       *
       * Push notification delivery is outside the database
       * transaction and cannot fail the completed sale.
       */
      const deviceTokens =
        (
          completion
            .device_tokens ??
          []
        ).filter(
          (
            token,
          ): token is string =>
            typeof token ===
              "string" &&
            token.trim()
              .length > 0,
        );

      if (
        deviceTokens.length > 0 &&
        completion.push_title &&
        completion.push_body
      ) {
        try {
          await sendPushNotification({
            tokens:
              deviceTokens,

            title:
              completion
                .push_title,

            body:
              completion
                .push_body,

            data: {
              notification_id:
                completion
                  .receiver_notification_id ??
                "",

              reference:
                completion
                  .push_reference ??
                transaction.r,

              transaction_type:
                TransactionType
                  .gold_token_sell,

              document_number:
                completion
                  .document_number,

              token_document_number:
                completion
                  .token_document_number,
            },
          });
        } catch (pushError) {
          console.error(
            "GOLD_SELL_PUSH_NOTIFICATION_FAILED",
            {
              transactionId,

              blockchainTransactionId,

              notificationId:
                completion
                  .receiver_notification_id,

              error:
                pushError instanceof Error
                  ? pushError.message
                  : String(
                    pushError,
                  ),
            },
          );
        }
      }

      /*
       * Flutter checks only whether this invocation throws.
       */
      return successResponse({
        success: true,
      });
    } catch (error) {
      /*
       * Fallback failed-state update.
       *
       * Never overwrite a committed success.
       */
      if (
        authRpc &&
        transactionId &&
        !postingCommitted &&
        !failureStateUpdated
      ) {
        const failureMessage =
          error instanceof Error
            ? error.message
            : "GOLD_SELL_FAILED";

        failureStateUpdated =
          await updateFailedState(
            authRpc,
            transactionId,
            failureMessage,
          );
      }

      console.error(
        "GOLD_SELL_ERROR",
        {
          transactionId,

          blockchainTransactionId,

          blockchainTransactionHash,

          postingCommitted,

          error:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );

      return errorResponse(
        error,
        "GOLD_SELL_FAILED",
      );
    }
  },
);

