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

    const supabase = createSupabaseClient(request);
    const { data, error } = await supabase.rpc("get_my_tax_payable_summary");

    if (error) {
      if (error.code === "42501") {
        throw new AppError("RESERVE_BANK_TAX_NOT_AUTHORIZED", 403);
      }

      console.error("TAX_PAYABLE_SUMMARY_RPC_FAILED", {
        code: error.code,
        message: error.message,
      });
      throw new AppError("TAX_PAYABLE_SUMMARY_FAILED");
    }

    if (!data) {
      throw new AppError("TAX_PAYABLE_SUMMARY_NOT_FOUND");
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(error, "TAX_PAYABLE_SUMMARY_FAILED");
  }
});