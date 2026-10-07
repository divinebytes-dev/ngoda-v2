// supabase/functions/voucher-payment/index.ts

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
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

import type {
  TransactionData,
} from "../../_shared/transaction-verification-service.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import type {
  Json,
} from "../../_shared/database.types.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";

import {
  awardCompletedTransactionLoyalty,
} from "../../_shared/gamification/award-completed-transaction-loyalty.ts";

import type {
  LoyaltyAwardResult,
} from "../../_shared/types/loyalty-award.ts";


type VoucherPaymentContext = {
  merchant_id: string;
  country_code: string;
  merchant_wallet_address: string;
  voucher_owner_wallet_address: string;
  version_time: number | string;
};


type VoucherPaymentResult = {
  success: boolean;
  reference: string;
  customer_id: string;
  gross_amount: string;
  fee: string;
  currency: string;
  voucher_remaining_balance: string;
  notification_id: string | null;
  device_tokens: string[] | null;
  push_title: string | null;
  push_body: string | null;
  push_reference: string | null;

  /*
   * USD equivalent of the committed voucher payment amount.
   *
   * Returned by complete_my_voucher_payment().
   */
  gross_amount_usd: string;
};


type TransactionLoyaltyResult = {
  points_earned: number;
  base_points_earned: number;
  bonus_points_earned: number;
  points_spent: number;
  available_points: number;
  tier_points: number;
  previous_level_code: string | null;
  level_code: string | null;
  level_changed: boolean;
};


type RpcError = {
  code?: string;
  message: string;
  details?: string | null;
  hint?: string | null;
};


type RpcResult = {
  data: unknown;
  error: RpcError | null;
};


type UntypedRpcClient = {
  rpc(
    functionName: string,
    parameters?: Record<string, unknown>,
  ): Promise<RpcResult>;
};


function transactionToJson(
  value: TransactionData,
): Json {
  return value as unknown as Json;
}


function errorMessage(
  error: unknown,
  fallback: string,
): string {
  if (
    error instanceof Error &&
    error.message
  ) {
    return error.message;
  }

  if (typeof error === "string") {
    return error;
  }

  return fallback;
}


function requestIpAddress(
  request: Request,
): string {
  const forwardedFor =
    request.headers.get(
      "x-forwarded-for",
    );

  const forwardedAddress =
    forwardedFor
      ?.split(",")[0]
      ?.trim();

  if (forwardedAddress) {
    return forwardedAddress;
  }

  return (
    request.headers
      .get("x-real-ip")
      ?.trim() ??
    "unknown"
  );
}


