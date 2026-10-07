// supabase/functions/loan-repayment/index.ts

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  TransactionType,
} from "../../_shared/enums.ts";

import {
  FinancialActivityType,
} from "../../_shared/types/financial-activity-type.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  awardCompletedTransactionLoyalty,
} from "../../_shared/gamification/award-completed-transaction-loyalty.ts";

import {
  recordFinancialActivity,
} from "../../_shared/financial-intelligence/record-financial-activity.ts";


type LoanRepaymentRequest = {
  amount?:
    | string
    | number;

  reference?: string;
};


type LoanRepaymentResult = {
  success: boolean;

  document_number: string;

  principal_paid: string;

  interest_paid: string;

  collateral_unlocked: string;

  unused_payment: string;

  loans_closed: number;
};


type LoanRepaymentContext = {
  user_id: string;

  country_code: string;
};


type TransactionLoyaltyResult = {
  points_earned: number;

  points_spent: number;

  available_points: number;

  tier_points: number;

  previous_level_code:
    | string
    | null;

  level_code:
    | string
    | null;

  level_changed: boolean;
};


type RpcError = {
  code?: string;

  message: string;

  details?:
    | string
    | null;

  hint?:
    | string
    | null;
};


type RpcResult = {
  data: unknown;

  error:
    | RpcError
    | null;
};


