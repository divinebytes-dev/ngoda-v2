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
  awardCompletedTransactionLoyalty,
} from "../../_shared/gamification/award-completed-transaction-loyalty.ts";

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


type GoldBuyContext = {
  user_id: string;
  country_code: string;
  wallet_address: string;
  version_time: number | string;
};


type GoldBuyPreparation = {
  user_id: string;
  country_code: string;
  user_wallet_address: string;
  treasury_id: string;
  treasury_wallet_address: string;
  treasury_wallet_index: number | string;
  fiscal_year: number;
  period: number;
  document_prefix: string;
  input_amount: string;
  input_currency: string;
  token_quantity: string;
  gross_token_quantity: string;
  token_fee: string;
  gross_amount: string;
  spread: string;
};


type GoldBuyCompletion = {
  success: boolean;
  document_number: string;
  quantity: string;

  /*
   * complete_gold_buy returns the committed USD gross
   * amount here.
   *
   * This is:
   *
   * - the actual USD savings outflow;
   * - the committed investment purchase amount;
   * - the qualifying loyalty amount.
   *
   * It must not be reconstructed from TransactionData.
   */
  total_spent: string;

  explorer_url: string;

  receiver_notification_id:
    string | null;

  device_tokens:
    string[] | null;

  push_title:
    string | null;

  push_body:
    string | null;

  push_reference:
    string | null;
};


