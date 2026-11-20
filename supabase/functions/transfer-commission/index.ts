import { errorResponse, successResponse } from "../../_shared/api-response.ts";
import { AppError } from "../../_shared/app-error.ts";
import type { Json } from "../../_shared/database.types.ts";
import type { TransactionType } from "../../_shared/enums.ts";
import { recordFinancialActivity } from "../../_shared/financial-intelligence/record-financial-activity.ts";
import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";
import {
  type TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";
import { FinancialActivityType } from "../../_shared/types/financial-activity-type.ts";

type CommissionTransferResult = {
  success: true;
  reference: string;
  currency: string;
  amount: string;
  amount_usd: string;
  fee: string;
  financial_transaction_id: string;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError("METHOD_NOT_ALLOWED", 405);
    }

    let body: { transaction?: TransactionData } | null;
    try {
      body = await request.json();
    } catch {
      throw new AppError("INVALID_REQUEST_BODY", 400);
    }

    const transaction = body?.transaction;
    if (!transaction || transaction.v !== "v9") {
      throw new AppError("INVALID_COMMISSION_TRANSFER", 400);
    }

    const authSupabase = createSupabaseClient(request);
    const { data: contexts, error: contextError } = await authSupabase.rpc(
      "fetch_my_commission_transfer_context",
    );

    if (contextError) {
      console.error("COMMISSION_TRANSFER_CONTEXT_FAILED", contextError);
      throw new AppError("COMMISSION_TRANSFER_CONTEXT_FAILED");
    }

    const context = contexts?.[0];
    if (!context) {
      throw new AppError("COMMISSION_TRANSFER_NOT_AUTHORIZED", 403);
    }

    if (transaction.s !== context.sender_id) {
      throw new AppError("COMMISSION_TRANSFER_PARTICIPANT_MISMATCH", 400);
    }

    const versionTime = Number(context.version_time);
    if (!Number.isFinite(versionTime) || versionTime <= 0) {
      throw new AppError("INVALID_TRANSACTION_VERSION_TIME");
    }

    TransactionVerificationService.validateTransactionFields(transaction);
    TransactionVerificationService.validateTransactionTimestamp(
      transaction,
      versionTime,
    );

    if (!TransactionVerificationService.verifyTransactionSignature(
      transaction,
      context.wallet_address,
    )) {
      throw new AppError("USER_SIGNATURE_VERIFICATION_FAILED", 403);
    }

    const ipAddress = request.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim() || request.headers.get("x-real-ip")?.trim() || "unknown";

    const postingSupabase = createSupabaseServiceClient();
    const { data, error: postingError } = await postingSupabase.rpc(
      "commission_transfer",
      {
        p_sender_id: context.sender_id,
        p_verified_wallet_address: context.wallet_address,
        p_transaction: transaction as unknown as Json,
        p_ip_address: ipAddress,
      },
    );

    if (postingError) {
      console.error("COMMISSION_TRANSFER_POSTING_FAILED", postingError);
      if (postingError.code === "23505" &&
        postingError.message === "TRANSACTION_REPLAY") {
        throw new AppError("TRANSACTION_REPLAY", 409);
      }
      if (postingError.code === "42501") {
        throw new AppError("COMMISSION_TRANSFER_NOT_AUTHORIZED", 403);
      }
      throw new AppError(postingError.message || "COMMISSION_TRANSFER_FAILED");
    }

    const result = data as CommissionTransferResult | null;
    if (!result?.success) {
      throw new AppError("COMMISSION_TRANSFER_RESULT_NOT_FOUND");
    }

    // Record the personal-wallet inflow once. The transaction type lets
    // reports distinguish it from ordinary deposits.
    try {
      const activity = await recordFinancialActivity(postingSupabase, {
        reference: result.reference,
        userId: context.sender_id,
        countryCode: context.country_code,
        currencyCode: result.currency,
        transactionType: "commission_transfer" as TransactionType,
        activityType: FinancialActivityType.deposit,
        amount: result.amount,
        amountUsd: result.amount_usd,
        cashAmount: result.amount,
        cashAmountUsd: result.amount_usd,
      });

      if (activity.status === "failed") {
        console.error("COMMISSION_TRANSFER_ACTIVITY_FAILED", {
          reference: result.reference,
          error: activity.error,
        });
      }
    } catch (error) {
      console.error("COMMISSION_TRANSFER_ACTIVITY_FAILED", {
        reference: result.reference,
        error,
      });
    }

    return successResponse(result);
  } catch (error) {
    return errorResponse(error, "COMMISSION_TRANSFER_FAILED");
  }
});
