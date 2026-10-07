// supabase/functions/loan-detail/index.ts

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


type LoanDetailRequest = {
  loan_id?: string;
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

  if (typeof error === "string") {
    return error;
  }

  return fallback;
}


async function getLoanId(
  request: Request,
): Promise<string | null> {
  if (request.method === "GET") {
    const url =
      new URL(request.url);

    return (
      url.searchParams
        .get("loan_id")
        ?.trim() ??
      null
    );
  }

  let body: LoanDetailRequest;

  try {
    body = await request.json();
  } catch {
    throw new AppError(
      "INVALID_REQUEST_BODY",
    );
  }

  return (
    body.loan_id?.trim() ??
    null
  );
}


Deno.serve(async (request: Request) => {
  try {
    /*
     * Supabase functions.invoke() uses POST.
     * GET remains available for direct HTTP calls.
     */
    if (
      request.method !== "GET" &&
      request.method !== "POST"
    ) {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const loanId =
      await getLoanId(request);

    if (!loanId) {
      throw new AppError(
        "LOAN_ID_UNDEFINED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const rpcClient =
      authSupabase as unknown as
        UntypedRpcClient;

    /*
     * PostgreSQL validates that:
     * - the caller is an authenticated customer
     * - the loan is active
     * - the loan belongs to the caller
     */
    const {
      data,
      error: rpcError,
    } = await rpcClient.rpc(
      "fetch_my_active_loan_detail",
      {
        p_loan_id:
          loanId,
      },
    );

    if (rpcError) {
      console.error(
        "FETCH_LOAN_DETAIL_RPC_FAILED",
        {
          code:
            rpcError.code,

          message:
            rpcError.message,

          details:
            rpcError.details,

          hint:
            rpcError.hint,

          loanId,
        },
      );

      throw new AppError(
        rpcError.message ||
          "FETCH_LOAN_DRILLDOWN_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "ACTIVE_LOAN_NOT_FOUND",
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "FETCH_LOAN_DETAIL_ERROR",
      {
        error:
          getErrorMessage(
            error,
            "FETCH_LOAN_DRILLDOWN_FAILED",
          ),
      },
    );

    return errorResponse(
      error,
      "FETCH_LOAN_DRILLDOWN_FAILED",
    );
  }
});