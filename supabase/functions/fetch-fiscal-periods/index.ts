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

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "GET") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    const supabase = createSupabaseClient(req);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_fiscal_periods",
    );

    if (error) {
      console.error(
        "FETCH_FISCAL_PERIODS_RPC_FAILED:",
        error,
      );

      throw new AppError(
        error.message,
        400,
      );
    }

    if (!data) {
      throw new AppError(
        "FISCAL_PERIODS_NOT_FOUND",
        404,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "FETCH_FISCAL_PERIODS_FAILED:",
      error,
    );

    if (error instanceof AppError) {
      return errorResponse(
        error.message,
      );
    }

    return errorResponse(
      "FETCH_FISCAL_PERIODS_FAILED",
    );
  }
});