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
  message?: string;
  details?: string | null;
  hint?: string | null;
};

type RpcResult = {
  data: unknown;
  error: RpcError | null;
};

type RpcClient = {
  rpc: (
    functionName: string,
    args?: Record<string, unknown>,
  ) => Promise<RpcResult>;
};

type ExpressTapLimit = {
  currency_code: string;
  express_tap_limit: string | number;
  is_active: boolean;
};


Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    try {
      if (
        request.method !== "POST"
      ) {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
        );
      }

      const supabase =
        createSupabaseClient(
          request,
        );

      const rpcClient =
        supabase as unknown as RpcClient;

      const {
        data,
        error,
      } = await rpcClient.rpc(
        "fetch_my_express_tap_limits",
      );

      if (error) {
        console.error(
          "Express Tap limits RPC failed",
          {
            code: error.code,
            message: error.message,
            details: error.details,
            hint: error.hint,
          },
        );

        throw new AppError(
          error.message ||
            "EXPRESS_TAP_LIMITS_FETCH_FAILED",
        );
      }

      const limits =
        Array.isArray(data)
          ? data as ExpressTapLimit[]
          : [];

      return successResponse(
        limits,
      );
    } catch (error) {
      console.error(
        "Express Tap limits error",
        {
          message:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );

      return errorResponse(
        error,
        "EXPRESS_TAP_LIMITS_FETCH_FAILED",
      );
    }
  },
);