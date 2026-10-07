// supabase/functions/loan-disbursement/index.ts

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  getBlockchainWalletBalances,
} from "../../_shared/blockchain/balances.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";

import {
  FinancialActivityType,
} from "../../_shared/types/financial-activity-type.ts";


type LoanDisbursementRequest = {
  required_amount?:
    | string
    | number;

  reference?: string;
};


type LoanDisbursementContext = {
  wallet_address: string;
  country_code: string;
};


type LoanDisbursementResult = {
  success: boolean;

  document_number: string;

  loan_id: string;

  /*
   * Authoritative customer returned by the committed
   * PostgreSQL transaction.
   */
  customer_id: string;

  /*
   * Authoritative country returned by PostgreSQL.
   */
  country_code: string;

  /*
   * Loans are always USD.
   */
  currency_code: string;

  /*
   * Full loan principal.
   *
   * Example:
   *
   * loan principal = 100
   */
  principal_amount: string;

  collateral_locked: string;

  initiation_fee: string;

  /*
   * Actual USD credited to the customer's wallet.
   *
   * Example:
   *
   * principal      = 100
   * initiation fee = 2
   * net disbursed  = 98
   */
  net_disbursed: string;

  notification_id: string | null;

  device_tokens: string[] | null;

  push_title: string | null;

  push_body: string | null;

  push_reference: string | null;
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


function getErrorMessage(
  error: unknown,
  fallback: string,
): string {
  if (
    error instanceof Error &&
    error.message
  ) {
    return error.message;
  }

  if (
    typeof error === "string"
  ) {
    return error;
  }

  return fallback;
}


function getIpAddress(
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


Deno.serve(
  async (
    request: Request,
  ) => {
    try {
      /*
       * ========================================================
       * METHOD
       * ========================================================
       */
      if (
        request.method !==
          "POST"
      ) {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
        );
      }


      /*
       * ========================================================
       * AUTHENTICATED CLIENT
       * ========================================================
       */
      const authSupabase =
        createSupabaseClient(
          request,
        );

      const rpcClient =
        authSupabase as unknown as
          UntypedRpcClient;


      /*
       * ========================================================
       * REQUEST BODY
       * ========================================================
       */
      let body:
        LoanDisbursementRequest;

      try {
        body =
          await request.json();
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }


      const requiredAmount =
        body.required_amount;


      if (
        requiredAmount ===
          undefined ||
        requiredAmount ===
          null ||
        String(
          requiredAmount,
        ).trim() === ""
      ) {
        throw new AppError(
          "AMOUNT_REQUIRED",
        );
      }


      const reference =
        body.reference
          ?.trim();


      if (!reference) {
        throw new AppError(
          "REFERENCE_REQUIRED",
        );
      }


      /*
       * ========================================================
       * LOAN CONTEXT
       * ========================================================
       *
       * Reuse the loan preview context.
       *
       * It validates:
       *
       * - authentication
       * - allowed role
       * - active user
       * - wallet address
       * - country
       */
      const {
        data:
          contextData,

        error:
          contextError,
      } =
        await rpcClient.rpc(
          "fetch_my_loan_preview_context",
        );


      if (contextError) {
        console.error(
          "LOAN_DISBURSEMENT_CONTEXT_FAILED",
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
            "LOAN_DISBURSEMENT_CONTEXT_FAILED",
        );
      }


      const contextRows =
        contextData as
          LoanDisbursementContext[] |
          null;


      const context =
        contextRows?.[0];


      if (!context) {
        throw new AppError(
          "LOAN_DISBURSEMENT_CONTEXT_NOT_FOUND",
        );
      }


      if (
        !context.wallet_address
      ) {
        throw new AppError(
          "USER_WALLET_NOT_CONFIGURED",
        );
      }


      if (
        !context.country_code
      ) {
        throw new AppError(
          "USER_COUNTRY_NOT_CONFIGURED",
        );
      }


      /*
       * ========================================================
       * BLOCKCHAIN GOLD BALANCE
       * ========================================================
       *
       * Fetch the latest blockchain Gold balance immediately
       * before executing the loan.
       */
      const blockchainBalances =
        await getBlockchainWalletBalances(
          context.wallet_address,
        );


      if (
        !blockchainBalances
          .token_balance
      ) {
        throw new AppError(
          "BLOCKCHAIN_BALANCE_NOT_FOUND",
        );
      }


      const ipAddress =
        getIpAddress(
          request,
        );


      /*
       * ========================================================
       * EXECUTE LOAN
       * ========================================================
       *
       * PostgreSQL performs the entire financial transaction:
       *
       * - recalculates loan eligibility
       * - locks collateral
       * - posts GL
       * - credits wallet
       * - creates loan
       * - creates loan entry
       * - updates collateral
       * - updates snapshots
       *
       * Loans are always USD.
       */
      const {
        data:
          resultData,

        error:
          disbursementError,
      } =
        await rpcClient.rpc(
          "execute_my_loan_disbursement",
          {
            p_requested_amount:
              String(
                requiredAmount,
              ),

            p_token_balance:
              blockchainBalances
                .token_balance,

            p_reference:
              reference,

            p_currency_code:
              "usd",

            p_ip_address:
              ipAddress,
          },
        );


      /*
       * ========================================================
       * LOAN POSTING FAILED
       * ========================================================
       */
      if (
        disbursementError
      ) {
        console.error(
          "LOAN_DISBURSEMENT_RPC_FAILED",
          {
            code:
              disbursementError.code,

            message:
              disbursementError.message,

            details:
              disbursementError.details,

            hint:
              disbursementError.hint,

            reference,

            walletAddress:
              context.wallet_address,

            countryCode:
              context.country_code,
          },
        );


        if (
          disbursementError
            .code ===
            "23505" ||
          disbursementError
            .message ===
            "TRANSACTION_REPLAY" ||
          disbursementError
            .message
            .includes(
              "TRANSACTION_REPLAY",
            )
        ) {
          throw new AppError(
            "TRANSACTION_REPLAY",
            409,
          );
        }


        throw new AppError(
          disbursementError
            .message ||
            "LOAN_DISBURSEMENT_FAILED",
        );
      }


      /*
       * ========================================================
       * COMMITTED RESULT
       * ========================================================
       *
       * Once PostgreSQL returns this successful result, the loan
       * has already been committed.
       */
      const resultRows =
        resultData as
          LoanDisbursementResult[] |
          null;


      const result =
        resultRows?.[0];


      if (
        !result ||
        result.success !==
          true
      ) {
        throw new AppError(
          "LOAN_DISBURSEMENT_FAILED",
        );
      }


      /*
       * ========================================================
       * FINANCIAL INTELLIGENCE
       * ========================================================
       *
       * IMPORTANT:
       *
       * The loan is already committed.
       *
       * Financial Intelligence is secondary processing.
       * Failure here must NEVER change the successful loan.
       *
       *
       * Example:
       *
       * principal amount = 100
       * initiation fee   = 2
       * net disbursed    = 98
       *
       *
       * FI records:
       *
       * borrowing / loan increase:
       *
       *     +100
       *
       * savings / deposit inflow:
       *
       *     +98
       */
      try {
        const financialActivity =
          await recordFinancialActivity(
            authSupabase,
            {
              reference:

                reference,


              /*
               * Use the customer returned from the committed
               * PostgreSQL transaction.
               */
              userId:

                result.customer_id,


              countryCode:

                result.country_code,


              /*
               * Loans are always USD.
               */
              currencyCode:

                "usd",


              transactionType:

                "loan_disbursement",


              activityType:

                FinancialActivityType
                  .loan_disbursement,


              /*
               * Behavioral borrowing amount.
               *
               * This is the FULL loan principal.
               */
              amount:

                result.principal_amount,


              amountUsd:

                result.principal_amount,


              /*
               * Actual cash deposited into the customer's
               * USD wallet.
               *
               * This becomes savings inflow.
               */
              cashAmount:

                result.net_disbursed,


              cashAmountUsd:

                result.net_disbursed,


              /*
               * Explicit loan principal movement.
               */
              principalAmount:

                result.principal_amount,


              principalAmountUsd:

                result.principal_amount,


              /*
               * No interest is created during the
               * disbursement event.
               */
              interestAmount:

                "0.000000",


              interestAmountUsd:

                "0.000000",
            },
          );


        if (
          financialActivity
            .status ===
            "failed"
        ) {
          console.error(
            "LOAN_DISBURSEMENT_FINANCIAL_INTELLIGENCE_FAILED",
            {
              reference,

              documentNumber:
                result
                  .document_number,

              loanId:
                result.loan_id,

              customerId:
                result.customer_id,

              principalAmount:
                result
                  .principal_amount,

              netDisbursed:
                result
                  .net_disbursed,

              error:
                financialActivity
                  .error,
            },
          );
        }
      } catch (
        financialError
      ) {
        /*
         * Defensive boundary.
         *
         * recordFinancialActivity already catches its own
         * errors, but an unexpected exception here must still
         * never affect the committed loan.
         */
        console.error(
          "LOAN_DISBURSEMENT_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            reference,

            documentNumber:
              result
                .document_number,

            loanId:
              result.loan_id,

            customerId:
              result.customer_id,

            error:
              getErrorMessage(
                financialError,
                "FINANCIAL_INTELLIGENCE_FAILED",
              ),
          },
        );
      }


      /*
       * ========================================================
       * PUSH NOTIFICATION
       * ========================================================
       *
       * Push notification is also post-commit secondary
       * processing.
       *
       * Failure must not reverse or fail the loan.
       */
      const deviceTokens =
        result.device_tokens ??
        [];


      if (
        deviceTokens.length >
          0 &&
        result.push_title &&
        result.push_body
      ) {
        try {
          await sendPushNotification(
            {
              tokens:

                deviceTokens,


              title:

                result.push_title,


              body:

                result.push_body,


              data: {
                notification_id:

                  result
                    .notification_id ??
                  "",


                reference:

                  result
                    .push_reference ??
                  reference,


                transaction_type:

                  "loan_disbursement",


                document_number:

                  result
                    .document_number,


                loan_id:

                  result.loan_id,
              },
            },
          );
        } catch (
          pushError
        ) {
          console.error(
            "LOAN_DISBURSEMENT_PUSH_FAILED",
            {
              reference,

              documentNumber:
                result
                  .document_number,

              loanId:
                result.loan_id,

              notificationId:
                result
                  .notification_id,

              error:
                getErrorMessage(
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
      return successResponse(
        {
          success:

            true,


          document_number:

            result
              .document_number,


          loan_id:

            result.loan_id,


          principal_amount:

            result
              .principal_amount,


          collateral_locked:

            result
              .collateral_locked,


          initiation_fee:

            result
              .initiation_fee,


          net_disbursed:

            result
              .net_disbursed,
        },
      );
    } catch (error) {
      console.error(
        "LOAN_DISBURSEMENT_ERROR",
        {
          error:
            getErrorMessage(
              error,
              "LOAN_DISBURSEMENT_FAILED",
            ),
        },
      );


      return errorResponse(
        error,
        "LOAN_DISBURSEMENT_FAILED",
      );
    }
  },
);

