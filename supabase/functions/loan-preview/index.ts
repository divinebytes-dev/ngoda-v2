// supabase/functions/loan-preview/index.ts

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


type LoanPreviewContext = {
  wallet_address: string;
  country_code: string;
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


type LoanPreviewRequest = {
  required_amount?:
    | string
    | number;
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

  if (typeof error === "string") {
    return error;
  }

  return fallback;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const rpcClient =
      authSupabase as unknown as
        UntypedRpcClient;

    let body: LoanPreviewRequest;

    try {
      body = await request.json();
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
      requiredAmount === null ||
      String(requiredAmount)
          .trim() === ""
    ) {
      throw new AppError(
        "MISSING_REQUIRED_FIELDS",
      );
    }

    /*
     * Fetch the authenticated user's trusted wallet context.
     *
     * The database checks:
     * - authentication
     * - the required user role
     * - active user status
     * - wallet configuration
     * - country configuration
     */
    const {
      data: contextData,
      error: contextError,
    } = await rpcClient.rpc(
      "fetch_my_loan_preview_context",
    );

    if (contextError) {
      console.error(
        "LOAN_PREVIEW_CONTEXT_FAILED",
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
          "LOAN_PREVIEW_CONTEXT_FAILED",
      );
    }

    const contextRows =
      contextData as
        LoanPreviewContext[] | null;

    const context =
      contextRows?.[0];

    if (!context) {
      throw new AppError(
        "LOAN_PREVIEW_CONTEXT_NOT_FOUND",
      );
    }

    if (!context.wallet_address) {
      throw new AppError(
        "USER_WALLET_NOT_CONFIGURED",
      );
    }

    if (!context.country_code) {
      throw new AppError(
        "USER_COUNTRY_NOT_CONFIGURED",
      );
    }

    /*
     * Fetch the user's current on-chain Gold balance.
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

    /*
     * PostgreSQL performs all loan calculations using numeric
     * values. Passing the amount as text avoids JavaScript
     * floating-point conversion.
     */
    const {
      data: previewData,
      error: previewError,
    } = await rpcClient.rpc(
      "preview_my_loan",
      {
        p_requested_amount:
          String(requiredAmount),

        p_token_balance:
          blockchainBalances
            .token_balance,

        p_currency_code:
          "usd",
      },
    );

    if (previewError) {
      console.error(
        "LOAN_PREVIEW_RPC_FAILED",
        {
          code:
            previewError.code,

          message:
            previewError.message,

          details:
            previewError.details,

          hint:
            previewError.hint,

          walletAddress:
            context.wallet_address,

          countryCode:
            context.country_code,
        },
      );

      throw new AppError(
        previewError.message ||
          "LOAN_PREVIEW_FAILED",
      );
    }

    if (!previewData) {
      throw new AppError(
        "LOAN_PREVIEW_NOT_FOUND",
      );
    }

    return successResponse(
      previewData,
    );
  } catch (error) {
    console.error(
      "LOAN_PREVIEW_ERROR",
      {
        error:
          getErrorMessage(
            error,
            "LOAN_PREVIEW_FAILED",
          ),
      },
    );

    return errorResponse(
      error,
      "LOAN_PREVIEW_FAILED",
    );
  }
});