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
  errorMessage: string,
  maximum?: number,
): number {
  if (value === null || value.trim() === "") {
    return defaultValue;
  }

  const normalized = value.trim();

  if (!/^\d+$/.test(normalized)) {
    throw new AppError(errorMessage, 400);
  }

  const parsed = Number(normalized);

  if (
    !Number.isSafeInteger(parsed) ||
    parsed < 1 ||
    (maximum !== undefined && parsed > maximum)
  ) {
    throw new AppError(errorMessage, 400);
  }

  return parsed;
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    if (request.method !== "GET") {
      throw new AppError("METHOD_NOT_ALLOWED", 405);
    }

    const url = new URL(request.url);

    const page = parsePositiveInteger(
      url.searchParams.get("page"),
      1,
      "INVALID_PAGE",
    );

    const pageSize = parsePositiveInteger(
      url.searchParams.get("pageSize") ??
        url.searchParams.get("page_size"),
      50,
      "INVALID_PAGE_SIZE",
      100,
    );

    const supabase = createSupabaseClient(request);

    const { data, error } = await supabase.rpc(
      "fetch_incomplete_blockchain_transactions",
      {
        p_page: page,
        p_page_size: pageSize,
      },
    );

    if (error) {
      console.error(
        "FETCH_INCOMPLETE_BLOCKCHAIN_TRANSACTIONS_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          page,
          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_INCOMPLETE_BLOCKCHAIN_TRANSACTIONS_FAILED",
      );
    }



    return successResponse(
      data ?? {
        transactions: [],
        pagination: {
          page,
          page_size: pageSize,
          total_entries: 0,
          total_pages: 1,
          has_previous: page > 1,
          has_next: false,
        },
      },
    );
  } catch (error) {
    console.error(
      "FETCH_INCOMPLETE_BLOCKCHAIN_TRANSACTIONS_ERROR",
      error,
    );

    return errorResponse(
      error,
      "FETCH_INCOMPLETE_BLOCKCHAIN_TRANSACTIONS_FAILED",
    );
  }
});