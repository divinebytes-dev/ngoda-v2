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


type CreditAgentCashSettlementContext = {
  merchant_id: string;
  merchant_country_code: string;
  merchant_wallet_address: string;

  accounts_id: string;
  accounts_country_code: string;
  accounts_wallet_address: string;

  treasury_id: string;

  version_time: number;
};


type CreditAgentCashSettlementResult = {
  success: boolean;

  document_number: string;
  reference: string;

  merchant_id: string;
  accounts_id: string;

  currency_code: string;
  settled_amount: string;

  cash_holding_before: string;
  cash_holding_after: string;

  merchant_notification_id:
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

  let failureStateUpdated = false;

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
      !currentTransactionId
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
          "Credit-agent cash-settlement state update failed",
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
        "Credit-agent cash-settlement state update failed",
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
     * The authenticated caller is the credit merchant.
     *
     * Accounts created and signed TransactionData.
     * The merchant scanned it, signed SenderApproval,
     * and submitted both values.
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

    if (transaction.v !== "v8") {
      throw new AppError(
        "OPERATION_NOT_ALLOWED",
      );
    }

    const transactionJson =
      transaction as unknown as Json;

    const approvalJson =
      approval as unknown as Json;

    /*
     * transaction.s contains the accounts user who
     * received the physical cash and signed the
     * transaction.
     *
     * PostgreSQL validates:
     *
     * - authenticated caller is an active merchant;
     * - merchant has an active credit-agent account;
     * - transaction.s belongs to active accounts;
     * - both users belong to the same country;
     * - treasury is fetched using merchant country;
     * - currency is active for the credit agent.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_credit_agent_cash_settlement_context",
      {
        p_v:
          transaction.v,

        p_accounts_id:
          transaction.s,

        p_currency_code:
          transaction.c,
      },
    );

    if (contextError) {
      console.error(
        "Credit-agent cash-settlement context failed",
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
          "CREDIT_AGENT_CASH_SETTLEMENT_CONTEXT_FAILED",
      );
    }

    const context =
      (
        contextRows as unknown as
          CreditAgentCashSettlementContext[] | null
      )?.[0];

    if (!context) {
      throw new AppError(
        "CREDIT_AGENT_CASH_SETTLEMENT_CONTEXT_NOT_FOUND",
      );
    }

    if (!context.merchant_id) {
      throw new AppError(
        "MERCHANT_NOT_FOUND",
      );
    }

    if (!context.merchant_country_code) {
      throw new AppError(
        "MERCHANT_COUNTRY_NOT_CONFIGURED",
      );
    }

    if (!context.merchant_wallet_address) {
      throw new AppError(
        "MERCHANT_WALLET_ADDRESS_NOT_FOUND",
      );
    }

    if (!context.accounts_id) {
      throw new AppError(
        "ACCOUNTS_USER_NOT_FOUND",
      );
    }

    if (!context.accounts_country_code) {
      throw new AppError(
        "ACCOUNTS_COUNTRY_NOT_CONFIGURED",
      );
    }

    if (!context.accounts_wallet_address) {
      throw new AppError(
        "ACCOUNTS_WALLET_ADDRESS_NOT_FOUND",
      );
    }

    if (!context.treasury_id) {
      throw new AppError(
        "TREASURY_NOT_FOUND",
      );
    }

    /*
     * Create processing state before signature
     * verification.
     */
    const {
      data: createdTransactionId,
      error: createError,
    } = await authSupabase.rpc(
      "create_my_credit_agent_cash_settlement_state",
      {
        p_transaction:
          transactionJson,

        p_sender_approval:
          approvalJson,
      },
    );

    if (createError) {
      console.error(
        "Credit-agent cash-settlement state creation failed",
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
     * Merchant confirms that the cash was handed over.
     */
    const merchantApprovalValid =
      TransactionVerificationService
        .verifySenderSignature(
          approval,
          context.merchant_wallet_address,
        );

    if (!merchantApprovalValid) {
      throw new AppError(
        "MERCHANT_SIGNATURE_VERIFICATION_FAILED",
      );
    }

    /*
     * Accounts confirms that the cash was received.
     */
    const accountsSignatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.accounts_wallet_address,
        );

    if (!accountsSignatureValid) {
      throw new AppError(
        "ACCOUNTS_SIGNATURE_VERIFICATION_FAILED",
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
     * TransactionData and SenderApproval must describe
     * the same settlement.
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
     * Service role performs the atomic financial
     * posting.
     */
    const postingSupabase =
      createSupabaseServiceClient();

    const {
      data,
      error: postingError,
    } = await postingSupabase.rpc(
      "credit_agent_cash_settlement",
      {
        p_merchant_id:
          context.merchant_id,

        p_transaction:
          transactionJson,

        p_transaction_type:
          TransactionType.credit_agent_cash_settlement,

        p_country_code:
          context.merchant_country_code,

        p_transaction_state_id:
          transactionId,

        p_ip_address:
          ipAddress,
      },
    );

    if (postingError) {
      console.error(
        "CREDIT_AGENT_CASH_SETTLEMENT_POSTING_FAILED",
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

          accountsId:
            context.accounts_id,

          treasuryId:
            context.treasury_id,
        },
      );

      failureStateUpdated =
        await markTransactionFailed(
          postingError.message ||
            "CREDIT_AGENT_CASH_SETTLEMENT_FAILED",
        );

      throw new AppError(
        postingError.message ||
          "CREDIT_AGENT_CASH_SETTLEMENT_FAILED",
      );
    }

    const result =
      (
        data as unknown as
          CreditAgentCashSettlementResult[] | null
      )?.[0];

    if (!result?.success) {
      throw new AppError(
        "CREDIT_AGENT_CASH_SETTLEMENT_RESULT_NOT_FOUND",
      );
    }

    /*
     * Financial posting has committed. Push failure
     * must not change the successful transaction state.
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

        if (result.merchant_notification_id) {
          pushData.notification_id =
            result.merchant_notification_id;
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
            "CREDIT_AGENT_CASH_SETTLEMENT_PUSH_PARTIAL_FAILURE",
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
          "CREDIT_AGENT_CASH_SETTLEMENT_PUSH_FAILED",
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
     * Do not expose internal posting data or device
     * tokens to Flutter.
     */
    return successResponse({
      success: true,
    });
  } catch (error) {
    /*
     * Preserve the outer retry so unexpected errors do
     * not leave transaction states in processing.
     */
    if (
      transactionId &&
      !failureStateUpdated
    ) {
      const failureMessage =
        error instanceof Error
          ? error.message
          : "CREDIT_AGENT_CASH_SETTLEMENT_FAILED";

      failureStateUpdated =
        await markTransactionFailed(
          failureMessage,
        );
    }

    return errorResponse(
      error,
      "CREDIT_AGENT_CASH_SETTLEMENT_FAILED",
    );
  }
});