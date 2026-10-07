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


function parsePositiveInteger(
  value: string | null,
  defaultValue: number,
  errorCode: string,
): number {
  if (value === null || value.trim() === "") {
    return defaultValue;
  }

  if (!/^[0-9]+$/.test(value.trim())) {
    throw new AppError(errorCode);
  }

  const result = Number(value);

  if (
    !Number.isSafeInteger(result) ||
    result < 1
  ) {
    throw new AppError(errorCode);
  }

  return result;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url = new URL(request.url);

    const merchantId =
      url.searchParams
        .get("merchantId")
        ?.trim();

    const currencyCode =
      url.searchParams
        .get("currency")
        ?.trim()
        .toLowerCase();

    if (!merchantId) {
      throw new AppError(
        "MERCHANT_ID_REQUIRED",
      );
    }

    if (!currencyCode) {
      throw new AppError(
        "CURRENCY_REQUIRED",
      );
    }

    if (currencyCode === "gold") {
      throw new AppError(
        "INVALID_CREDIT_AGENT_CURRENCY",
      );
    }

    const page = parsePositiveInteger(
      url.searchParams.get("page"),
      1,
      "INVALID_PAGE",
    );

    const pageSize = parsePositiveInteger(
      url.searchParams.get("pageSize"),
      50,
      "INVALID_PAGE_SIZE",
    );

    if (pageSize > 100) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
      );
    }

    /*
     * Use the authenticated client so PostgreSQL can
     * enforce the Accounts role and country boundary.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_credit_agent_drilldown",
      {
        p_merchant_id:
          merchantId,

        p_currency_code:
          currencyCode,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "CREDIT_AGENT_DRILLDOWN_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          merchantId,

          currencyCode,

          page,

          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_CREDIT_AGENT_DRILLDOWN",
      );
    }

    if (
      data === null ||
      data === undefined
    ) {
      throw new AppError(
        "CREDIT_AGENT_DRILLDOWN_RESULT_NOT_FOUND",
      );
    }

    /*
     * Return the multi-currency account drilldown result
     * unchanged.
     */
    return successResponse(data);
  } catch (error) {
    return errorResponse(
      error,
      "FAILED_TO_FETCH_CREDIT_AGENT_DRILLDOWN",
    );
  }
});