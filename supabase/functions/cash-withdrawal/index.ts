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


type CashWithdrawalResult = {
  success: boolean;

  document_no: string;

  /*
   * Entered withdrawal amount.
   */
  amount: string;

  /*
   * Entered withdrawal amount converted to USD
   * by PostgreSQL using current_rates.
   */
  amount_usd: string;

  /*
   * Actual amount deducted from the withdrawing
   * user's wallet.
   *
   * This includes the withdrawal amount plus the
   * applicable cash charges.
   */
  sender_debit: string;

  /*
   * Actual sender wallet debit converted to USD.
   */
  sender_debit_usd: string;

  fee: string;
  tax: string;
  currency: string;

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
};


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  let failureStateUpdated =
    false;

  /*
   * Once the posting RPC succeeds, PostgreSQL has
   * committed the financial transaction.
   *
   * Nothing after that point may change the transaction
   * state to failed.
   */
  let transactionCompleted =
    false;

  let authSupabase:
    ReturnType<
      typeof createSupabaseClient
    > | null = null;


  /*
   * Mark the current processing transaction as failed.
   *
   * The posting-error branch attempts this first.
   *
   * The outer catch retries only when the first attempt
   * was unsuccessful.
   *
   * A successfully committed transaction must never be
   * marked failed by a post-commit process.
   */
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
          "Cash-withdrawal state update failed",
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
        "Cash-withdrawal state update failed",
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
     * ==========================================================
     * AUTHENTICATED CLIENT
     * ==========================================================
     *
     * Used for:
     *
     * - resolving authenticated agent/merchant;
     * - validating participants;
     * - creating processing state;
     * - recording transaction failure.
     */
    authSupabase =
      createSupabaseClient(request);


    /*
     * ==========================================================
     * REQUEST BODY
     * ==========================================================
     */
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
     * Cash withdrawal remains on v3.
     */
    if (transaction.v !== "v3") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }


    /*
     * Use strongly typed values in the Edge Function.
     *
     * Convert to Json only at RPC boundaries.
     */
    const transactionJson =
      transaction as unknown as Json;

    const approvalJson =
      approval as unknown as Json;


    /*
     * ==========================================================
     * FETCH TRUSTED WITHDRAWAL CONTEXT
     * ==========================================================
     *
     * PostgreSQL validates:
     *
     * - caller is agent/merchant;
     * - transaction.s belongs to an active user;
     * - user role is allowed;
     * - both users belong to the same country;
     * - agent and user are different users.
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
        "Cash-withdrawal context failed",
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
        "AGENT_NOT_FOUND",
      );
    }


    if (!context.country_code) {
      throw new AppError(
        "AGENT_COUNTRY_NOT_CONFIGURED",
      );
    }


    if (!context.agent_wallet_address) {
      throw new AppError(
        "AGENT_WALLET_ADDRESS_NOT_FOUND",
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
     *
     * This happens before signature verification so that
     * subsequent validation failures can be recorded.
     */
    const {
      data: createdTransactionId,
      error: createError,
    } = await authSupabase.rpc(
      "create_my_cash_withdrawal_state",
      {
        p_transaction:
          transactionJson,

        p_sender_approval:
          approvalJson,
      },
    );


    if (createError) {
      console.error(
        "Cash-withdrawal state creation failed",
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
     * VERIFY AGENT / MERCHANT APPROVAL
     * ==========================================================
     */
    const agentSignatureValid =
      TransactionVerificationService
        .verifySenderSignature(
          approval,
          context.agent_wallet_address,
        );


    if (!agentSignatureValid) {
      throw new AppError(
        "AGENT_SIGNATURE_VERIFICATION_FAILED",
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


    /*
     * ==========================================================
     * VALIDATE SIGNED TRANSACTION
     * ==========================================================
     */
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
     * Transaction and approval must represent the
     * same withdrawal.
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


    /*
     * ==========================================================
     * IP ADDRESS
     * ==========================================================
     */
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
     * POST CASH WITHDRAWAL
     * ==========================================================
     *
     * This RPC is privileged and therefore uses the
     * service-role client.
     */
    const postingSupabase =
      createSupabaseServiceClient();


    const {
      data,
      error: postingError,
    } = await postingSupabase.rpc(
      "cash_withdrawal",
      {
        p_agent_id:
          context.agent_id,

        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.cash_withdrawal,

        p_country_code:
          context.country_code,

        p_transaction_state_id:
          transactionId,

        p_ip_address:
          ipAddress,
      },
    );


    /*
     * ==========================================================
     * POSTING FAILURE
     * ==========================================================
     */
    if (postingError) {
      console.error(
        "CASH_WITHDRAWAL_POSTING_FAILED",
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

          agentId:
            context.agent_id,

          userId:
            context.user_id,
        },
      );


      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "CASH_WITHDRAWAL_FAILED",
        );


      throw new AppError(
        postingError.message ||
          "CASH_WITHDRAWAL_FAILED",
      );
    }


    /*
     * ==========================================================
     * FINANCIAL POSTING HAS COMMITTED
     * ==========================================================
     *
     * Set this immediately after PostgreSQL returns without
     * a posting error.
     *
     * Financial Intelligence and push notification are
     * secondary post-commit processes.
     *
     * They must never turn a successful financial
     * transaction into a failed transaction.
     */
    transactionCompleted =
      true;


    /*
     * ==========================================================
     * POSTING RESULT
     * ==========================================================
     */
    const result =
      (
        data as unknown as
          CashWithdrawalResult[] | null
      )?.[0];


    if (!result?.success) {
      throw new AppError(
        "CASH_WITHDRAWAL_RESULT_NOT_FOUND",
      );
    }


    /*
     * ==========================================================
     * FINANCIAL INTELLIGENCE
     * ==========================================================
     *
     * This withdrawal creates TWO Financial Intelligence
     * activities.
     *
     *
     * WITHDRAWING USER
     * ----------------
     *
     * withdrawal activity:
     *
     *     amount =
     *         entered withdrawal amount
     *
     * savings outflow:
     *
     *     cashAmount =
     *         actual wallet debit
     *
     * The wallet debit includes the withdrawal plus
     * applicable charges.
     *
     *
     * RECEIVING AGENT / MERCHANT
     * --------------------------
     *
     * deposit activity:
     *
     *     amount =
     *         entered withdrawal amount
     *
     * savings inflow:
     *
     *     cashAmount =
     *         entered withdrawal amount
     *
     * The agent receives only the entered amount.
     *
     *
     * No loyalty points are awarded for cash withdrawal.
     */


    /*
     * ==========================================================
     * FINANCIAL INTELLIGENCE — WITHDRAWING USER
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
              TransactionType.cash_withdrawal,

            activityType:
              FinancialActivityType.withdrawal,

            /*
             * Behaviour amount.
             *
             * This is the entered withdrawal amount.
             */
            amount:
              result.amount,

            amountUsd:
              result.amount_usd,

            /*
             * Savings movement.
             *
             * This is the exact wallet debit returned
             * by PostgreSQL.
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
          "CASH_WITHDRAWAL_USER_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            reference:
              result.document_no,

            userId:
              context.user_id,

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
        "CASH_WITHDRAWAL_USER_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          reference:
            result.document_no,

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
     * FINANCIAL INTELLIGENCE — RECEIVING AGENT / MERCHANT
     * ==========================================================
     *
     * The receiving agent receives ONLY result.amount.
     *
     * The withdrawing user's fees/tax are not part of the
     * agent's deposit or savings inflow.
     */
    try {
      const agentFinancialActivityOutcome =
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
              TransactionType.cash_withdrawal,

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
        agentFinancialActivityOutcome.status ===
        "failed"
      ) {
        console.error(
          "CASH_WITHDRAWAL_AGENT_FINANCIAL_INTELLIGENCE_FAILED",
          {
            transactionId,

            reference:
              result.document_no,

            agentId:
              context.agent_id,

            currency:
              result.currency,

            amount:
              result.amount,

            amountUsd:
              result.amount_usd,

            error:
              agentFinancialActivityOutcome.error,
          },
        );
      }
    } catch (financialActivityError) {
      console.error(
        "CASH_WITHDRAWAL_AGENT_FINANCIAL_INTELLIGENCE_EXCEPTION",
        {
          transactionId,

          reference:
            result.document_no,

          agentId:
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
     * PUSH NOTIFICATION
     * ==========================================================
     *
     * Push notification failure must not affect the
     * completed financial transaction.
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
            "CASH_WITHDRAWAL_PUSH_PARTIAL_FAILURE",
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
          "CASH_WITHDRAWAL_PUSH_FAILED",
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
     * ==========================================================
     * RESPONSE
     * ==========================================================
     *
     * Flutter only checks for an exception.
     */
    return successResponse({
      success: true,
    });
  } catch (error) {
    /*
     * ==========================================================
     * FAILURE HANDLING
     * ==========================================================
     *
     * Retry the failed-state update only when:
     *
     * - a transaction state exists;
     * - financial posting has NOT committed;
     * - the earlier posting-error state update did not
     *   already succeed.
     */
    if (
      transactionId &&
      !transactionCompleted &&
      !failureStateUpdated
    ) {
      const failureMessage =
        error instanceof Error
          ? error.message
          : "CASH_WITHDRAWAL_FAILED";


      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }


    return errorResponse(
      error,
      "CASH_WITHDRAWAL_FAILED",
    );
  }
});
