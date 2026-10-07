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

type CloseFiscalYearBody = {
  fiscal_year?: unknown;
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    const body =
      await req.json() as CloseFiscalYearBody;

    if (
      typeof body.fiscal_year !== "number" ||
      !Number.isInteger(body.fiscal_year) ||
      body.fiscal_year <= 0
    ) {
      throw new AppError(
        "INVALID_FISCAL_YEAR",
        400,
      );
    }

    const supabase =
      createSupabaseClient(req);

    const {
      data,
      error,
    } = await supabase.rpc(
      "close_my_fiscal_year",
      {
        p_fiscal_year: body.fiscal_year,
      },
    );

    if (error) {
      console.error(
        "CLOSE_FISCAL_YEAR_RPC_FAILED:",
        error,
      );

      throw new AppError(
        error.message,
        400,
      );
    }

    if (!data) {
      throw new AppError(
        "INVALID_CLOSE_FISCAL_YEAR_RESPONSE",
        500,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "CLOSE_FISCAL_YEAR_FAILED:",
      error,
    );

    if (error instanceof AppError) {
      return errorResponse(
        error.message,
      );
    }

    return errorResponse(
      "CLOSE_FISCAL_YEAR_FAILED",
    );
  }
});