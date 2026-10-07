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

function extractGoldPrice(
  data: unknown,
): string {
  if (
    typeof data === "string" ||
    typeof data === "number"
  ) {
    return String(data);
  }

  if (
    Array.isArray(data) &&
    data.length > 0
  ) {
    const first =
      data[0];

    if (
      typeof first === "string" ||
      typeof first === "number"
    ) {
      return String(first);
    }

    if (
      first !== null &&
      typeof first === "object"
    ) {
      const values =
        Object.values(first);

      const value =
        values[0];

      if (
        typeof value === "string" ||
        typeof value === "number"
      ) {
        return String(value);
      }
    }
  }

  throw new AppError(
    "INVALID_GOLD_PRICE_RESPONSE",
  );
}

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

      /*
       * Cast temporarily in case the generated types
       * do not yet contain the new wrapper function.
       */
      const rpcClient =
        supabase as unknown as RpcClient;

      const {
        data,
        error,
      } = await rpcClient.rpc(
        "fetch_public_gold_price",
      );

      if (error) {
        console.error(
          "Gold-price RPC failed",
          {
            code: error.code,
            message: error.message,
            details: error.details,
            hint: error.hint,
          },
        );

        throw new AppError(
          error.message ||
            "FAILED_TO_FETCH_GOLD_PRICE",
        );
      }

      const pricePerGram =
        extractGoldPrice(
          data,
        );

      console.log(
        "Gold price:",
        pricePerGram,
      );

      return successResponse(
        pricePerGram,
      );
    } catch (error) {
      console.error(
        "Gold price fetch error",
        {
          message:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );

      return errorResponse(
        error,
        "FAILED_TO_FETCH_GOLD_PRICE",
      );
    }
  },
);