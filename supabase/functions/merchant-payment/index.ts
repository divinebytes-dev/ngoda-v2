// supabase/functions/merchant-payment/index.ts

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
  SenderApproval,
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
  awardCompletedTransactionLoyalty,
} from "../../_shared/gamification/award-completed-transaction-loyalty.ts";

import {
  awardLoyaltyPoints,
} from "../../_shared/gamification/award-loyalty-points.ts";

import type {
  LoyaltyAwardResult,
} from "../../_shared/types/loyalty-award.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";


type NumericValue =
  | string
  | number;


type MerchantPaymentContext = {
  payer_id: string;
  merchant_id: string;
  country_code: string;
  payer_wallet_address: string;
  merchant_wallet_address: string;
  version_time: NumericValue;
};


type MerchantPaymentPreparation = {
  payer_id: string;
  payer_wallet_address: string;
  merchant_id: string;
  merchant_wallet_address: string;
  treasury_id: string;
  country_code: string;
  fiscal_year: number;
  period: number;
  document_prefix: string;
  currency_code: string;
  amount: NumericValue;
  payer_debit_amount: NumericValue;
  merchant_credit_amount: NumericValue;
  other_amount: NumericValue;
  payment_fee: NumericValue;
  commission_rate: NumericValue;
  commission_amount: NumericValue;
};


