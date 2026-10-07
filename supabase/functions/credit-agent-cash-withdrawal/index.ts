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
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";


type CashWithdrawalContext = {
  agent_id: string;
  country_code: string;
  agent_wallet_address: string;

  user_id: string;
  user_country_code: string;
  user_wallet_address: string;

  version_time: number;
};


type CreditAgentCashWithdrawalResult = {
  success: boolean;

  document_no: string;

  /*
   * Cash amount received by the credit agent.
   */
  amount: string;

  fee: string;
  tax: string;
  currency: string;

  holding_used: string;
  receivable_used: string;

  user_notification_id:
    string | null;

  device_tokens:
    string[] | null;

  push_title:
    string | null;

  push_body:
    string | null;

  push_reference:
    string | null;

  /*
   * Financial Intelligence values returned by the
   * posting RPC.
   */
  amount_usd: string;

  /*
   * Exact customer-wallet debit including applicable
   * withdrawal charges.
   */
  sender_debit: string;

  /*
   * Exact customer-wallet debit converted to USD using
   * the transaction-time current rate.
   */
  sender_debit_usd: string;
};


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  let failureStateUpdated =
    false;

  /*
   * Once PostgreSQL completes the posting, subsequent
   * Financial Intelligence or push failures must never
   * mark the transaction as failed.
   */
  let transactionCompleted =
    false;

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
          "Credit-agent cash-withdrawal state update failed",
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
        "Credit-agent cash-withdrawal state update failed",
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
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }


    /*
     * The authenticated caller is the merchant who is
     * processing the customer withdrawal.
     */
    authSupabase =
      createSupabaseClient(request);


    let body: {
      transaction?: TransactionData;
      approval?: SenderApproval;
    };


    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }


    const transaction =
      body.transaction;

    const approval =
      body.approval;


    if (!transaction) {
      throw new AppError(
        "TRANSACTION_DATA_IS_MISSING",
      );
    }


    if (!approval) {
      throw new AppError(
        "SENDER_APPROVAL_IS_MISSING",
      );
    }


    /*
     * Credit-agent cash withdrawal uses the same signed
     * v3 format as standard cash withdrawal.
     */
    if (transaction.v !== "v3") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }


    const transactionJson =
      transaction as unknown as Json;

    const approvalJson =
      approval as unknown as Json;


    /*
     * ==========================================================
     * FETCH WITHDRAWAL CONTEXT
     * ==========================================================
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_cash_withdrawal_context",
      {
        p_v:
          transaction.v,

        p_user_id:
          transaction.s,
      },
    );


    if (contextError) {
      console.error(
        "Credit-agent cash-withdrawal context failed",
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
          "CASH_WITHDRAWAL_CONTEXT_FAILED",
      );
    }


    const context =
      (
        contextRows as unknown as
          CashWithdrawalContext[] | null
      )?.[0];


    if (!context) {
      throw new AppError(
        "CASH_WITHDRAWAL_CONTEXT_NOT_FOUND",
      );
    }


    if (!context.agent_id) {
      throw new AppError(
        "MERCHANT_NOT_FOUND",
      );
    }


    if (!context.country_code) {
      throw new AppError(
        "MERCHANT_COUNTRY_NOT_CONFIGURED",
      );
    }


    if (!context.agent_wallet_address) {
      throw new AppError(
        "MERCHANT_WALLET_ADDRESS_NOT_FOUND",
      );
    }


    if (!context.user_id) {
      throw new AppError(
        "USER_NOT_FOUND",
      );
    }


    if (!context.user_wallet_address) {
      throw new AppError(
        "USER_WALLET_ADDRESS_NOT_FOUND",
      );
    }


    /*
     * ==========================================================
     * CREATE PROCESSING TRANSACTION STATE
     * ==========================================================
     */
    const {
      data: createdTransactionId,
      error: createError,
    } = await authSupabase.rpc(
      "create_my_credit_agent_cash_withdrawal_state",
      {
        p_transaction:
          transactionJson,

        p_sender_approval:
          approvalJson,
      },
    );


    if (createError) {
      console.error(
        "Credit-agent cash-withdrawal state creation failed",
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


    /*
     * ==========================================================
     * VERIFY MERCHANT APPROVAL SIGNATURE
     * ==========================================================
     */
    const merchantSignatureValid =
      TransactionVerificationService
        .verifySenderSignature(
          approval,
          context.agent_wallet_address,
        );


    if (!merchantSignatureValid) {
      throw new AppError(
        "MERCHANT_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /*
     * ==========================================================
     * VERIFY WITHDRAWING USER SIGNATURE
     * ==========================================================
     */
    const userSignatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.user_wallet_address,
        );


    if (!userSignatureValid) {
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
        Number(context.version_time),
      );


    /*
     * Transaction and merchant approval must describe
     * exactly the same withdrawal.
     */
    if (
      transaction.a !==
      approval.a
    ) {
      throw new AppError(
        "AMOUNT_MISMATCH",
      );
    }


    if (
      transaction.c !==
      approval.c
    ) {
      throw new AppError(
        "CURRENCY_MISMATCH",
      );
    }


    if (
      transaction.r !==
      approval.r
    ) {
      throw new AppError(
        "REFERENCE_MISMATCH",
      );
    }


    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";


    /*
     * ==========================================================
     * POST FINANCIAL TRANSACTION
     * ==========================================================
     */
    const postingSupabase =
      createSupabaseServiceClient();


    const {
      data,
      error: postingError,
    } = await postingSupabase.rpc(
      "credit_agent_cash_withdrawal",
      {
        p_agent_id:
          context.agent_id,

        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.credit_agent_cash_withdrawal,

        p_country_code:
          context.country_code,

        p_transaction_state_id:
          transactionId,

        p_ip_address:
          ipAddress,
      },
    );


    if (postingError) {
      console.error(
        "CREDIT_AGENT_CASH_WITHDRAWAL_POSTING_FAILED",
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
            context.agent_id,

          userId:
            context.user_id,
        },
      );


      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "CREDIT_AGENT_CASH_WITHDRAWAL_FAILED",
        );


      throw new AppError(
        postingError.message ||
          "CREDIT_AGENT_CASH_WITHDRAWAL_FAILED",
      );
    }


    /*
     * ==========================================================
     * FINANCIAL POSTING HAS COMMITTED
     * ==========================================================
     *
     * Set immediately after PostgreSQL returns without
     * a posting error.
     *
     * Nothing after this point may change the financial
     * transaction to failed.
     */
    transactionCompleted =
      true;


    const result =
      (
        data as unknown as
          CreditAgentCashWithdrawalResult[] | null
      )?.[0];


    if (!result?.success) {
      throw new AppError(
        "CREDIT_AGENT_CASH_WITHDRAWAL_RESULT_NOT_FOUND",
      );
    }


    /*
     * ==========================================================
     * FINANCIAL INTELLIGENCE
     * ==========================================================
     *
     * Same Financial Intelligence treatment as normal
     * cash withdrawal.
     *
     *
     * WITHDRAWING CUSTOMER
     * --------------------
     *
     * withdrawal:
     *
     *     amount =
     *         cash amount withdrawn
     *
     * savings outflow:
     *
     *     cashAmount =
     *         full wallet debit including charges
     *
     *
     * RECEIVING CREDIT AGENT / MERCHANT
     * ---------------------------------
     *
     * deposit:
     *
     *     amount =
     *         cash amount received
     *
     * savings inflow:
     *
     *     cashAmount =
     *         cash amount received
     *
     *
     * No loyalty points are awarded.
     */


    /*
     * ==========================================================
     * WITHDRAWING CUSTOMER FINANCIAL POT
     * ==========================================================
     */
    try {
      const userFinancialActivityOutcome =
        await recordFinancialActivity(
          postingSupabase,
          {
            reference:
              result.document_no,

            userId:
              context.user_id,

            countryCode:
              context.country_code,

            currencyCode:
              result.currency,

            transactionType:
              TransactionType.credit_agent_cash_withdrawal,

            activityType:
              FinancialActivityType.withdrawal,

            /*
             * Withdrawal behaviour amount.
             */
            amount:
              result.amount,

            amountUsd:
              result.amount_usd,

            /*
             * Actual savings outflow.
             *
             * This is the exact customer-wallet debit
             * including fee/tax/other customer charges.
             */
            cashAmount:
              result.sender_debit,

            cashAmountUsd:
              result.sender_debit_usd,
          },
        );


      if (
        userFinancialActivityOutcome.status ===
        "failed"
      ) {
        console.error(
          "CREDIT_AGENT_CASH_WITHDRAWAL_USER_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            reference:
              result.document_no,

            userId:
              context.user_id,

            merchantId:
              context.agent_id,

            currency:
              result.currency,

            amount:
              result.amount,

            amountUsd:
              result.amount_usd,

            senderDebit:
              result.sender_debit,

            senderDebitUsd:
              result.sender_debit_usd,

            error:
              userFinancialActivityOutcome.error,
          },
        );
      }
    } catch (financialActivityError) {
      console.error(
        "CREDIT_AGENT_CASH_WITHDRAWAL_USER_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          reference:
            result.document_no,

          userId:
            context.user_id,

          merchantId:
            context.agent_id,

          currency:
            result.currency,

          error:
            financialActivityError instanceof Error
              ? financialActivityError.message
              : String(financialActivityError),
        },
      );
    }


    /*
     * ==========================================================
     * CREDIT AGENT / MERCHANT FINANCIAL POT
     * ==========================================================
     *
     * The merchant receives ONLY result.amount.
     *
     * Customer withdrawal fees and tax do not form part
     * of the merchant's deposit/savings inflow.
     */
    try {
      const merchantFinancialActivityOutcome =
        await recordFinancialActivity(
          postingSupabase,
          {
            reference:
              result.document_no,

            userId:
              context.agent_id,

            countryCode:
              context.country_code,

            currencyCode:
              result.currency,

            transactionType:
              TransactionType.credit_agent_cash_withdrawal,

            activityType:
              FinancialActivityType.deposit,

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
        merchantFinancialActivityOutcome.status ===
        "failed"
      ) {
        console.error(
          "CREDIT_AGENT_CASH_WITHDRAWAL_MERCHANT_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            reference:
              result.document_no,

            merchantId:
              context.agent_id,

            userId:
              context.user_id,

            currency:
              result.currency,

            amount:
              result.amount,

            amountUsd:
              result.amount_usd,

            error:
              merchantFinancialActivityOutcome.error,
          },
        );
      }
    } catch (financialActivityError) {
      console.error(
        "CREDIT_AGENT_CASH_WITHDRAWAL_MERCHANT_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          reference:
            result.document_no,

          merchantId:
            context.agent_id,

          userId:
            context.user_id,

          currency:
            result.currency,

          error:
            financialActivityError instanceof Error
              ? financialActivityError.message
              : String(financialActivityError),
        },
      );
    }


    /*
     * ==========================================================
     * PUSH NOTIFICATION
     * ==========================================================
     *
     * Push failure cannot affect the already committed
     * withdrawal.
     */
    const deviceTokens =
      result.device_tokens ?? [];


    if (
      deviceTokens.length > 0 &&
      result.push_title &&
      result.push_body
    ) {
      try {
        const pushData:
          Record<string, string> = {};


        if (
          result.user_notification_id
        ) {
          pushData.notification_id =
            result.user_notification_id;
        }


        if (
          result.push_reference
        ) {
          pushData.reference =
            result.push_reference;
        }


        const pushResult =
          await sendPushNotification({
            tokens:
              deviceTokens,

            title:
              result.push_title,

            body:
              result.push_body,

            data:
              pushData,
          });


        if (
          pushResult &&
          pushResult.failureCount > 0
        ) {
          console.error(
            "CREDIT_AGENT_CASH_WITHDRAWAL_PUSH_PARTIAL_FAILURE",
            {
              transactionId,

              successCount:
                pushResult.successCount,

              failureCount:
                pushResult.failureCount,

              responses:
                pushResult.responses.map(
                  (
                    response,
                    index,
                  ) => ({
                    token:
                      deviceTokens[index],

                    success:
                      response.success,

                    error:
                      response.error
                        ?.message,
                  }),
                ),
            },
          );
        }
      } catch (pushError) {
        console.error(
          "CREDIT_AGENT_CASH_WITHDRAWAL_PUSH_FAILED",
          {
            transactionId,

            error:
              pushError instanceof Error
                ? pushError.message
                : String(pushError),
          },
        );
      }
    }


    /*
     * Internal posting details, Financial Intelligence
     * details and device tokens are deliberately not
     * returned to Flutter.
     */
    return successResponse({
      success: true,
    });
  } catch (error) {
    /*
     * A transaction can only be changed to failed before
     * the financial posting has committed.
     */
    if (
      transactionId &&
      !transactionCompleted &&
      !failureStateUpdated
    ) {
      const failureMessage =
        error instanceof Error
          ? error.message
          : "CREDIT_AGENT_CASH_WITHDRAWAL_FAILED";


      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }


    return errorResponse(
      error,
      "CREDIT_AGENT_CASH_WITHDRAWAL_FAILED",
    );
  }
});
