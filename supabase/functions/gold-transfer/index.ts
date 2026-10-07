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
  blockchainConfig,
} from "../../_shared/blockchain/client.ts";

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


function validatePositiveAmount(
  value: NumericValue,
  errorMessage: string,
): string {
  const amount =
    String(value);

  const parsed =
    Number(amount);

  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return amount;
}


function validateNonNegativeAmount(
  value: NumericValue,
  errorMessage: string,
): string {
  const amount =
    String(value);

  const parsed =
    Number(amount);

  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return amount;
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
        "Gold-transfer state update failed",
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
        transaction?:
          TransactionData;
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

      /*
       * Keep the transaction typed for canonical validation.
       */
      const transaction =
        body.transaction;

      /*
       * Gold Transfer has its own version.
       * Do not change this to the Gold Buy version.
       */
      if (
        transaction.v !== "v6"
      ) {
        throw new AppError(
          "OPERATION_NOT_ALLOWED",
        );
      }

      const transactionJson =
        transaction as unknown as Json;

      /*
       * Fetch authenticated sender context.
       */
      const {
        data: contextData,
        error: contextError,
      } = await authRpc.rpc(
        "fetch_my_gold_transfer_context",
        {
          p_v:
            transaction.v,
        },
      );

      if (contextError) {
        console.error(
          "Gold-transfer context failed",
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
            "GOLD_TRANSFER_CONTEXT_FAILED",
        );
      }

      const context =
        firstRow<GoldTransferContext>(
          contextData,
        );

      if (!context) {
        throw new AppError(
          "GOLD_TRANSFER_CONTEXT_NOT_FOUND",
        );
      }

      if (!context.sender_id) {
        throw new AppError(
          "SENDER_NOT_FOUND",
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
       * Create processing transaction state.
       */
      const {
        data:
          transactionStateData,

        error:
          transactionStateError,
      } = await authRpc.rpc(
        "create_my_gold_transfer_state",
        {
          p_transaction:
            transactionJson,
        },
      );

      if (
        transactionStateError
      ) {
        console.error(
          "Gold-transfer state creation failed",
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
       * Validate signed transaction.
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
       * Service client for trusted preparation/posting.
       */
      const serviceSupabase =
        createSupabaseServiceClient();

      const serviceRpc =
        asRpcClient(
          serviceSupabase,
        );

      /*
       * Recalculate receiver, amount, fee and total amount
       * in PostgreSQL.
       */
      const {
        data:
          preparationData,

        error:
          preparationError,
      } = await serviceRpc.rpc(
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
        },
      );

      if (preparationError) {
        console.error(
          "Gold-transfer preparation failed",
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

            senderId:
              context.sender_id,
          },
        );

        throw new AppError(
          preparationError.message ||
            "GOLD_TRANSFER_PREPARATION_FAILED",
        );
      }

      const preparation =
        firstRow<GoldTransferPreparation>(
          preparationData,
        );

      if (!preparation) {
        throw new AppError(
          "GOLD_TRANSFER_PREPARATION_NOT_FOUND",
        );
      }

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
        !preparation
          .receiver_id ||
        !preparation
          .receiver_wallet_address
      ) {
        throw new AppError(
          "RECEIVER_WALLET_NOT_CONFIGURED",
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

      /*
       * Blockchain fee treasury must be the same treasury
       * used by accounting.
       */
      if (
        normalizeAddress(
          preparation
            .treasury_wallet_address,
        ) !==
        normalizeAddress(
          blockchainConfig
            .treasuryAddress,
        )
      ) {
        throw new AppError(
          "TREASURY_BLOCKCHAIN_ADDRESS_MISMATCH",
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
       * These values came from PostgreSQL and are also the
       * authoritative values used for the blockchain transfer.
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
       * Sign transfer.
       *
       * On-chain:
       *
       * sender -> receiver = amount
       * sender -> treasury = fee
       *
       * Therefore sender's total gold position reduction is
       * totalAmount.
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
        });

      /*
       * Execute blockchain transfer.
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
       * Record blockchain transaction.
       */
      const {
        data:
          blockchainRecordData,

        error:
          blockchainRecordError,
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
            blockchainTransactionHash,

          p_explorer_url:
            explorerUrl,
        },
      );

      if (
        blockchainRecordError
      ) {
        console.error(
          "GOLD_TRANSFER_BLOCKCHAIN_RECORD_FAILED",
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
            "GOLD_TRANSFER_BLOCKCHAIN_RECORD_FAILED",
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
          "Gold-transfer blockchain record ID missing",
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
       * Complete GL entries, wallet entries, notifications,
       * blockchain status and transaction state atomically.
       */
      const {
        data:
          completionData,

        error:
          completionError,
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
            ipAddress,
        },
      );

      if (completionError) {
        console.error(
          "GOLD_TRANSFER_POSTING_FAILED",
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

            senderId:
              context.sender_id,
          },
        );

        /*
         * Attempt failed state immediately.
         */
        failureStateUpdated =
          await updateFailedState(
            authRpc,
            transactionId,
            completionError.message ||
              "GOLD_TRANSFER_POSTING_FAILED",
          );

        throw new AppError(
          completionError.message ||
            "GOLD_TRANSFER_POSTING_FAILED",
        );
      }

      /*
       * complete_gold_transfer has committed successfully.
       *
       * Nothing below this point may mark the financial
       * transaction as failed.
       */
      postingCommitted =
        true;

      const completion =
        firstRow<GoldTransferCompletion>(
          completionData,
        );

      /*
       * A missing response row must not change an already
       * committed transaction back to failed.
       */
      if (!completion) {
        console.error(
          "Gold-transfer completion response missing",
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
       * FINANCIAL INTELLIGENCE — SENDER
       * ==========================================================
       *
       * A gold transfer is not an investment purchase or sale.
       *
       * It simply moves an existing gold position.
       *
       * The sender loses:
       *
       *     transfer amount + transfer fee
       *
       * The SQL preparation result already gives this exact
       * amount as total_amount.
       *
       * No cash/savings movement is recorded.
       */
      try {
        const senderFinancialActivity =
          await recordFinancialActivity(
            serviceSupabase,
            {
              reference:
                completion.document_number,

              userId:
                context.sender_id,

              countryCode:
                context.country_code,

              currencyCode:
                "gold",

              transactionType:
                TransactionType
                  .gold_token_transfer,

              activityType:
                FinancialActivityType
                  .investment_transfer_out,

              /*
               * amount represents the actual gold position
               * leaving the sender.
               */
              amount:
                totalAmount,

              /*
               * Gold transfers do not generate investment
               * behaviour based on USD value.
               */
              amountUsd:
                "0.000000",

              /*
               * No fiat savings movement.
               */
              cashAmount:
                "0.000000",

              cashAmountUsd:
                "0.000000",

              /*
               * Sender's exact gold-position reduction:
               *
               * transfer amount + gold transfer fee.
               */
              goldQuantity:
                totalAmount,

              investmentCostUsd:
                "0.000000",
            },
          );

        if (
          senderFinancialActivity.status ===
          "failed"
        ) {
          console.error(
            "GOLD_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_FAILED",
            {
              transactionId,

              reference:
                completion.document_number,

              senderId:
                context.sender_id,

              transferAmount:
                completion.amount,

              transferFee:
                completion.fee,

              totalGoldOut:
                totalAmount,

              error:
                senderFinancialActivity.error,
            },
          );
        }
      } catch (financialActivityError) {
        console.error(
          "GOLD_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            transactionId,

            reference:
              completion.document_number,

            senderId:
              context.sender_id,

            totalGoldOut:
              totalAmount,

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
       * FINANCIAL INTELLIGENCE — RECEIVER
       * ==========================================================
       *
       * The receiver receives only the transferred quantity.
       *
       * The sender's transfer fee goes to treasury and must
       * never increase the receiver's gold position.
       *
       * This is transfer-in activity, not an investment buy,
       * so it does not create investor behaviour.
       */
      try {
        const receiverFinancialActivity =
          await recordFinancialActivity(
            serviceSupabase,
            {
              reference:
                completion.document_number,

              userId:
                preparation.receiver_id,

              countryCode:
                context.country_code,

              currencyCode:
                "gold",

              transactionType:
                TransactionType
                  .gold_token_transfer,

              activityType:
                FinancialActivityType
                  .investment_transfer_in,

              /*
               * Receiver gets the transfer amount only.
               */
              amount:
                completion.amount,

              amountUsd:
                "0.000000",

              /*
               * No fiat savings movement.
               */
              cashAmount:
                "0.000000",

              cashAmountUsd:
                "0.000000",

              /*
               * Exact gold quantity received.
               */
              goldQuantity:
                completion.amount,

              investmentCostUsd:
                "0.000000",
            },
          );

        if (
          receiverFinancialActivity.status ===
          "failed"
        ) {
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

              error:
                receiverFinancialActivity.error,
            },
          );
        }
      } catch (financialActivityError) {
        console.error(
          "GOLD_TRANSFER_RECEIVER_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            transactionId,

            reference:
              completion.document_number,

            receiverId:
              preparation.receiver_id,

            goldQuantity:
              completion.amount,

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
       * Push occurs after the committed financial transaction.
       * Failure here must not fail or reverse the transfer.
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
                  .gold_token_transfer,

              document_number:
                completion
                  .document_number,
            },
          });
        } catch (pushError) {
          console.error(
            "GOLD_TRANSFER_PUSH_NOTIFICATION_FAILED",
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
       * Flutter only checks whether the invocation throws.
       */
      return successResponse({
        success: true,
      });
    } catch (error) {
      /*
       * Never change an already committed successful
       * transaction back to failed.
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
            : "GOLD_TRANSFER_FAILED";

        failureStateUpdated =
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
        "GOLD_TRANSFER_FAILED",
      );
    }
  },
);