function buildLoyaltyResult(
  award: LoyaltyAwardResult | null,
): TransactionLoyaltyResult | null {
  if (!award) {
    return null;
  }

  return {
    points_earned:
      award.points_awarded ?? 0,

    base_points_earned:
      award.points_awarded ?? 0,

    bonus_points_earned:
      0,

    points_spent:
      0,

    available_points:
      award.available_points ?? 0,

    tier_points:
      award.tier_points ?? 0,

    previous_level_code:
      award.previous_level_code ?? null,

    level_code:
      award.level_code ?? null,

    level_changed:
      award.level_changed ?? false,
  };
}


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  let postingCommitted =
    false;

  let failureStateUpdated =
    false;

  let authSupabase:
    ReturnType<
      typeof createSupabaseClient
    > | null = null;


  async function markTransactionFailed(
    message: string,
  ): Promise<boolean> {
    if (
      !authSupabase ||
      !transactionId ||
      postingCommitted
    ) {
      return false;
    }

    try {
      const rpcClient =
        authSupabase as unknown as
          UntypedRpcClient;

      const {
        error,
      } = await rpcClient.rpc(
        "update_my_transaction_state",
        {
          p_transaction_id:
            transactionId,

          p_status:
            TransactionStatus.failed,

          p_message:
            message,
        },
      );

      if (error) {
        console.error(
          "VOUCHER_PAYMENT_STATE_UPDATE_FAILED",
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
    } catch (updateError) {
      console.error(
        "VOUCHER_PAYMENT_STATE_UPDATE_FAILED",
        {
          transactionId,

          error:
            errorMessage(
              updateError,
              "TRANSACTION_STATE_UPDATE_FAILED",
            ),
        },
      );

      return false;
    }
  }


  try {
    if (
      request.method !== "POST"
    ) {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }


    authSupabase =
      createSupabaseClient(
        request,
      );


    const rpcClient =
      authSupabase as unknown as
        UntypedRpcClient;


    let body: {
      voucher?: TransactionData;
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


    if (!body.voucher) {
      throw new AppError(
        "VOUCHER_DATA_MISSING",
      );
    }


    if (!body.transaction) {
      throw new AppError(
        "TRANSACTION_DATA_MISSING",
      );
    }


    const voucher =
      body.voucher;


    const transaction =
      body.transaction;


    /*
     * Preserve the original versions.
     */
    if (
      transaction.v !== "v0"
    ) {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }


    if (
      voucher.v !== "v0"
    ) {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }


    if (
      !voucher.s ||
      !voucher.s.trim()
    ) {
      throw new AppError(
        "VOUCHER_OWNER_ID_MISSING",
      );
    }


    /*
     * ========================================================
     * CONTEXT
     * ========================================================
     *
     * The authenticated user is the merchant/vendor.
     *
     * voucher.s is the voucher owner.
     */
    const {
      data:
        contextData,

      error:
        contextError,
    } = await rpcClient.rpc(
      "fetch_my_voucher_payment_context",
      {
        p_v:
          transaction.v,

        p_voucher_owner_id:
          voucher.s,
      },
    );


    if (contextError) {
      console.error(
        "VOUCHER_PAYMENT_CONTEXT_FAILED",
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
          "VOUCHER_PAYMENT_CONTEXT_FAILED",
      );
    }


    const contextRows =
      contextData as
        VoucherPaymentContext[] | null;


    const context =
      contextRows?.[0];


    if (!context) {
      throw new AppError(
        "VOUCHER_PAYMENT_CONTEXT_NOT_FOUND",
      );
    }


    if (!context.merchant_id) {
      throw new AppError(
        "MERCHANT_NOT_FOUND",
      );
    }


    if (
      !context
        .merchant_wallet_address
    ) {
      throw new AppError(
        "MERCHANT_WALLET_NOT_CONFIGURED",
      );
    }


    if (
      !context
        .voucher_owner_wallet_address
    ) {
      throw new AppError(
        "VOUCHER_OWNER_WALLET_NOT_CONFIGURED",
      );
    }


    const transactionJson =
      transactionToJson(
        transaction,
      );


    const voucherJson =
      transactionToJson(
        voucher,
      );


    /*
     * ========================================================
     * CREATE TRANSACTION STATE
     * ========================================================
     */
    const {
      data:
        stateData,

      error:
        stateError,
    } = await rpcClient.rpc(
      "create_my_voucher_payment_state",
      {
        p_transaction:
          transactionJson,

        p_voucher:
          voucherJson,
      },
    );


    if (stateError) {
      console.error(
        "VOUCHER_PAYMENT_STATE_CREATE_FAILED",
        {
          code:
            stateError.code,

          message:
            stateError.message,

          details:
            stateError.details,

          hint:
            stateError.hint,
        },
      );


      if (
        stateError.code === "23505" ||
        stateError.message ===
          "TRANSACTION_REPLAY"
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


    if (!stateData) {
      throw new AppError(
        "TRANSACTION_STATE_CREATE_FAILED",
      );
    }


    transactionId =
      String(
        stateData,
      );


    /*
     * ========================================================
     * TRANSACTION VALIDATION
     * ========================================================
     */
    TransactionVerificationService
      .validateTransactionFields(
        transaction,
      );


    TransactionVerificationService
      .validateTransactionTimestamp(
        transaction,
        Number(
          context.version_time,
        ),
      );


    /*
     * ========================================================
     * VOUCHER OWNER SIGNATURE
     * ========================================================
     */
    const voucherVerified =
      TransactionVerificationService
        .verifyTransactionSignature(
          voucher,
          context
            .voucher_owner_wallet_address,
        );


    if (!voucherVerified) {
      throw new AppError(
        "VOUCHER_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /*
     * ========================================================
     * MERCHANT SIGNATURE
     * ========================================================
     */
    const merchantVerified =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context
            .merchant_wallet_address,
        );


    if (!merchantVerified) {
      throw new AppError(
        "MERCHANT_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    if (
      transaction.c !==
      voucher.c
    ) {
      throw new AppError(
        "CURRENCY_MISMATCH",
      );
    }


    /*
     * transaction.s contains the voucher reference.
     */
    if (
      transaction.s !==
      voucher.r
    ) {
      throw new AppError(
        "REFERENCE_MISMATCH",
      );
    }


    const ipAddress =
      requestIpAddress(
        request,
      );


    /*
     * ========================================================
     * COMPLETE VOUCHER PAYMENT
     * ========================================================
     */
    const {
      data:
        resultData,

      error:
        postingError,
    } = await rpcClient.rpc(
      "complete_my_voucher_payment",
      {
        p_transaction:
          transactionJson,

        p_voucher:
          voucherJson,

        p_transaction_state_id:
          transactionId,

        p_ip_address:
          ipAddress,
      },
    );


    if (postingError) {
      console.error(
        "VOUCHER_PAYMENT_POSTING_FAILED",
        {
          code:
            postingError.code,

          message:
            postingError.message,

          details:
            postingError.details,

          hint:
            postingError.hint,

          transactionId,

          merchantId:
            context.merchant_id,

          voucherReference:
            voucher.r,
        },
      );


      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "VOUCHER_PAYMENT_FAILED",
        );


      throw new AppError(
        postingError.message ||
          "VOUCHER_PAYMENT_FAILED",
      );
    }


    /*
     * The database transaction has committed successfully.
     *
     * Nothing after this point may mark the transaction failed.
     */
    postingCommitted =
      true;


    const resultRows =
      resultData as
        VoucherPaymentResult[] | null;


    const result =
      resultRows?.[0];


    /*
     * The posting RPC succeeded, therefore the financial
     * transaction may already be committed even if the returned
     * payload is unexpectedly missing.
     */
    if (!result?.success) {
      console.error(
        "VOUCHER_PAYMENT_COMPLETION_RESULT_MISSING",
        {
          transactionId,

          merchantId:
            context.merchant_id,

          voucherReference:
            voucher.r,
        },
      );


      return successResponse({
        success:
          true,
      });
    }


    /*
     * ========================================================
     * POST-COMMIT SERVICE CLIENT
     * ========================================================
     */
    const serviceSupabase =
      createSupabaseServiceClient();


    /*
     * ========================================================
     * FINANCIAL INTELLIGENCE
     * ========================================================
     *
     * The voucher OWNER is the spender.
     *
     * Example:
     *
     * voucher payment       ZAR 100
     *
     * FI spending           ZAR 100
     *
     * There is no customer cash-wallet debit. The voucher
     * balance is reduced instead, therefore cashAmount remains
     * zero.
     */
    try {
      const financialActivity =
        await recordFinancialActivity(
          serviceSupabase,
          {
            reference:
              result.reference,

            userId:
              result.customer_id,

            countryCode:
              context.country_code,

            currencyCode:
              result.currency,

            /*
             * Voucher payment is economically a merchant
             * payment made by the voucher owner.
             */
            transactionType:
              TransactionType
                .merchant_payment,

            activityType:
              FinancialActivityType
                .spending,

            /*
             * Purchase amount in transaction currency.
             */
            amount:
              result.gross_amount,

            /*
             * Authoritative USD equivalent returned by
             * PostgreSQL.
             */
            amountUsd:
              result.gross_amount_usd,

            /*
             * Voucher redemption does not debit the customer's
             * normal cash wallet.
             */
            cashAmount:
              "0.000000",

            cashAmountUsd:
              "0.000000",

            goldQuantity:
              "0.000000",

            investmentCostUsd:
              "0.000000",

            principalAmount:
              "0.000000",

            principalAmountUsd:
              "0.000000",

            interestAmount:
              "0.000000",

            interestAmountUsd:
              "0.000000",
          },
        );


      if (
        financialActivity.status ===
        "failed"
      ) {
        console.error(
          "VOUCHER_PAYMENT_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            reference:
              result.reference,

            voucherOwnerId:
              result.customer_id,

            currency:
              result.currency,

            grossAmount:
              result.gross_amount,

            grossAmountUsd:
              result.gross_amount_usd,

            error:
              financialActivity.error,
          },
        );
      }
    } catch (financialError) {
      /*
       * FI is post-commit secondary processing.
       *
       * It must never convert a successful voucher payment into
       * a failed payment.
       */
      console.error(
        "VOUCHER_PAYMENT_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          reference:
            result.reference,

          voucherOwnerId:
            result.customer_id,

          error:
            errorMessage(
              financialError,
              "FINANCIAL_INTELLIGENCE_FAILED",
            ),
        },
      );
    }


    /*
     * ========================================================
     * LOYALTY
     * ========================================================
     *
     * Voucher payment uses the same merchant-payment loyalty
     * rules as an ordinary merchant payment.
     *
     * The reward belongs to the voucher OWNER, not the
     * authenticated merchant.
     */
    let baseAward:
      LoyaltyAwardResult | null =
        null;


    try {
      const loyaltyOutcome =
        await awardCompletedTransactionLoyalty(
          serviceSupabase,
          {
            transactionType:
              TransactionType
                .merchant_payment,

            /*
             * Voucher owner receives the points.
             */
            userId:
              result.customer_id,

            reference:
              result.reference,

            amount:
              result.gross_amount,

            amountUsd:
              result.gross_amount_usd,

            countryCode:
              context.country_code,

            currencyCode:
              result.currency,

            metadata: {
              merchant_id:
                context.merchant_id,

              payment_type:
                "voucher",

              voucher_reference:
                voucher.r,

              transaction_reference:
                transaction.r,

              voucher_remaining_balance:
                result
                  .voucher_remaining_balance,

              fee:
                result.fee,
            },
          },
        );


      if (
        loyaltyOutcome.status ===
        "completed"
      ) {
        baseAward =
          loyaltyOutcome.result;
      } else {
        console.error(
          "VOUCHER_PAYMENT_LOYALTY_NOT_COMPLETED",
          {
            transactionId,

            reference:
              result.reference,

            voucherOwnerId:
              result.customer_id,

            status:
              loyaltyOutcome.status,
          },
        );
      }
    } catch (loyaltyError) {
      /*
       * Loyalty is post-commit secondary processing.
       */
      console.error(
        "VOUCHER_PAYMENT_LOYALTY_FAILED",
        {
          transactionId,

          reference:
            result.reference,

          voucherOwnerId:
            result.customer_id,

          error:
            errorMessage(
              loyaltyError,
              "LOYALTY_FAILED",
            ),
        },
      );
    }


    const loyalty =
      buildLoyaltyResult(
        baseAward,
      );


    /*
     * ========================================================
     * PUSH NOTIFICATION
     * ========================================================
     *
     * Push runs after the database transaction commits.
     * Failure cannot reverse the voucher payment.
     */
    const deviceTokens = [
      ...new Set(
        (
          result.device_tokens ??
          []
        )
          .map(
            (token) =>
              token.trim(),
          )
          .filter(
            (token) =>
              token.length > 0,
          ),
      ),
    ];


    if (
      deviceTokens.length > 0 &&
      result.push_title &&
      result.push_body
    ) {
      try {
        await sendPushNotification({
          tokens:
            deviceTokens,

          title:
            result.push_title,

          body:
            result.push_body,

          data: {
            notification_id:
              result.notification_id ??
              "",

            reference:
              result.push_reference ??
              result.reference,

            transaction_type:
              TransactionType
                .merchant_payment,

            payment_type:
              "voucher",
          },
        });
      } catch (pushError) {
        console.error(
          "VOUCHER_PAYMENT_PUSH_FAILED",
          {
            transactionId,

            notificationId:
              result.notification_id,

            error:
              errorMessage(
                pushError,
                "PUSH_NOTIFICATION_FAILED",
              ),
          },
        );
      }
    }


    /*
     * ========================================================
     * RESPONSE
     * ========================================================
     */
    return successResponse({
      reference:
        result.reference,

      customer_id:
        result.customer_id,

      gross_amount:
        result.gross_amount,

      fee:
        result.fee,

      currency:
        result.currency,

      voucher_remaining_balance:
        result
          .voucher_remaining_balance,

      loyalty,
    });
  } catch (error) {
    const failureMessage =
      errorMessage(
        error,
        "VOUCHER_PAYMENT_FAILED",
      );


    /*
     * Only a pre-commit failure may update the transaction
     * state to failed.
     */
    if (
      transactionId &&
      !postingCommitted &&
      !failureStateUpdated
    ) {
      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }


    console.error(
      "VOUCHER_PAYMENT_ERROR",
      {
        transactionId,

        postingCommitted,

        error:
          failureMessage,
      },
    );


    return errorResponse(
      error,
      "VOUCHER_PAYMENT_FAILED",
    );
  }
});

