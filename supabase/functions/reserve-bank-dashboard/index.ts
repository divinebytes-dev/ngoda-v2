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
    const { data, error } = await supabase.rpc("get_my_reserve_bank_dashboard");

    if (error) {
      if (error.code === "42501") {
        throw new AppError("RESERVE_BANK_TAX_NOT_AUTHORIZED", 403);
      }

      console.error("RESERVE_BANK_DASHBOARD_RPC_FAILED", {
        code: error.code,
        message: error.message,
      });
      throw new AppError("RESERVE_BANK_DASHBOARD_FAILED");
    }

    if (!data) {
      throw new AppError("RESERVE_BANK_DASHBOARD_NOT_FOUND");
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(error, "RESERVE_BANK_DASHBOARD_FAILED");
  }
});