type TransactionLoyaltyResult = {
  points_earned: number;
  points_spent: number;
  available_points: number;
  tier_points: number;
  previous_level_code: string | null;
  level_code: string | null;
  level_changed: boolean;
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
      first !== null &&
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
  return `${requiredEnvironment(
    "CHIADO_EXPLORER",
  )}${transactionHash}`;
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

  return request.headers
    .get("x-real-ip")
    ?.trim() ?? "unknown";
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
        "Gold-buy transaction-state update failed",
        {
          transactionId,

          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );

      return false;
    }

    return true;
  } catch (error) {
    console.error(
      "Gold-buy transaction-state update failed",
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
    let transactionId:
      string | null = null;

    let blockchainTransactionId:
      string | null = null;

    let blockchainTransactionHash:
      string | null = null;

    let authRpc:
      RpcClient | null = null;

    let failureStateUpdated =
      false;

    /*
     * complete_gold_buy is the financial commit point.
     *
     * Once this becomes true, failures from Financial
     * Intelligence, loyalty or push notification must
     * never mark the financial transaction as failed.
     */
    let postingCommitted =
      false;


    try {
      if (request.method !== "POST") {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
        );
      }


      /*
       * ==========================================================
       * AUTHENTICATED CLIENT
       * ==========================================================
       */
      const authSupabase =
        createSupabaseClient(request);

      authRpc =
        asRpcClient(authSupabase);


      /*
       * ==========================================================
       * REQUEST BODY
       * ==========================================================
       */
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


      if (!body.transaction) {
        throw new AppError(
          "TRANSACTION_DATA_IS_MISSING",
        );
      }


      const transaction =
        body.transaction;


      if (transaction.v !== "v7") {
        throw new AppError(
          "OPERATION_NOT_ALLOWED",
        );
      }


      const transactionJson =
        transaction as unknown as Json;


      /*
       * ==========================================================
       * FETCH GOLD BUY CONTEXT
       * ==========================================================
       */
      const {
        data: contextData,
        error: contextError,
      } = await authRpc.rpc(
        "fetch_my_gold_buy_context",
        {
          p_v:
            transaction.v,
        },
      );


      if (contextError) {
        console.error(
          "Gold-buy context RPC failed",
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
            "GOLD_BUY_CONTEXT_FAILED",
        );
      }


      const context =
        firstRow<GoldBuyContext>(
          contextData,
        );


      if (!context) {
        throw new AppError(
          "GOLD_BUY_CONTEXT_NOT_FOUND",
        );
      }


      if (!context.user_id) {
        throw new AppError(
          "AUTHENTICATED_USER_NOT_FOUND",
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
        Number(
          context.version_time,
        );


      if (!Number.isFinite(versionTime)) {
        throw new AppError(
          "INVALID_TRANSACTION_VERSION_TIME",
        );
      }


      /*
       * ==========================================================
       * CREATE PROCESSING TRANSACTION STATE
       * ==========================================================
       */
      const {
        data: transactionStateData,
        error: transactionStateError,
      } = await authRpc.rpc(
        "create_my_gold_buy_state",
        {
          p_transaction:
            transactionJson,
        },
      );


      if (transactionStateError) {
        console.error(
          "Gold-buy transaction-state creation failed",
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
          transactionStateError.code ===
            "23505" ||
          transactionStateError.message
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
          transactionStateError.message ||
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
       * ==========================================================
       * VERIFY SIGNED TRANSACTION
       * ==========================================================
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
       * ==========================================================
       * SERVICE CLIENT
       * ==========================================================
       */
      const serviceSupabase =
        createSupabaseServiceClient();


      const serviceRpc =
        asRpcClient(
          serviceSupabase,
        );


      /*
       * ==========================================================
       * PREPARE GOLD BUY
       * ==========================================================
       */
      const {
        data: preparationData,
        error: preparationError,
      } = await serviceRpc.rpc(
        "prepare_gold_buy",
        {
          p_user_id:
            context.user_id,

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
          "Gold-buy preparation failed",
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

            userId:
              context.user_id,
          },
        );


        throw new AppError(
          preparationError.message ||
            "GOLD_BUY_PREPARATION_FAILED",
        );
      }


      const preparation =
        firstRow<GoldBuyPreparation>(
          preparationData,
        );


      if (!preparation) {
        throw new AppError(
          "GOLD_BUY_PREPARATION_NOT_FOUND",
        );
      }


      if (
        preparation.user_id !==
        context.user_id
      ) {
        throw new AppError(
          "GOLD_BUY_USER_MISMATCH",
        );
      }


      if (
        preparation.country_code !==
        context.country_code
      ) {
        throw new AppError(
          "GOLD_BUY_COUNTRY_MISMATCH",
        );
      }


      if (
        preparation
          .user_wallet_address
          .toLowerCase() !==
        context
          .wallet_address
          .toLowerCase()
      ) {
        throw new AppError(
          "GOLD_BUY_WALLET_MISMATCH",
        );
      }


      if (
        !preparation
          .treasury_wallet_address
      ) {
        throw new AppError(
          "TREASURY_WALLET_NOT_CONFIGURED",
        );
      }


      const treasuryWalletIndex =
        Number(
          preparation
            .treasury_wallet_index,
        );


      if (
        !Number.isSafeInteger(
          treasuryWalletIndex,
        ) ||
        treasuryWalletIndex < 0
      ) {
        throw new AppError(
          "INVALID_TREASURY_WALLET_INDEX",
        );
      }


      if (
        !preparation.token_quantity ||
        Number(
          preparation.token_quantity,
        ) <= 0
      ) {
        throw new AppError(
          "INVALID_TOKEN_QUANTITY",
        );
      }


      /*
       * ==========================================================
       * SIGN BLOCKCHAIN TRANSFER
       * ==========================================================
       */
      const signedTransfer =
        await signTransfer({
          fromIndex:
            treasuryWalletIndex,

          expectedOwner:
            preparation
              .treasury_wallet_address,

          to:
            preparation
              .user_wallet_address,

          amount:
            preparation
              .token_quantity,

          fee:
            "0",
        });


      /*
       * ==========================================================
       * EXECUTE BLOCKCHAIN TRANSFER
       * ==========================================================
       */
      const blockchainResult =
        await relayTransferWithPermit(
          signedTransfer,
        );


      blockchainTransactionHash =
        blockchainResult.txHash;


      if (!blockchainTransactionHash) {
        throw new AppError(
          "BLOCKCHAIN_TRANSACTION_HASH_MISSING",
        );
      }


      const explorerUrl =
        buildExplorerUrl(
          blockchainTransactionHash,
        );


      /*
       * ==========================================================
       * RECORD BLOCKCHAIN TRANSACTION
       * ==========================================================
       */
      const {
        data: blockchainRecordData,
        error: blockchainRecordError,
      } = await serviceRpc.rpc(
        "record_gold_buy_blockchain_transaction",
        {
          p_user_id:
            context.user_id,

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


      if (blockchainRecordError) {
        console.error(
          "GOLD_BUY_BLOCKCHAIN_RECORD_FAILED",
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
          blockchainRecordError.message ||
            "GOLD_BUY_BLOCKCHAIN_RECORD_FAILED",
        );
      }


      blockchainTransactionId =
        scalarValue(
          blockchainRecordData,
        );


      if (!blockchainTransactionId) {
        throw new AppError(
          "BLOCKCHAIN_TRANSACTION_RECORD_NOT_FOUND",
        );
      }


      /*
       * ==========================================================
       * COMPLETE GOLD BUY
       * ==========================================================
       *
       * This is the financial posting commit point.
       */
      const {
        data: completionData,
        error: completionError,
      } = await serviceRpc.rpc(
        "complete_gold_buy",
        {
          p_user_id:
            context.user_id,

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
        },
      );


      if (completionError) {
        console.error(
          "GOLD_BUY_POSTING_FAILED",
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

            userId:
              context.user_id,
          },
        );


        failureStateUpdated =
          await updateFailedState(
            authRpc,
            transactionId,
            completionError.message ||
              "GOLD_BUY_POSTING_FAILED",
          );


        throw new AppError(
          completionError.message ||
            "GOLD_BUY_POSTING_FAILED",
        );
      }


      /*
       * complete_gold_buy has committed successfully.
       *
       * Nothing below this point may mark this transaction
       * state as failed.
       */
      postingCommitted =
        true;


      const completion =
        firstRow<GoldBuyCompletion>(
          completionData,
        );


      if (!completion?.success) {
        console.error(
          "Gold-buy completion response missing",
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
       * FINANCIAL INTELLIGENCE — GOLD INVESTMENT BUY
       * ==========================================================
       *
       * Gold buy is always financially settled in USD.
       *
       * The buyer receives one investment_buy activity:
       *
       * investment purchase:
       *
       *     amount =
       *         committed USD amount spent
       *
       * savings outflow:
       *
       *     cashAmount =
       *         committed USD wallet outflow
       *
       * gold position increase:
       *
       *     goldQuantity =
       *         committed token quantity
       *
       * investment acquisition cost:
       *
       *     investmentCostUsd =
       *         committed USD amount spent
       *
       * We deliberately use complete_gold_buy values and
       * do not reconstruct either amount or quantity from
       * the signed request.
       */
      try {
        const financialActivityOutcome =
          await recordFinancialActivity(
            serviceSupabase,
            {
              reference:
                completion.document_number,

              userId:
                context.user_id,

              countryCode:
                context.country_code,

              /*
               * Gold purchase cash settlement is always
               * denominated in USD.
               */
              currencyCode:
                "usd",

              transactionType:
                TransactionType.gold_token_buy,

              activityType:
                FinancialActivityType.investment_buy,

              /*
               * Investment purchase amount.
               */
              amount:
                completion.total_spent,

              amountUsd:
                completion.total_spent,

              /*
               * Savings movement.
               *
               * The committed USD amount spent leaves the
               * customer's cash position.
               */
              cashAmount:
                completion.total_spent,

              cashAmountUsd:
                completion.total_spent,

              /*
               * Gold investment position increase.
               */
              goldQuantity:
                completion.quantity,

              /*
               * USD acquisition cost of this gold purchase.
               */
              investmentCostUsd:
                completion.total_spent,
            },
          );


        if (
          financialActivityOutcome.status ===
          "failed"
        ) {
          console.error(
            "GOLD_BUY_FINANCIAL_INTELLIGENCE_FAILED",
            {
              transactionId,

              reference:
                completion.document_number,

              userId:
                context.user_id,

              amountUsd:
                completion.total_spent,

              goldQuantity:
                completion.quantity,

              error:
                financialActivityOutcome.error,
            },
          );
        }
      } catch (financialActivityError) {
        /*
         * Financial Intelligence is post-commit.
         *
         * Failure here must never affect the already
         * completed gold purchase.
         */
        console.error(
          "GOLD_BUY_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            transactionId,

            reference:
              completion.document_number,

            userId:
              context.user_id,

            amountUsd:
              completion.total_spent,

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
       * LOYALTY
       * ==========================================================
       */
      let loyalty:
        TransactionLoyaltyResult | null =
          null;


      /*
       * The financial and blockchain transactions have
       * committed.
       *
       * total_spent is returned by complete_gold_buy from
       * the committed USD posting.
       *
       * It is intentionally used instead of transaction.a,
       * token quantity, transaction fee, or spread.
       */
      const loyaltyOutcome =
        await awardCompletedTransactionLoyalty(
          serviceSupabase,
          {
            transactionType:
              TransactionType.gold_token_buy,

            userId:
              context.user_id,

            reference:
              completion.document_number,

            amount:
              completion.total_spent,

            amountUsd:
              completion.total_spent,

            countryCode:
              context.country_code,

            currencyCode:
              "usd",

            metadata: {
              transaction_reference:
                transaction.r,

              transaction_state_id:
                transactionId,

              blockchain_transaction_id:
                blockchainTransactionId,

              blockchain_transaction_hash:
                blockchainTransactionHash,

              token_quantity:
                completion.quantity,

              amount_basis:
                "committed_gold_buy_usd_amount",
            },
          },
        );


      if (
        loyaltyOutcome.status ===
        "completed"
      ) {
        const award =
          loyaltyOutcome.result;


        loyalty = {
          points_earned:
            award.points_awarded,

          points_spent:
            0,

          available_points:
            award.available_points ?? 0,

          tier_points:
            award.tier_points ?? 0,

          previous_level_code:
            award.previous_level_code ??
            null,

          level_code:
            award.level_code ?? null,

          level_changed:
            award.level_changed ?? false,
        };
      }


      /*
       * ==========================================================
       * PUSH NOTIFICATION
       * ==========================================================
       */
      const deviceTokens = [
        ...new Set(
          (
            completion.device_tokens ??
            []
          ).filter(
            (
              token,
            ): token is string =>
              typeof token === "string" &&
              token.trim().length > 0,
          ),
        ),
      ];


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
              completion.push_title,

            body:
              completion.push_body,

            data: {
              notification_id:
                completion
                  .receiver_notification_id ??
                "",

              reference:
                completion.push_reference ??
                transaction.r,

              transaction_type:
                TransactionType
                  .gold_token_buy,

              document_number:
                completion.document_number,
            },
          });
        } catch (pushError) {
          console.error(
            "GOLD_BUY_PUSH_NOTIFICATION_FAILED",
            {
              transactionId,

              blockchainTransactionId,

              notificationId:
                completion
                  .receiver_notification_id,

              error:
                pushError instanceof Error
                  ? pushError.message
                  : String(pushError),
            },
          );
        }
      }


      /*
       * ==========================================================
       * RESPONSE
       * ==========================================================
       */
      return successResponse({
        success:
          true,

        amount:
          completion.total_spent,

        quantity:
          completion.quantity,

        currency:
          "usd",

        document_number:
          completion.document_number,

        explorer_url:
          completion.explorer_url,

        loyalty,
      });
    } catch (error) {
      /*
       * Only mark failed before complete_gold_buy has
       * successfully committed.
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
            : "GOLD_PURCHASE_FAILED";


        failureStateUpdated =
          await updateFailedState(
            authRpc,
            transactionId,
            failureMessage,
          );
      }


      console.error(
        "GOLD_BUY_ERROR",
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
        "GOLD_PURCHASE_FAILED",
      );
    }
  },
);


