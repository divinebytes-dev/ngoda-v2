import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  getTotalSupply,
} from "../../_shared/blockchain/balances.ts";

type TokenAdjustmentRecord = {
  id: string;
  document_number: string;
  adjustment_type: string;
  quantity: string | number;
  uom: string;
  status: string;
  description: string | null;
  available_gold: string | number;
};

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "Content-Type": "application/json",
      },
    },
  );
}

function successResponse(
  data: unknown,
): Response {
  return jsonResponse({
    success: true,
    data,
  });
}

function errorResponse(
  error: string,
  status = 400,
): Response {
  return jsonResponse(
    {
      success: false,
      error,
    },
    status,
  );
}

function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }

  return String(error);
}

async function getTokenAdjustmentsByStatus(
  request: Request,
  status: string,
): Promise<Array<Record<string, unknown>>> {
  const supabase =
    createSupabaseClient(request);

  /*
   * Blockchain supply and database adjustments are
   * independent and can be fetched concurrently.
   */
  const [
    adjustmentResult,
    tokenSupply,
  ] = await Promise.all([
    supabase.rpc(
      "fetch_token_adjustments_by_status",
      {
        p_status: status,
      },
    ),

    getTotalSupply(),
  ]);

  if (adjustmentResult.error) {
    console.error(
      "TOKEN_ADJUSTMENTS_RPC_FAILED",
      {
        code:
          adjustmentResult.error.code,

        message:
          adjustmentResult.error.message,

        details:
          adjustmentResult.error.details,

        hint:
          adjustmentResult.error.hint,

        status,
      },
    );

    throw new Error(
      adjustmentResult.error.message,
    );
  }

  const adjustments =
    (
      adjustmentResult.data ??
      []
    ) as TokenAdjustmentRecord[];

  const totalTokens =
    tokenSupply.token_balance;

  return adjustments.map(
    (adjustment) => ({
      ...adjustment,

      quantity:
        adjustment.quantity.toString(),

      available_gold:
        adjustment.available_gold.toString(),

      total_tokens:
        totalTokens.toString(),
    }),
  );
}

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {

    if (request.method !== "GET") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    try {
      const url =
        new URL(request.url);

      const status =
        url.searchParams
          .get("status")
          ?.trim()
          .toLowerCase();

      if (!status) {
        return errorResponse(
          "STATUS_IS_REQUIRED",
        );
      }

      const adjustments =
        await getTokenAdjustmentsByStatus(
          request,
          status,
        );

      console.log(
        "TOKEN_ADJUSTMENTS_FETCHED",
        {
          status,
          count:
            adjustments.length,
        },
      );

      return successResponse(
        adjustments,
      );
    } catch (error) {
      const message =
        getErrorMessage(error);

      console.error(
        "TOKEN_ADJUSTMENTS_ERROR",
        {
          error: message,
        },
      );

      if (
        message === "UNAUTHENTICATED" ||
        message === "FORBIDDEN"
      ) {
        return errorResponse(
          message,
          403,
        );
      }

      return errorResponse(
        message ||
          "FAILED_TO_FETCH_ADJUSTMENTS",
        400,
      );
    }
  },
);