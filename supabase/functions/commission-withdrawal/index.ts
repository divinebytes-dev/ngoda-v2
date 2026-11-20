import { errorResponse, successResponse } from "../../_shared/api-response.ts";
import { AppError } from "../../_shared/app-error.ts";
import type { Json } from "../../_shared/database.types.ts";
import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";
import {
  type SenderApproval,
  type TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError("METHOD_NOT_ALLOWED", 405);
    }

    let body: {
      transaction?: TransactionData;
      approval?: SenderApproval;
    } | null;
    try {
      body = await request.json();
    } catch {
      throw new AppError("INVALID_REQUEST_BODY", 400);
    }

    const transaction = body?.transaction;
    const approval = body?.approval;
    if (
      transaction?.v !== "v10" ||
      approval?.v !== transaction.v ||
      typeof transaction.s !== "string" ||
      !transaction.s ||
      transaction.r !== approval.r ||
      transaction.c !== approval.c ||
      String(transaction.a) !== String(approval.a)
    ) {
      throw new AppError("INVALID_COMMISSION_WITHDRAWAL", 400);
    }

    if (
      !Number.isSafeInteger(transaction.a) || transaction.a <= 0 ||
      !Number.isSafeInteger(transaction.f) || transaction.f < 0 ||
      !Number.isSafeInteger(transaction.g) || transaction.g < 0
    ) {
      throw new AppError("INVALID_COMMISSION_WITHDRAWAL_AMOUNTS", 400);
    }

    const authSupabase = createSupabaseClient(request);
    const { data: contexts, error: contextError } = await authSupabase.rpc(
      "fetch_my_commission_withdrawal_context",
      { p_user_id: transaction.s },
    );
    if (contextError) {
      console.error("COMMISSION_WITHDRAWAL_CONTEXT_FAILED", contextError);
      throw new AppError("COMMISSION_WITHDRAWAL_CONTEXT_FAILED");
    }

    const context = contexts?.[0];
    if (!context || approval.b !== context.clerk_id) {
      throw new AppError("COMMISSION_WITHDRAWAL_NOT_AUTHORIZED", 403);
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
      context.user_wallet_address,
    )) {
      throw new AppError("USER_SIGNATURE_VERIFICATION_FAILED", 403);
    }

    if (!TransactionVerificationService.verifySenderSignature(
      approval,
      context.clerk_wallet_address,
    )) {
      throw new AppError("CLERK_SIGNATURE_VERIFICATION_FAILED", 403);
    }

    const ipAddress = request.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim() || request.headers.get("x-real-ip")?.trim() || "unknown";
    const postingSupabase = createSupabaseServiceClient();
    const { data, error: postingError } = await postingSupabase.rpc(
      "commission_withdrawal",
      {
        p_clerk_id: context.clerk_id,
        p_verified_clerk_address: context.clerk_wallet_address,
        p_verified_user_address: context.user_wallet_address,
        p_transaction: transaction as unknown as Json,
        p_approval: approval as unknown as Json,
        p_ip_address: ipAddress,
      },
    );

    if (postingError) {
      console.error("COMMISSION_WITHDRAWAL_POSTING_FAILED", postingError);
      switch (postingError.code) {
        case "23505":
          if (postingError.message === "TRANSACTION_REPLAY") {
            throw new AppError("TRANSACTION_REPLAY", 409);
          }
          break;
        case "42501":
          throw new AppError("COMMISSION_WITHDRAWAL_NOT_AUTHORIZED", 403);
        case "22023":
          throw new AppError(postingError.message, 400);
      }

      if (postingError.message === "INSUFFICIENT_BALANCE") {
        throw new AppError("INSUFFICIENT_BALANCE", 400);
      }
      throw new AppError("COMMISSION_WITHDRAWAL_FAILED");
    }

    if (!data || typeof data !== "object" || !("success" in data) ||
      data.success !== true) {
      throw new AppError("COMMISSION_WITHDRAWAL_RESULT_NOT_FOUND");
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(error, "COMMISSION_WITHDRAWAL_FAILED");
  }
});
