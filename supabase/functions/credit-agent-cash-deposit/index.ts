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
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";


type TransactionLoyaltyResult = {
  points_earned: number;
  points_spent: number;
  available_points: number;
  tier_points: number;
  previous_level_code: string | null;
  level_code: string | null;
  level_changed: boolean;
};


type CreditAgentCashDepositContext = {
  user_id: string;
  country_code: string;
  user_wallet_address: string;

  provider_id: string;
  provider_country_code: string;
  provider_wallet_address: string;

  version_time: number;
};


type CreditAgentCashDepositResult = {
  success: boolean;
  reference: string;
  customer_id: string;
  gross_amount: string;

  /*
   * These values must be returned by the
   * credit_agent_cash_deposit RPC.
   *
   * gross_amount_usd must use the rate applied to the
   * completed posting.
   */
  gross_amount_usd:
    string | null;

  financial_transaction_id:
    string | null;

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


Deno.serve(async (request: Request) => {
  let transactionId:
    string | null = null;

  let failureStateUpdated =
    false;

  /*
   * Once the accounting transaction has committed,
   * secondary processing must never change it to failed.
   */
  let transactionCompleted =
    false;

  let authSupabase:
    ReturnType<
      typeof createSupabaseClient
    > | null = null;


  /*
   * Update a processing transaction to failed.
   *
   * The posting-error branch attempts this first.
   * The outer catch retries only when that first
   * attempt was unsuccessful.
   *
   * A completed financial transaction must never
   * be changed to failed.
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
          "Credit-agent cash-deposit state update failed",
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
        "Credit-agent cash-deposit state update failed",
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
     * Authenticated client:
     *
     * - identifies the caller;
     * - fetches trusted context;
     * - creates the processing state;
     * - updates failed states.
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
        "TRANSACTION_DATA_MISSING",
      );
    }


    if (!approval) {
      throw new AppError(
        "SENDER_APPROVAL_MISSING",
      );
    }


    /*
     * Credit-agent cash deposit remains on v1.
     */
    if (transaction.v !== "v1") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }


    /*
     * Database JSON values are used only when calling
     * PostgreSQL. Application validation continues to
     * use the strongly typed objects.
     */
    const transactionJson =
      transaction as unknown as Json;

    const approvalJson =
      approval as unknown as Json;


    /*
     * Fetch trusted participant information.
     *
     * PostgreSQL derives the initiating user from
     * auth.uid() and validates:
     *
     * - initiating role: customer, agent or vendor;
     * - provider role: agent or merchant;
     * - both users are active;
     * - both users belong to the same country.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_cash_deposit_context",
      {
        p_v:
          transaction.v,

        p_provider_id:
          transaction.s,
      },
    );


    if (contextError) {
      console.error(
        "Credit-agent cash-deposit context failed",
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
          "CREDIT_AGENT_CASH_DEPOSIT_CONTEXT_FAILED",
      );
    }


    const context =
      (
        contextRows as unknown as
          CreditAgentCashDepositContext[] | null
      )?.[0];


    if (!context) {
      throw new AppError(
        "CREDIT_AGENT_CASH_DEPOSIT_CONTEXT_NOT_FOUND",
      );
    }


    if (!context.user_id) {
      throw new AppError(
        "USER_NOT_FOUND",
      );
    }


    if (!context.country_code) {
      throw new AppError(
        "USER_COUNTRY_NOT_CONFIGURED",
      );
    }


    if (!context.user_wallet_address) {
      throw new AppError(
        "USER_WALLET_ADDRESS_NOT_FOUND",
      );
    }


    if (!context.provider_id) {
      throw new AppError(
        "PROVIDER_NOT_FOUND",
      );
    }


    if (!context.provider_country_code) {
      throw new AppError(
        "PROVIDER_COUNTRY_NOT_CONFIGURED",
      );
    }


    if (!context.provider_wallet_address) {
      throw new AppError(
        "PROVIDER_WALLET_ADDRESS_NOT_FOUND",
      );
    }


    /*
     * Create the processing transaction state before
     * cryptographic verification.
     *
     * Validation failures after this point are recorded
     * as failed transaction states.
     */
    const {
      data: createdTransactionId,
      error: createError,
    } = await authSupabase.rpc(
      "create_my_credit_agent_cash_deposit_state",
      {
        p_transaction:
          transactionJson,

        p_sender_approval:
          approvalJson,
      },
    );


    if (createError) {
      console.error(
        "Credit-agent cash-deposit state creation failed",
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
     * Verify the provider's signed transaction.
     */
    const providerSignatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.provider_wallet_address,
        );


    if (!providerSignatureValid) {
      throw new AppError(
        "AGENT_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /*
     * Verify the receiving user's approval.
     */
    const userApprovalValid =
      TransactionVerificationService
        .verifySenderSignature(
          approval,
          context.user_wallet_address,
        );


    if (!userApprovalValid) {
      throw new AppError(
        "USER_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /*
     * Validate transaction fields and configured
     * transaction-version lifetime.
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
     * The signed transaction and signed approval must
     * refer to the same payment.
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
     * Only this server-side client holds the service-role
     * key.
     *
     * The credit_agent_cash_deposit RPC is not executable
     * by authenticated or anonymous clients.
     */
    const postingSupabase =
      createSupabaseServiceClient();


    const {
      data,
      error: postingError,
    } = await postingSupabase.rpc(
      "credit_agent_cash_deposit",
      {
        p_user_id:
          context.user_id,

        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.credit_agent_cash_deposit,

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
        "CREDIT_AGENT_CASH_DEPOSIT_POSTING_FAILED",
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

          userId:
            context.user_id,

          providerId:
            context.provider_id,
        },
      );


      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "CREDIT_AGENT_CASH_DEPOSIT_FAILED",
        );


      throw new AppError(
        postingError.message ||
          "CREDIT_AGENT_CASH_DEPOSIT_FAILED",
      );
    }


    /*
     * The accounting transaction has committed.
     *
     * Everything after this point is secondary processing
     * and must never change the financial transaction
     * state to failed.
     */
    transactionCompleted =
      true;


    const result =
      (
        data as unknown as
          CreditAgentCashDepositResult[] | null
      )?.[0];


    if (!result?.success) {
      throw new AppError(
        "CREDIT_AGENT_CASH_DEPOSIT_RESULT_NOT_FOUND",
      );
    }


    /*
     * ==========================================================
     * FINANCIAL INTELLIGENCE
     * ==========================================================
     *
     * A credit-agent cash deposit has the same financial
     * behaviour meaning as a normal cash deposit.
     *
     * The receiving customer gets:
     *
     * deposit        += gross_amount
     * savings inflow += gross_amount
     *
     * The company-funded provider does not get a financial
     * intelligence deposit entry for this transaction.
     *
     * Financial Intelligence is post-commit and therefore
     * must never affect the completed transaction.
     */
    if (result.gross_amount_usd) {
      try {
        const financialActivityOutcome =
          await recordFinancialActivity(
            postingSupabase,
            {
              reference:
                result.reference,

              userId:
                result.customer_id,

              countryCode:
                context.country_code,

              currencyCode:
                transaction.c,

              transactionType:
                TransactionType.credit_agent_cash_deposit,

              activityType:
                FinancialActivityType.deposit,

              amount:
                result.gross_amount,

              amountUsd:
                result.gross_amount_usd,

              cashAmount:
                result.gross_amount,

              cashAmountUsd:
                result.gross_amount_usd,
            },
          );


        if (
          financialActivityOutcome.status ===
          "failed"
        ) {
          console.error(
            "CREDIT_AGENT_CASH_DEPOSIT_FINANCIAL_INTELLIGENCE_FAILED",
            {
              transactionId,

              reference:
                result.reference,

              customerId:
                result.customer_id,

              providerId:
                context.provider_id,

              currency:
                transaction.c,

              amount:
                result.gross_amount,

              amountUsd:
                result.gross_amount_usd,

              error:
                financialActivityOutcome.error,
            },
          );
        }
      } catch (financialActivityError) {
        console.error(
          "CREDIT_AGENT_CASH_DEPOSIT_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            transactionId,

            reference:
              result.reference,

            customerId:
              result.customer_id,

            providerId:
              context.provider_id,

            currency:
              transaction.c,

            error:
              financialActivityError instanceof Error
                ? financialActivityError.message
                : String(financialActivityError),
          },
        );
      }
    } else {
      /*
       * Missing USD value is an FI integration issue.
       * It must not affect the completed deposit.
       */
      console.error(
        "CREDIT_AGENT_CASH_DEPOSIT_FINANCIAL_INTELLIGENCE_USD_AMOUNT_MISSING",
        {
          transactionId,

          reference:
            result.reference,

          customerId:
            result.customer_id,

          providerId:
            context.provider_id,

          currency:
            transaction.c,
        },
      );
    }


    /*
     * ==========================================================
     * LOYALTY
     * ==========================================================
     *
     * Keep the existing loyalty behaviour unchanged.
     */
    let loyalty:
      TransactionLoyaltyResult | null =
        null;


    /*
     * The accounting transaction has committed at this
     * point. Loyalty failure must not change a successful
     * financial transaction to failed.
     *
     * The customer receiving the cash deposit earns the
     * points. The provider does not earn points here.
     */
    if (result.gross_amount_usd) {
      const loyaltyOutcome =
        await awardCompletedTransactionLoyalty(
          postingSupabase,
          {
            transactionType:
              TransactionType.credit_agent_cash_deposit,

            userId:
              result.customer_id,

            reference:
              result.reference,

            sourceTransactionId:
              result.financial_transaction_id ??
              transactionId,

            amount:
              result.gross_amount,

            amountUsd:
              result.gross_amount_usd,

            countryCode:
              context.country_code,

            currencyCode:
              transaction.c,

            metadata: {
              provider_id:
                context.provider_id,

              transaction_state_id:
                transactionId,
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
            award.previous_level_code ?? null,

          level_code:
            award.level_code ?? null,

          level_changed:
            award.level_changed ?? false,
        };
      }
    } else {
      /*
       * This is a loyalty integration/configuration error,
       * not a cash-deposit failure.
       */
      console.error(
        "CREDIT_AGENT_CASH_DEPOSIT_LOYALTY_USD_AMOUNT_MISSING",
        {
          transactionId,

          reference:
            result.reference,

          customerId:
            result.customer_id,

          currency:
            transaction.c,
        },
      );
    }


    /*
     * ==========================================================
     * PUSH NOTIFICATION
     * ==========================================================
     *
     * Push failure must not change a successful
     * financial transaction to failed.
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
          result.receiver_notification_id
        ) {
          pushData.notification_id =
            result.receiver_notification_id;
        }


        if (result.push_reference) {
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
            "CREDIT_AGENT_CASH_DEPOSIT_PUSH_PARTIAL_FAILURE",
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
          "CREDIT_AGENT_CASH_DEPOSIT_PUSH_FAILED",
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
     */
    return successResponse({
      success:
        result.success,

      reference:
        result.reference,

      customer_id:
        result.customer_id,

      amount:
        result.gross_amount,

      amount_usd:
        result.gross_amount_usd,

      currency:
        transaction.c,

      loyalty,
    });
  } catch (error) {
    /*
     * Retry the failed-state update only when:
     *
     * - a processing transaction exists;
     * - the financial posting has NOT completed;
     * - the posting-error branch did not already update it.
     *
     * Once transactionCompleted = true, Financial Intelligence,
     * loyalty, push or response-processing errors must never
     * change the completed transaction to failed.
     */
    if (
      transactionId &&
      !transactionCompleted &&
      !failureStateUpdated
    ) {
      const failureMessage =
        error instanceof Error
          ? error.message
          : "CREDIT_AGENT_CASH_DEPOSIT_FAILED";


      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }


    return errorResponse(
      error,
      "CREDIT_AGENT_CASH_DEPOSIT_FAILED",
    );
  }
});

