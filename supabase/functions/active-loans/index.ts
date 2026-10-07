// supabase/functions/active-loans/index.ts

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


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const rpcClient =
      authSupabase as unknown as
        UntypedRpcClient;

    /*
     * PostgreSQL derives the customer from auth.uid() and
     * validates the customer role and active status.
     */
    const {
      data,
      error: rpcError,
    } = await rpcClient.rpc(
      "fetch_my_active_loans",
    );

    if (rpcError) {
      console.error(
        "FETCH_ACTIVE_LOANS_RPC_FAILED",
        {
          code:
            rpcError.code,

          message:
            rpcError.message,

          details:
            rpcError.details,

          hint:
            rpcError.hint,
        },
      );

      throw new AppError(
        rpcError.message ||
          "FETCH_ACTIVE_LOANS_FAILED",
      );
    }

    /*
     * The database always returns an array. Preserve an empty
     * array when the customer has no active loans.
     */
    return successResponse(
      data ?? [],
    );
  } catch (error) {
    console.error(
      "FETCH_ACTIVE_LOANS_ERROR",
      {
        error:
          getErrorMessage(
            error,
            "FETCH_ACTIVE_LOANS_FAILED",
          ),
      },
    );

    return errorResponse(
      error,
      "FETCH_ACTIVE_LOANS_FAILED",
    );
  }
});