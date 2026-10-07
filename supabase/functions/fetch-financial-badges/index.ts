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


type FinancialBadge = {
  id: string;
  code: string;
  behavior: string;
  metric: string;
  level: number;
  threshold_usd: number;
  name: string;
  description: string | null;

  earned: boolean;

  achieved_value_usd:
    number | null;

  fiscal_year:
    number | null;

  period:
    number | null;

  achieved_at:
    string | null;
};


type FinancialBadgesResult = {
  badges: FinancialBadge[];
};


Deno.serve(async (request: Request) => {
  try {
    /*
     * Financial badges are read-only.
     */
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    /*
     * Authenticated client.
     *
     * get_my_financial_badges() derives the
     * current user from auth.uid().
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "get_my_financial_badges",
    );

    if (error) {
      console.error(
        "FINANCIAL_BADGES_FETCH_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FINANCIAL_BADGES_FETCH_FAILED",
      );
    }

    if (!data) {
      return successResponse({
        badges: [],
      } satisfies FinancialBadgesResult);
    }

    const result =
      data as FinancialBadgesResult;

    return successResponse({
      badges:
        result.badges ?? [],
    });
  } catch (error) {
    return errorResponse(
      error,
      "FINANCIAL_BADGES_FETCH_FAILED",
    );
  }
});