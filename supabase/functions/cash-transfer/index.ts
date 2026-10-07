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
  AppError,
} from "../../_shared/app-error.ts";

import {
  TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";

import {
  FinancialActivityType,
} from "../../_shared/types/financial-activity-type.ts";

import {
  awardCompletedTransactionLoyalty,
} from "../../_shared/gamification/award-completed-transaction-loyalty.ts";

import type {
  Json,
} from "../../_shared/database.types.ts";


const feePaymentMethods = [
  "cash",
  "points",
] as const;


type FeePaymentMethod =
  typeof feePaymentMethods[number];


type TransactionLoyaltyResult = {
  points_earned: number;
  points_spent: number;
  available_points: number;
  tier_points: number;
  previous_level_code: string | null;
  level_code: string | null;
  level_changed: boolean;
};


type CashTransferContext = {
  sender_id: string;
  country_code: string;
  wallet_address: string;
  version_time: number;
};

type CashTransferResult = {
  success: boolean;
  reference: string;
  financial_transaction_id: string;

  receiver_id: string;

  amount: string;
  amount_usd: string;

  sender_debit: string;
  sender_debit_usd: string;

  original_fee: string;
  cash_fee: string;
  cash_charges: string;
  fee_payment_method: FeePaymentMethod;
  points_redeemed: number;
  redemption_ledger_id: string | null;
  loyalty: TransactionLoyaltyResult | null;
  currency: string;

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

// type CashTransferResult = {
//   success: boolean;
//   reference: string;
//   financial_transaction_id: string;
//   amount: string;
//   amount_usd: string;
//   original_fee: string;
//   cash_fee: string;
//   cash_charges: string;
//   fee_payment_method: FeePaymentMethod;
//   points_redeemed: number;
//   redemption_ledger_id: string | null;
//   loyalty: TransactionLoyaltyResult | null;
//   currency: string;

//   receiver_notification_id:
//     string | null;

//   device_tokens:
//     string[] | null;

//   push_title:
//     string | null;

//   push_body:
//     string | null;

//   push_reference:
//     string | null;
// };


function parseFeePaymentMethod(
  value: unknown,
): FeePaymentMethod {
  if (
    value === undefined ||
    value === null ||
    (
      typeof value === "string" &&
      value.trim() === ""
    )
  ) {
    throw new AppError(
      "FEE_PAYMENT_METHOD_REQUIRED",
      400,
    );
  }

  if (typeof value !== "string") {
    throw new AppError(
      "INVALID_FEE_PAYMENT_METHOD",
      400,
    );
  }

  const normalized =
    value.trim().toLowerCase();

  if (
    !feePaymentMethods.includes(
      normalized as FeePaymentMethod,
    )
  ) {
    throw new AppError(
      "INVALID_FEE_PAYMENT_METHOD",
      400,
    );
  }

  return normalized as FeePaymentMethod;
}


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  /*
   * Prevent the outer catch from unnecessarily
   * trying to update a state we already marked
   * failed in the posting-error branch.
   */
  let failureStateUpdated = false;

  /*
   * Once accounting commits successfully,
   * no later error may mark the transaction failed.
   */
  let transactionCompleted = false;

  let authSupabase:
    ReturnType<
      typeof createSupabaseClient
    > | null = null;


  async function markTransactionFailed(
    message: string,
  ): Promise<boolean> {
    const client =
      authSupabase;

    const currentTransactionId =
      transactionId;

    if (
      !client ||
      !currentTransactionId ||
      transactionCompleted
    ) {
      return false;
    }

    try {
      const {
        error,
      } = await client.rpc(
        "update_my_transaction_state",
        {
          p_transaction_id:
            currentTransactionId,

          p_status:
            TransactionStatus.failed,

          p_message:
            message,
        },
      );

      if (error) {
        console.error(
          "CASH_TRANSFER_STATE_UPDATE_FAILED",
          {
            transactionId:
              currentTransactionId,

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
        "CASH_TRANSFER_STATE_UPDATE_FAILED",
        {
          transactionId:
            currentTransactionId,

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
    /* ---------------------------------------------------------------------- */
    /* HTTP METHOD                                                            */
    /* ---------------------------------------------------------------------- */

    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    /* ---------------------------------------------------------------------- */
    /* AUTHENTICATED CLIENT                                                   */
    /* ---------------------------------------------------------------------- */

    authSupabase =
      createSupabaseClient(request);


    /* ---------------------------------------------------------------------- */
    /* REQUEST                                                                */
    /* ---------------------------------------------------------------------- */

    let body: {
      transaction?: TransactionData;
      fee_payment_method?: unknown;
    };

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    const transaction =
      body.transaction;

    if (!transaction) {
      throw new AppError(
        "TRANSACTION_DATA_IS_MISSING",
        400,
      );
    }


    if (transaction.v !== "v2") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
        400,
      );
    }


    const feePaymentMethod =
      parseFeePaymentMethod(
        body.fee_payment_method,
      );


    const transactionJson =
      transaction as unknown as Json;


    /* ---------------------------------------------------------------------- */
    /* TRUSTED CONTEXT                                                        */
    /* ---------------------------------------------------------------------- */

    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_cash_transfer_context",
      {
        p_v:
          String(transaction.v),
      },
    );


    if (contextError) {
      console.error(
        "CASH_TRANSFER_CONTEXT_FAILED",
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
          "CASH_TRANSFER_CONTEXT_FAILED",
      );
    }


    const context =
      (
        contextRows as
          CashTransferContext[] | null
      )?.[0];


    if (!context) {
      throw new AppError(
        "CASH_TRANSFER_CONTEXT_NOT_FOUND",
      );
    }


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
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }


    const versionTime =
      Number(context.version_time);

    if (!Number.isFinite(versionTime)) {
      throw new AppError(
        "INVALID_TRANSACTION_VERSION_TIME",
      );
    }


    /* ---------------------------------------------------------------------- */
    /* CREATE PROCESSING STATE EARLY                                          */
    /* ---------------------------------------------------------------------- */

    const {
      data: createdTransactionId,
      error: createError,
    } = await authSupabase.rpc(
      "create_my_transaction_state",
      {
        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.cash_transfer,
      },
    );


    if (createError) {
      console.error(
        "CASH_TRANSFER_STATE_CREATE_FAILED",
        {
          code:
            createError.code,

          message:
            createError.message,

          details:
            createError.details,

          hint:
            createError.hint,
        },
      );


      if (
        createError.code === "23505" ||
        createError.message ===
          "TRANSACTION_REPLAY"
      ) {
        throw new AppError(
          "TRANSACTION_REPLAY",
          409,
        );
      }


      throw new AppError(
        createError.message ||
          "TRANSACTION_STATE_CREATE_FAILED",
      );
    }


    if (!createdTransactionId) {
      throw new AppError(
        "TRANSACTION_STATE_CREATE_FAILED",
      );
    }


    transactionId =
      String(createdTransactionId);


    /* ---------------------------------------------------------------------- */
    /* TRANSACTION VERIFICATION                                               */
    /* ---------------------------------------------------------------------- */

    TransactionVerificationService
      .validateTransactionFields(
        transaction,
      );


    TransactionVerificationService
      .validateTransactionTimestamp(
        transaction,
        versionTime,
      );


    const signatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.wallet_address,
        );


    if (!signatureValid) {
      throw new AppError(
        "USER_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /* ---------------------------------------------------------------------- */
    /* REQUEST IP                                                             */
    /* ---------------------------------------------------------------------- */

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";


    /* ---------------------------------------------------------------------- */
    /* FINANCIAL POSTING AND ATOMIC REDEMPTION                                */
    /* ---------------------------------------------------------------------- */

    const postingSupabase =
      createSupabaseServiceClient();


    const {
      data,
      error: postingError,
    } = await postingSupabase.rpc(
      "cash_transfer",
      {
        p_transaction_state_id:
          transactionId,

        p_sender_id:
          context.sender_id,

        p_country_code:
          context.country_code,

        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.cash_transfer,

        p_ip_address:
          ipAddress,

        p_fee_payment_method:
          feePaymentMethod,
      },
    );


    if (postingError) {
      console.error(
        "CASH_TRANSFER_POSTING_FAILED",
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

          senderId:
            context.sender_id,

          feePaymentMethod,
        },
      );


      /*
       * Keep this immediate failure update. It prevents
       * processing transactions from remaining stuck.
       */
      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "CASH_TRANSFER_FAILED",
        );


      throw new AppError(
        postingError.message ||
          "CASH_TRANSFER_FAILED",
      );
    }


    /*
     * The stored procedure committed financial posting,
     * optional points redemption, wallet posting, and
     * transaction_state -> success.
     */
    transactionCompleted = true;


    /* ---------------------------------------------------------------------- */
    /* RESULT                                                                 */
    /* ---------------------------------------------------------------------- */

    const result =
      (
        Array.isArray(data)
          ? data[0]
          : data
      ) as CashTransferResult | null;


  if (!result?.success) {
    /*
     * Accounting has already committed, so this error
     * must never cause the transaction state to become failed.
     */
    throw new AppError(
      "CASH_TRANSFER_RESULT_NOT_FOUND",
    );
  }


  /* ---------------------------------------------------------------------- */
  /* FINANCIAL INTELLIGENCE - SENDER                                        */
  /* ---------------------------------------------------------------------- */

  /*
   * The sender transferred result.amount, but the actual
   * reduction of the sender wallet is result.sender_debit.
   *
   * sender_debit includes all charges that remained payable
   * in cash after the fee-payment method was applied.
   *
   * This is post-commit auxiliary processing. Any failure
   * must be logged and must NOT affect the completed transfer.
   */
  try {
    const senderFinancialActivityOutcome =
      await recordFinancialActivity(
        postingSupabase,
        {
          reference:
            result.reference,

          userId:
            context.sender_id,

          countryCode:
            context.country_code,

          currencyCode:
            result.currency,

          transactionType:
            TransactionType.cash_transfer,

          activityType:
            FinancialActivityType.withdrawal,

          /*
           * The actual transfer activity.
           */
          amount:
            result.amount,

          amountUsd:
            result.amount_usd,

          /*
           * The actual reduction in the sender's
           * cash/savings position.
           */
          cashAmount:
            result.sender_debit,

          cashAmountUsd:
            result.sender_debit_usd,
        },
      );


    if (
      senderFinancialActivityOutcome.status ===
      "failed"
    ) {
      console.error(
        "CASH_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_FAILED",
        {
          transactionId,

          reference:
            result.reference,

          senderId:
            context.sender_id,

          currency:
            result.currency,

          amount:
            result.amount,

          senderDebit:
            result.sender_debit,

          error:
            senderFinancialActivityOutcome.error,
        },
      );
    }
  } catch (financialActivityError) {
    /*
     * Defensive local catch.
     *
     * recordFinancialActivity itself should already be
     * non-throwing, but this protects the transaction if
     * that implementation ever changes or an unexpected
     * runtime exception occurs.
     */
    console.error(
      "CASH_TRANSFER_SENDER_FINANCIAL_INTELLIGENCE_EXCEPTION",
      {
        transactionId,

        reference:
          result.reference,

        senderId:
          context.sender_id,

        currency:
          result.currency,

        error:
          financialActivityError instanceof Error
            ? financialActivityError.message
            : String(financialActivityError),
      },
    );
  }


  /* ---------------------------------------------------------------------- */
  /* FINANCIAL INTELLIGENCE - RECEIVER                                      */
  /* ---------------------------------------------------------------------- */

  /*
   * The receiver receives only the amount entered by
   * the sender. Sender fees/charges never belong to
   * the receiver's deposit/savings inflow.
   */
  try {
    const receiverFinancialActivityOutcome =
      await recordFinancialActivity(
        postingSupabase,
        {
          reference:
            result.reference,

          userId:
            result.receiver_id,

          countryCode:
            context.country_code,

          currencyCode:
            result.currency,

          transactionType:
            TransactionType.cash_transfer,

          activityType:
            FinancialActivityType.deposit,

          /*
           * Receiver gets only the transfer amount.
           */
          amount:
            result.amount,

          amountUsd:
            result.amount_usd,

          cashAmount:
            result.amount,

          cashAmountUsd:
            result.amount_usd,
        },
      );


    if (
      receiverFinancialActivityOutcome.status ===
      "failed"
    ) {
      console.error(
        "CASH_TRANSFER_RECEIVER_FINANCIAL_INTELLIGENCE_FAILED",
        {
          transactionId,

          reference:
            result.reference,

          receiverId:
            result.receiver_id,

          currency:
            result.currency,

          amount:
            result.amount,

          error:
            receiverFinancialActivityOutcome.error,
        },
      );
    }
  } catch (financialActivityError) {
    console.error(
      "CASH_TRANSFER_RECEIVER_FINANCIAL_INTELLIGENCE_EXCEPTION",
      {
        transactionId,

        reference:
          result.reference,

        receiverId:
          result.receiver_id,

        currency:
          result.currency,

        error:
          financialActivityError instanceof Error
            ? financialActivityError.message
            : String(financialActivityError),
      },
    );
  }


  /* ---------------------------------------------------------------------- */
  /* POST-COMMIT LOYALTY EARNING                                            */
  /* ---------------------------------------------------------------------- */


    let loyalty: TransactionLoyaltyResult | null =
      result.loyalty;


    /* ---------------------------------------------------------------------- */
    /* POST-COMMIT LOYALTY EARNING                                            */
    /* ---------------------------------------------------------------------- */

    /*
     * A cash-paid transfer may earn points. A points-paid
     * transfer cannot earn new transfer points.
     */
    if (
      result.fee_payment_method === "cash"
    ) {
      const loyaltyOutcome =
        await awardCompletedTransactionLoyalty(
        postingSupabase,
        {
          transactionType:
            TransactionType.cash_transfer,

          userId:
            context.sender_id,

          reference:
            result.reference,

          sourceTransactionId:
            result.financial_transaction_id,

          amount:
            result.amount,

          amountUsd:
            result.amount_usd,

          countryCode:
            context.country_code,

          currencyCode:
            result.currency,

          metadata: {
            fee_payment_method:
              result.fee_payment_method,

            original_fee:
              result.original_fee,

            cash_fee:
              result.cash_fee,
          },
        },
        );

      if (
        loyaltyOutcome.status === "completed"
      ) {
        const award = loyaltyOutcome.result;

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
            award.previous_level_code ?? null,
          level_code:
            award.level_code ?? null,
          level_changed:
            award.level_changed ?? false,
        };
      }
    } else {
      /*
       * The points-paid transfer earns no new points, but
       * it still counts as completed transfer activity for
       * badge milestones such as First Transfer.
       */
      const {
        error: activityError,
      } = await postingSupabase.rpc(
        "record_non_earning_transfer_activity",
        {
          p_idempotency_key:
            `loyalty-activity:user_transfer:${result.reference}`,

          p_user_id:
            context.sender_id,

          p_source_reference:
            result.reference,

          p_source_transaction_id:
            result.financial_transaction_id,

          p_amount:
            result.amount,

          p_amount_usd:
            result.amount_usd,

          p_country_code:
            context.country_code,

          p_currency_code:
            result.currency,

          p_metadata: {
            fee_payment_method:
              result.fee_payment_method,

            points_redeemed:
              result.points_redeemed,

            redemption_ledger_id:
              result.redemption_ledger_id,
          },
        },
      );

      if (activityError) {
        /*
         * Financial posting and points redemption are
         * already committed. Badge activity failure must
         * not change the transfer to failed.
         */
        console.error(
          "CASH_TRANSFER_LOYALTY_ACTIVITY_FAILED",
          {
            transactionId,
            reference:
              result.reference,
            code:
              activityError.code,
            message:
              activityError.message,
            details:
              activityError.details,
            hint:
              activityError.hint,
          },
        );
      }
    }


    /* ---------------------------------------------------------------------- */
    /* PUSH                                                                   */
    /* ---------------------------------------------------------------------- */

    const deviceTokens = [
      ...new Set(
        (
          result.device_tokens ??
          []
        )
          .map(
            token =>
              token.trim(),
          )
          .filter(
            token =>
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
              result
                .receiver_notification_id ??
              "",

            reference:
              result.push_reference ??
              "",
          },
        });
      } catch (pushError) {
        console.error(
          "CASH_TRANSFER_PUSH_FAILED",
          {
            transactionId,

            notificationId:
              result
                .receiver_notification_id,

            reference:
              result.push_reference,

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
        result.success,

      amount:
        result.amount,

      /*
       * Preserve the existing fee field as the actual
       * cash fee charged to the wallet.
       */
      fee:
        result.cash_charges,

      original_fee:
        result.original_fee,

      fee_payment_method:
        result.fee_payment_method,

      points_redeemed:
        result.points_redeemed,

      loyalty,

      currency:
        result.currency,
    });
  } catch (error) {
    /*
     * FINAL SAFETY NET.
     *
     * Keep this even though posting failures already
     * try to update the state inside the posting branch.
     */
    if (
      authSupabase &&
      transactionId &&
      !transactionCompleted &&
      !failureStateUpdated
    ) {
      const failureMessage =
        error instanceof Error
          ? error.message
          : "CASH_TRANSFER_FAILED";


      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }


    return errorResponse(
      error,
      "CASH_TRANSFER_FAILED",
    );
  }
});
