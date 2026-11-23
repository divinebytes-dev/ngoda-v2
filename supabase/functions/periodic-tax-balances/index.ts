import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";
import { AppError } from "../../_shared/app-error.ts";
import { createSupabaseClient } from "../../_shared/supabase-client.ts";

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError("METHOD_NOT_ALLOWED", 405);
    }

    const currency = new URL(request.url).searchParams
      .get("currency")?.trim().toLowerCase();

    if (!currency) {
      throw new AppError("CURRENCY_IS_REQUIRED", 400);
    }

    const supabase = createSupabaseClient(request);
    const { data, error } = await supabase.rpc("get_my_tax_payable_periods", {
      p_currency: currency,
    });

    if (error) {
      if (error.code === "42501") {
        throw new AppError("RESERVE_BANK_TAX_NOT_AUTHORIZED", 403);
      }

      if (error.code === "22023") {
        throw new AppError("CURRENCY_IS_REQUIRED", 400);
      }

      console.error("TAX_PAYABLE_PERIODS_RPC_FAILED", {
        code: error.code,
        message: error.message,
      });
      throw new AppError("TAX_PAYABLE_PERIODS_FAILED");
    }

    if (!data) {
      throw new AppError("TAX_PAYABLE_PERIODS_NOT_FOUND");
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(error, "TAX_PAYABLE_PERIODS_FAILED");
  }
});