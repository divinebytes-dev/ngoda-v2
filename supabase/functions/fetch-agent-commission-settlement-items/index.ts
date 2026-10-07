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
  if (
    value === null ||
    value.trim() === ""
  ) {
    return defaultValue;
  }

  if (
    !/^\d+$/.test(
      value.trim(),
    )
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const parsedValue =
    Number(value);

  if (
    !Number.isSafeInteger(
      parsedValue,
    ) ||
    parsedValue < 1 ||
    (
      maximum !== undefined &&
      parsedValue > maximum
    )
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return parsedValue;
}


Deno.serve(async (request: Request) => {
  try {
    /*
     * This log confirms that the request reached the
     * Edge Function.
     */
    console.log(
      "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_REQUEST",
      {
        method:
          request.method,

        url:
          request.url,
      },
    );

    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url =
      new URL(request.url);

    const batchId =
      (
        url.searchParams.get(
          "batchId",
        ) ??
        url.searchParams.get(
          "batch_id",
        )
      )?.trim();

    if (!batchId) {
      throw new AppError(
        "SETTLEMENT_BATCH_ID_REQUIRED",
        400,
      );
    }

    const page =
      parsePositiveInteger(
        url.searchParams.get(
          "page",
        ),
        1,
        "INVALID_PAGE",
      );

    const pageSize =
      parsePositiveInteger(
        url.searchParams.get(
          "pageSize",
        ) ??
          url.searchParams.get(
            "page_size",
          ),
        50,
        "INVALID_PAGE_SIZE",
        100,
      );

    console.log(
      "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_PARAMETERS",
      {
        batchId,
        page,
        pageSize,
      },
    );

    const supabase =
      createSupabaseClient(
        request,
      );

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_agent_commission_settlement_items",
      {
        p_batch_id:
          batchId,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          batchId,
          page,
          pageSize,
        },
      );

      if (
        error.message.includes(
          "AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND",
        )
      ) {
        throw new AppError(
          "AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND",
          404,
        );
      }

      throw new AppError(
        error.message ||
          "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_FAILED",
      );
    }

    const result =
      data ?? {
        totalAgents:
          0,

        currency:
          "",

        totalAmount:
          "0",

        items:
          [],

        pagination: {
          page,

          page_size:
            pageSize,

          total_entries:
            0,

          total_pages:
            1,

          has_previous:
            page > 1,

          has_next:
            false,
        },
      };

    return successResponse(
      result,
    );
  } catch (error) {
    console.error(
      "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_AGENT_COMMISSION_SETTLEMENT_ITEMS_FAILED",
    );
  }
});