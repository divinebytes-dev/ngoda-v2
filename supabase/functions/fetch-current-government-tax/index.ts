// supabase/functions/fetch-current-government-tax/index.ts
import { errorResponse, successResponse } from "../../_shared/api-response.ts";
import { createSupabaseClient } from "../../_shared/supabase-client.ts";
import { AppError } from "../../_shared/app-error.ts";

function positiveInteger(value: unknown, fallback: number, max: number): number {
  if (value === undefined) return fallback;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new AppError("INVALID_PAGINATION", 400);
  }
  return value;
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    if (request.method !== "POST") throw new AppError("METHOD_NOT_ALLOWED", 405);
    const text = await request.text();
    let body: Record<string, unknown> = {};
    try {
      const parsed: unknown = text.trim() ? JSON.parse(text) : {};
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      body = parsed as Record<string, unknown>;
    } catch {
      throw new AppError("INVALID_REQUEST_BODY", 400);
    }
    let currency: string | null = null;
    if (body.currency_code != null) {
      if (typeof body.currency_code !== "string" || !body.currency_code.trim()) {
        throw new AppError("INVALID_CURRENCY_CODE", 400);
      }
      currency = body.currency_code.trim().toLowerCase();
    }
    let asOf: string | null = null;
    if (body.as_of != null) {
      if (typeof body.as_of !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/i.test(body.as_of) ||
        !Number.isFinite(Date.parse(body.as_of))) {
        throw new AppError("INVALID_AS_OF", 400);
      }
      asOf = body.as_of;
    }
    const supabase = createSupabaseClient(request);
    const { data, error } = await supabase.rpc("fetch_my_current_government_tax", {
      p_currency_code: currency,
      p_page: positiveInteger(body.page, 1, 2147483647),
      p_page_size: positiveInteger(body.page_size, 50, 100),
      p_as_of: asOf,
    });
    if (error) {
      console.error("FETCH_CURRENT_GOVERNMENT_TAX_RPC_FAILED", error);
      throw new AppError(error.message || "FAILED_TO_FETCH_CURRENT_GOVERNMENT_TAX",
        error.code === "42501" ? (error.message === "UNAUTHORIZED" ? 401 : 403) : 400);
    }
    if (data == null) throw new AppError("CURRENT_GOVERNMENT_TAX_RESULT_NOT_FOUND", 500);
    return successResponse(data);
  } catch (error) {
    console.error("FETCH_CURRENT_GOVERNMENT_TAX_ERROR", error);
    return errorResponse(error, "FAILED_TO_FETCH_CURRENT_GOVERNMENT_TAX");
  }
});