type MerchantPaymentCompletion = {
  success: boolean;
  document_number: string;
  financial_transaction_id: string;
  amount: string;
  amount_usd: string;
  payment_fee: string;
  payment_fee_usd: string;
  payment_fee_contribution: boolean;
  payer_debit_amount: string;
  currency_code: string;
  receiver_notification_id: string | null;
  device_tokens: string[] | null;
  push_title: string | null;
  push_body: string | null;
  push_reference: string | null;
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


function parsePaymentFeeContribution(
  value: unknown,
): boolean {
  /*
   * This is deliberately opt-in. Older Flutter clients that omit the field
   * do not pay the optional contribution.
   */
  if (
    value === undefined ||
    value === null
  ) {
    return false;
  }

  if (typeof value !== "boolean") {
    throw new AppError(
      "INVALID_PAYMENT_FEE_CONTRIBUTION",
      400,
    );
  }

  return value;
}


function normalizeAddress(
  address: string,
): string {
  return address
    .trim()
    .toLowerCase();
}


function positiveNumber(
  value: NumericValue,
  errorMessage: string,
): number {
  const parsed = Number(value);

  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return parsed;
}


function nonNegativeNumber(
  value: NumericValue,
  errorMessage: string,
): number {
  const parsed = Number(value);

  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return parsed;
}


function clientIpAddress(
  request: Request,
): string {
  return request.headers
    .get("x-forwarded-for")
    ?.split(",")[0]
    ?.trim() ??
    request.headers
      .get("x-real-ip")
      ?.trim() ??
    "unknown";
}


function buildLoyaltyResult(
  baseAward: LoyaltyAwardResult | null,
  bonusAward: LoyaltyAwardResult | null,
): TransactionLoyaltyResult | null {
  if (!baseAward && !bonusAward) {
    return null;
  }

  const finalAward =
    bonusAward ?? baseAward!;

  const levelChanged =
    (baseAward?.level_changed ?? false) ||
    (bonusAward?.level_changed ?? false);

  const levelChangeAward =
    (baseAward?.level_changed ?? false)
      ? baseAward
      : (bonusAward?.level_changed ?? false)
      ? bonusAward
      : null;

  const basePoints =
    baseAward?.points_awarded ?? 0;

  const bonusPoints =
    bonusAward?.points_awarded ?? 0;

  return {
    points_earned:
      basePoints + bonusPoints,

    base_points_earned:
      basePoints,

    bonus_points_earned:
      bonusPoints,

    points_spent:
      0,

    available_points:
      finalAward.available_points ?? 0,

    tier_points:
      finalAward.tier_points ?? 0,

    previous_level_code:
      levelChangeAward
        ?.previous_level_code ??
      baseAward
        ?.previous_level_code ??
      null,

    level_code:
      finalAward.level_code ?? null,

    level_changed:
      levelChanged,
  };
}


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  let failureStateUpdated = false;
  let postingCommitted = false;

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
      const {
        error,
      } = await authSupabase.rpc(
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
          "MERCHANT_PAYMENT_STATE_UPDATE_FAILED",
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
        "MERCHANT_PAYMENT_STATE_UPDATE_FAILED",
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


  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    authSupabase =
      createSupabaseClient(request);

    let body: {
      transaction?: TransactionData;
      approval?: SenderApproval;
      payment_fee_contribution?: unknown;
    };

    try {
      body = await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const transaction =
      body.transaction;

    const approval =
      body.approval;

    if (!transaction) {
      throw new AppError(
        "TRANSACTION_DATA_MISSING",
        400,
      );
    }

    if (!approval) {
      throw new AppError(
        "SENDER_APPROVAL_MISSING",
        400,
      );
    }

    if (transaction.v !== "v4") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
        400,
      );
    }

    const paymentFeeContribution =
      parsePaymentFeeContribution(
        body.payment_fee_contribution,
      );

    const transactionJson =
      transaction as unknown as Json;

    const approvalJson =
      approval as unknown as Json;

    const {
      data: contextData,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_merchant_payment_context",
      {
        p_v:
          transaction.v,

        p_merchant_id:
          transaction.s,
      },
    );

    if (contextError) {
      console.error(
        "MERCHANT_PAYMENT_CONTEXT_FAILED",
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
          "MERCHANT_PAYMENT_CONTEXT_FAILED",
      );
    }

    const context =
      firstRow<MerchantPaymentContext>(
        contextData,
      );

    if (!context) {
      throw new AppError(
        "MERCHANT_PAYMENT_CONTEXT_NOT_FOUND",
      );
    }

    if (!context.payer_id) {
      throw new AppError(
        "PAYER_NOT_FOUND",
      );
    }

    if (!context.merchant_id) {
      throw new AppError(
        "MERCHANT_NOT_FOUND",
      );
    }

    if (
      context.merchant_id !==
      transaction.s
    ) {
      throw new AppError(
        "MERCHANT_ID_MISMATCH",
      );
    }

    if (!context.country_code) {
      throw new AppError(
        "USER_COUNTRY_NOT_CONFIGURED",
      );
    }

    if (!context.payer_wallet_address) {
      throw new AppError(
        "PAYER_WALLET_NOT_CONFIGURED",
      );
    }

    if (!context.merchant_wallet_address) {
      throw new AppError(
        "MERCHANT_WALLET_NOT_CONFIGURED",
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

    const {
      data: stateData,
      error: stateError,
    } = await authSupabase.rpc(
      "create_my_merchant_payment_state",
      {
        p_transaction:
          transactionJson,

        p_approval:
          approvalJson,

        p_payment_fee_contribution:
          paymentFeeContribution,
      },
    );

    if (stateError) {
      console.error(
        "MERCHANT_PAYMENT_STATE_CREATE_FAILED",
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
        stateError.message
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

    const merchantSignatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.merchant_wallet_address,
        );

    if (!merchantSignatureValid) {
      throw new AppError(
        "MERCHANT_SIGNATURE_VERIFICATION_FAILED",
      );
    }

    const payerSignatureValid =
      TransactionVerificationService
        .verifySenderSignature(
          approval,
          context.payer_wallet_address,
        );

    if (!payerSignatureValid) {
      throw new AppError(
        "USER_SIGNATURE_VERIFICATION_FAILED",
      );
    }

    TransactionVerificationService
      .validateTransactionFields(
        transaction,
      );

    TransactionVerificationService
      .validateTransactionTimestamp(
        transaction,
        versionTime,
      );

    if (transaction.a !== approval.a) {
      throw new AppError(
        "AMOUNT_MISMATCH",
      );
    }

    if (transaction.c !== approval.c) {
      throw new AppError(
        "CURRENCY_MISMATCH",
      );
    }

    if (transaction.r !== approval.r) {
      throw new AppError(
        "REFERENCE_MISMATCH",
      );
    }

    const serviceSupabase =
      createSupabaseServiceClient();

    const {
      data: preparationData,
      error: preparationError,
    } = await serviceSupabase.rpc(
      "prepare_merchant_payment",
      {
        p_payer_id:
          context.payer_id,

        p_transaction:
          transactionJson,

        p_approval:
          approvalJson,

        p_country_code:
          context.country_code,

        p_transaction_state_id:
          transactionId,

        p_payment_fee_contribution:
          paymentFeeContribution,
      },
    );

    if (preparationError) {
      console.error(
        "MERCHANT_PAYMENT_PREPARATION_FAILED",
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

          payerId:
            context.payer_id,

          merchantId:
            context.merchant_id,
        },
      );

      throw new AppError(
        preparationError.message ||
          "MERCHANT_PAYMENT_PREPARATION_FAILED",
      );
    }

    const preparation =
      firstRow<MerchantPaymentPreparation>(
        preparationData,
      );

    if (!preparation) {
      throw new AppError(
        "MERCHANT_PAYMENT_PREPARATION_NOT_FOUND",
      );
    }

    if (
      preparation.payer_id !==
      context.payer_id
    ) {
      throw new AppError(
        "MERCHANT_PAYMENT_PAYER_MISMATCH",
      );
    }

    if (
      preparation.merchant_id !==
      context.merchant_id
    ) {
      throw new AppError(
        "MERCHANT_PAYMENT_MERCHANT_MISMATCH",
      );
    }

    if (
      normalizeAddress(
        preparation.payer_wallet_address,
      ) !==
      normalizeAddress(
        context.payer_wallet_address,
      )
    ) {
      throw new AppError(
        "PAYER_WALLET_MISMATCH",
      );
    }

    if (
      normalizeAddress(
        preparation.merchant_wallet_address,
      ) !==
      normalizeAddress(
        context.merchant_wallet_address,
      )
    ) {
      throw new AppError(
        "MERCHANT_WALLET_MISMATCH",
      );
    }

    positiveNumber(
      preparation.amount,
      "INVALID_AMOUNT",
    );

    positiveNumber(
      preparation.payer_debit_amount,
      "INVALID_PAYER_DEBIT_AMOUNT",
    );

    positiveNumber(
      preparation.merchant_credit_amount,
      "INVALID_MERCHANT_CREDIT_AMOUNT",
    );

    nonNegativeNumber(
      preparation.payment_fee,
      "INVALID_PAYMENT_FEE",
    );

    if (
      !paymentFeeContribution &&
      Number(preparation.payment_fee) !== 0
    ) {
      throw new AppError(
        "OPTIONAL_PAYMENT_FEE_NOT_REMOVED",
      );
    }

    const {
      data: completionData,
      error: completionError,
    } = await serviceSupabase.rpc(
      "complete_merchant_payment",
      {
        p_payer_id:
          context.payer_id,

        p_transaction:
          transactionJson,

        p_approval:
          approvalJson,

        p_country_code:
          context.country_code,

        p_transaction_state_id:
          transactionId,

        p_payment_fee_contribution:
          paymentFeeContribution,

        p_ip_address:
          clientIpAddress(request),
      },
    );

    if (completionError) {
      console.error(
        "MERCHANT_PAYMENT_POSTING_FAILED",
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

          payerId:
            context.payer_id,

          merchantId:
            context.merchant_id,
        },
      );

      failureStateUpdated =
        await markTransactionFailed(
          completionError.message ||
            "MERCHANT_PAYMENT_POSTING_FAILED",
        );

      throw new AppError(
        completionError.message ||
          "MERCHANT_PAYMENT_POSTING_FAILED",
      );
    }

    /*
     * Financial posting has committed.
     *
     * Nothing after this point is allowed to mark the payment
     * transaction as failed.
     */
    postingCommitted = true;

    const completion =
      firstRow<MerchantPaymentCompletion>(
        completionData,
      );

    if (!completion?.success) {
      console.error(
        "MERCHANT_PAYMENT_COMPLETION_RESULT_MISSING",
        {
          transactionId,

          payerId:
            context.payer_id,

          merchantId:
            context.merchant_id,
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
     * Merchant payment is a spending activity for the payer.
     *
     * Spending:
     *
     *     amount
     *         = merchant payment principal
     *
     *     amountUsd
     *         = committed USD equivalent already returned for
     *           loyalty calculations
     *
     *
     * Savings outflow:
     *
     *     cashAmount
     *         = exact payer wallet debit
     *
     *     cashAmountUsd
     *         = principal USD
     *           + optional contribution fee USD
     *
     *
     * Example:
     *
     * Merchant amount        ZAR 100
     * Optional contribution  ZAR   2
     * Payer wallet debit     ZAR 102
     *
     * FI:
     *
     * spending               ZAR 100
     * savings outflow        ZAR 102
     */
    try {
      const amountUsd =
        Number(
          completion.amount_usd,
        );

      const paymentFeeUsd =
        Number(
          completion.payment_fee_usd,
        );

      if (
        !Number.isFinite(amountUsd) ||
        amountUsd < 0
      ) {
        throw new Error(
          "INVALID_MERCHANT_PAYMENT_AMOUNT_USD",
        );
      }

      if (
        !Number.isFinite(paymentFeeUsd) ||
        paymentFeeUsd < 0
      ) {
        throw new Error(
          "INVALID_MERCHANT_PAYMENT_FEE_USD",
        );
      }

      /*
       * The optional payment fee is the only additional payer
       * debit above the merchant payment amount.
       *
       * When the customer does not contribute the fee, the FI
       * savings outflow USD is simply amount_usd.
       */
      const payerDebitAmountUsd =
        completion.payment_fee_contribution
          ? (
              amountUsd +
              paymentFeeUsd
            ).toFixed(6)
          : amountUsd.toFixed(6);

      const financialActivity =
        await recordFinancialActivity(
          serviceSupabase,
          {
            reference:
              transaction.r,

            userId:
              context.payer_id,

            countryCode:
              context.country_code,

            currencyCode:
              completion.currency_code,

            transactionType:
              TransactionType
                .merchant_payment,

            activityType:
              FinancialActivityType
                .spending,

            /*
             * Spending principal in the transaction currency.
             */
            amount:
              completion.amount,

            /*
             * USD equivalent already calculated by PostgreSQL
             * for loyalty.
             */
            amountUsd:
              completion.amount_usd,

            /*
             * Exact amount removed from the payer's wallet.
             */
            cashAmount:
              completion.payer_debit_amount,

            /*
             * USD equivalent of the actual payer savings
             * outflow.
             */
            cashAmountUsd:
              payerDebitAmountUsd,

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
          "MERCHANT_PAYMENT_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            documentNumber:
              completion.document_number,

            payerId:
              context.payer_id,

            currencyCode:
              completion.currency_code,

            amount:
              completion.amount,

            amountUsd:
              completion.amount_usd,

            payerDebitAmount:
              completion.payer_debit_amount,

            payerDebitAmountUsd,

            error:
              financialActivity.error,
          },
        );
      }
    } catch (financialError) {
      /*
       * Merchant payment is already committed.
       *
       * FI failure must never change the completed financial
       * transaction.
       */
      console.error(
        "MERCHANT_PAYMENT_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          documentNumber:
            completion.document_number,

          payerId:
            context.payer_id,

          error:
            financialError instanceof Error
              ? financialError.message
              : String(financialError),
        },
      );
    }


    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     *
     * Financial posting has committed. Loyalty failures are
     * logged and must never change a successful payment to
     * failed.
     */
    let baseAward:
      LoyaltyAwardResult | null = null;

    let bonusAward:
      LoyaltyAwardResult | null = null;

    const baseOutcome =
      await awardCompletedTransactionLoyalty(
        serviceSupabase,
        {
          transactionType:
            TransactionType.merchant_payment,

          userId:
            context.payer_id,

          reference:
            completion.document_number,

          sourceTransactionId:
            completion.financial_transaction_id,

          amount:
            completion.amount,

          amountUsd:
            completion.amount_usd,

          countryCode:
            context.country_code,

          currencyCode:
            completion.currency_code,

          metadata: {
            merchant_id:
              context.merchant_id,

            transaction_reference:
              transaction.r,

            payment_fee_contribution:
              completion
                .payment_fee_contribution,

            payment_fee:
              completion.payment_fee,
          },
        },
      );

    if (
      baseOutcome.status ===
      "completed"
    ) {
      baseAward =
        baseOutcome.result;
    }

    if (
      completion.payment_fee_contribution &&
      Number(completion.payment_fee) > 0
    ) {
      try {
        bonusAward =
          await awardLoyaltyPoints(
            serviceSupabase,
            {
              idempotencyKey:
                `loyalty:merchant_payment_fee_contribution:${completion.document_number}`,

              eventType:
                "merchant_payment_fee_contribution",

              userId:
                context.payer_id,

              sourceReference:
                completion.document_number,

              sourceTransactionId:
                completion
                  .financial_transaction_id,

              transactionType:
                TransactionType.merchant_payment,

              amount:
                completion.payment_fee,

              amountUsd:
                completion.payment_fee_usd,

              countryCode:
                context.country_code,

              currencyCode:
                completion.currency_code,

              metadata: {
                merchant_id:
                  context.merchant_id,

                transaction_reference:
                  transaction.r,

                payment_fee_contribution:
                  true,
              },
            },
          );

        if (
          bonusAward.event_status !==
          "completed"
        ) {
          bonusAward = null;
        }
      } catch (loyaltyError) {
        console.error(
          "MERCHANT_PAYMENT_CONTRIBUTION_BONUS_FAILED",
          {
            transactionId,

            documentNumber:
              completion.document_number,

            payerId:
              context.payer_id,

            error:
              loyaltyError instanceof Error
                ? loyaltyError.message
                : String(loyaltyError),
          },
        );
      }
    }

    const loyalty =
      buildLoyaltyResult(
        baseAward,
        bonusAward,
      );

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
                .merchant_payment,

            document_number:
              completion.document_number,
          },
        });
      } catch (pushError) {
        console.error(
          "MERCHANT_PAYMENT_PUSH_NOTIFICATION_FAILED",
          {
            transactionId,

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

    return successResponse({
      success:
        true,

      document_number:
        completion.document_number,

      amount:
        completion.amount,

      payment_fee:
        completion.payment_fee,

      payment_fee_contribution:
        completion.payment_fee_contribution,

      payer_debit_amount:
        completion.payer_debit_amount,

      currency:
        completion.currency_code,

      loyalty,
    });
  } catch (error) {
    if (
      transactionId &&
      !postingCommitted &&
      !failureStateUpdated
    ) {
      failureStateUpdated =
        await markTransactionFailed(
          error instanceof Error
            ? error.message
            : "MERCHANT_PAYMENT_FAILED",
        );
    }

    console.error(
      "MERCHANT_PAYMENT_ERROR",
      {
        transactionId,

        postingCommitted,

        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "MERCHANT_PAYMENT_FAILED",
    );
  }
});

