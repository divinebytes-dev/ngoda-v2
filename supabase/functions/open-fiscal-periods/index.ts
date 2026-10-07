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
    if (req.method !== "POST") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    const supabase = createSupabaseClient(req);

    const {
      data,
      error,
    } = await supabase.rpc(
      "open_my_next_fiscal_year",
    );

    if (error) {
      console.error(
        "OPEN_FISCAL_YEAR_RPC_FAILED:",
        error,
      );

      throw new AppError(
        error.message,
        400,
      );
    }

    if (!data) {
      throw new AppError(
        "INVALID_OPEN_FISCAL_YEAR_RESPONSE",
        500,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "OPEN_FISCAL_YEAR_FAILED:",
      error,
    );

    if (error instanceof AppError) {
      return errorResponse(
        error.message,
      );
    }

    return errorResponse(
      "OPEN_FISCAL_YEAR_FAILED",
    );
  }
});