type UntypedRpcClient = {
  rpc(
    functionName: string,
    parameters?: Record<
      string,
      unknown
    >,
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
    typeof error ===
      "string"
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

  if (
    forwardedAddress
  ) {
    return forwardedAddress;
  }

  return (
    request.headers
      .get("x-real-ip")
      ?.trim() ??
    "unknown"
  );
}


function addAmounts(
  left: string,
  right: string,
): string {
  const leftValue =
    Number(left);

  const rightValue =
    Number(right);

  if (
    !Number.isFinite(
      leftValue,
    ) ||
    !Number.isFinite(
      rightValue,
    )
  ) {
    throw new AppError(
      "INVALID_LOAN_REPAYMENT_RESULT",
    );
  }

  return (
    leftValue +
    rightValue
  ).toFixed(6);
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
       * REPAYMENT CONTEXT
       * ========================================================
       *
       * Resolve the authenticated beneficiary and country.
       *
       * Neither value is accepted from the request body.
       */
      const {
        data:
          contextData,

        error:
          contextError,
      } =
        await rpcClient.rpc(
          "fetch_my_loan_repayment_context",
        );


      if (
        contextError
      ) {
        console.error(
          "LOAN_REPAYMENT_CONTEXT_FAILED",
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
            "LOAN_REPAYMENT_CONTEXT_FAILED",
        );
      }


      const contextRows =
        contextData as
          LoanRepaymentContext[] |
          null;


      const context =
        contextRows?.[0];


      if (
        !context?.user_id
      ) {
        throw new AppError(
          "USER_NOT_FOUND",
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
       * REQUEST BODY
       * ========================================================
       */
      let body:
        LoanRepaymentRequest;


      try {
        body =
          await request.json();
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }


      const amount =
        body.amount;


      if (
        amount ===
          undefined ||
        amount ===
          null ||
        String(
          amount,
        ).trim() === ""
      ) {
        throw new AppError(
          "AMOUNT_REQUIRED",
        );
      }


      const repaymentAmount =
        String(
          amount,
        ).trim();


      const reference =
        body.reference
          ?.trim();


      if (
        !reference
      ) {
        throw new AppError(
          "REFERENCE_REQUIRED",
        );
      }


      const ipAddress =
        getIpAddress(
          request,
        );


      /*
       * ========================================================
       * EXECUTE REPAYMENT
       * ========================================================
       *
       * PostgreSQL:
       *
       * - derives the authenticated customer
       * - locks active loans
       * - allocates interest first
       * - allocates remaining amount to principal
       * - unlocks collateral
       * - posts GL
       * - posts wallet entries
       * - updates loan entries
       * - updates snapshots
       *
       * Everything is committed atomically.
       */
      const {
        data:
          resultData,

        error:
          repaymentError,
      } =
        await rpcClient.rpc(
          "execute_my_loan_repayment",
          {
            p_amount:
              repaymentAmount,

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
       * REPAYMENT FAILURE
       * ========================================================
       */
      if (
        repaymentError
      ) {
        console.error(
          "LOAN_REPAYMENT_RPC_FAILED",
          {
            code:
              repaymentError.code,

            message:
              repaymentError.message,

            details:
              repaymentError.details,

            hint:
              repaymentError.hint,

            reference,
          },
        );


        if (
          repaymentError
            .code ===
            "23505" ||
          repaymentError
            .message ===
            "TRANSACTION_REPLAY" ||
          repaymentError
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
          repaymentError.message ||
            "REPAY_LOAN_FAILED",
        );
      }


      /*
       * ========================================================
       * COMMITTED RESULT
       * ========================================================
       */
      const resultRows =
        resultData as
          LoanRepaymentResult[] |
          null;


      const result =
        resultRows?.[0];


      if (
        !result ||
        result.success !==
          true
      ) {
        throw new AppError(
          "REPAY_LOAN_FAILED",
        );
      }


      /*
       * ========================================================
       * ACTUAL REPAYMENT CONSUMED
       * ========================================================
       *
       * Financial Intelligence must use what was actually
       * consumed by the loan:
       *
       * principal paid + interest paid
       *
       * Example:
       *
       * entered amount   = 120
       * principal paid   = 90
       * interest paid    = 10
       * unused payment   = 20
       *
       * savings outflow  = 100
       *
       * NOT 120.
       */
      const actualRepaymentAmount =
        addAmounts(
          result.principal_paid,
          result.interest_paid,
        );


      /*
       * ========================================================
       * FINANCIAL INTELLIGENCE
       * ========================================================
       *
       * The repayment is already committed.
       *
       * FI failure must never turn the repayment into failed.
       *
       *
       * FI semantics:
       *
       * amount
       *     = actual repayment consumed
       *
       * cashAmount
       *     = actual USD savings/wallet outflow
       *
       * principalAmount
       *     = principal reduction
       *
       * interestAmount
       *     = interest reduction
       */
      try {
        const financialActivity =
          await recordFinancialActivity(
            authSupabase,
            {
              reference:

                reference,


              userId:

                context.user_id,


              countryCode:

                context.country_code,


              currencyCode:

                "usd",


              transactionType:

                "loan_repayment",


              activityType:

                FinancialActivityType
                  .loan_repayment,


              /*
               * Total amount actually applied to the debt.
               */
              amount:

                actualRepaymentAmount,


              amountUsd:

                actualRepaymentAmount,


              /*
               * Exact savings / wallet outflow represented by
               * the amount actually consumed by the repayment.
               */
              cashAmount:

                actualRepaymentAmount,


              cashAmountUsd:

                actualRepaymentAmount,


              /*
               * Principal reduction.
               */
              principalAmount:

                result.principal_paid,


              principalAmountUsd:

                result.principal_paid,


              /*
               * Interest reduction.
               */
              interestAmount:

                result.interest_paid,


              interestAmountUsd:

                result.interest_paid,
            },
          );


        if (
          financialActivity
            .status ===
            "failed"
        ) {
          console.error(
            "LOAN_REPAYMENT_FINANCIAL_INTELLIGENCE_FAILED",
            {
              reference,

              documentNumber:
                result
                  .document_number,

              userId:
                context.user_id,

              repaymentAmount:
                actualRepaymentAmount,

              principalPaid:
                result
                  .principal_paid,

              interestPaid:
                result
                  .interest_paid,

              unusedPayment:
                result
                  .unused_payment,

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
         * exceptions, but nothing after commit may propagate
         * into the successful repayment.
         */
        console.error(
          "LOAN_REPAYMENT_FINANCIAL_INTELLIGENCE_EXCEPTION",
          {
            reference,

            documentNumber:
              result
                .document_number,

            userId:
              context.user_id,

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
       * LOYALTY
       * ========================================================
       *
       * Repayment has already committed.
       *
       * Loyalty therefore remains secondary processing and must
       * never turn a successful repayment into failed.
       */
      let loyalty:
        TransactionLoyaltyResult = {
          points_earned:
            0,

          points_spent:
            0,

          available_points:
            0,

          tier_points:
            0,

          previous_level_code:
            null,

          level_code:
            null,

          level_changed:
            false,
        };


      try {
        const serviceSupabase =
          createSupabaseServiceClient();


        const loyaltyOutcome =
          await awardCompletedTransactionLoyalty(
            serviceSupabase,
            {
              transactionType:

                TransactionType
                  .loan_repayment,


              userId:

                context.user_id,


              /*
               * Keep the transaction/document reference used by
               * the loyalty engine.
               */
              reference:

                result.document_number,


              /*
               * Loyalty currently uses the customer-entered
               * repayment amount as its configured qualifying
               * basis.
               *
               * This remains separate from FI accounting.
               */
              amount:

                repaymentAmount,


              amountUsd:

                repaymentAmount,


              countryCode:

                context.country_code,


              currencyCode:

                "usd",


              metadata: {
                request_reference:

                  reference,


                principal_paid:

                  result
                    .principal_paid,


                interest_paid:

                  result
                    .interest_paid,


                unused_payment:

                  result
                    .unused_payment,


                loans_closed:

                  result
                    .loans_closed,


                amount_basis:

                  "user_entered_repayment_amount",
              },
            },
          );


        if (
          loyaltyOutcome
            .status ===
              "completed" ||
          loyaltyOutcome
            .status ===
              "ignored"
        ) {
          const award =
            loyaltyOutcome
              .result;


          loyalty = {
            points_earned:

              award
                .points_awarded,


            points_spent:

              0,


            available_points:

              award
                .available_points ??
              0,


            tier_points:

              award
                .tier_points ??
              0,


            previous_level_code:

              award
                .previous_level_code ??
              null,


            level_code:

              award
                .level_code ??
              null,


            level_changed:

              award
                .level_changed ??
              false,
          };
        }
      } catch (
        loyaltyError
      ) {
        console.error(
          "LOAN_REPAYMENT_LOYALTY_FAILED",
          {
            reference,

            documentNumber:
              result
                .document_number,

            userId:
              context.user_id,

            error:
              getErrorMessage(
                loyaltyError,
                "LOYALTY_FAILED",
              ),
          },
        );
      }


      /*
       * ========================================================
       * RESPONSE
       * ========================================================
       */
      return successResponse(
        {
          document_number:

            result
              .document_number,


          principal_paid:

            result
              .principal_paid,


          interest_paid:

            result
              .interest_paid,


          collateral_unlocked:

            result
              .collateral_unlocked,


          unused_payment:

            result
              .unused_payment,


          loans_closed:

            result
              .loans_closed,


          loyalty,
        },
      );
    } catch (
      error
    ) {
      console.error(
        "LOAN_REPAYMENT_ERROR",
        {
          error:
            getErrorMessage(
              error,
              "REPAY_LOAN_FAILED",
            ),
        },
      );


      return errorResponse(
        error,
        "REPAY_LOAN_FAILED",
      );
    }
  },
);

