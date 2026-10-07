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

import type {
  Database,
} from "../../_shared/database.types.ts";


type SettlementStatus =
  Database["public"]["Enums"]["SettlementStatus"];


const FUNCTION_NAME =
  "fetch-agent-commission-settlement-batch";


function readStatus(
  request: Request,
): string | null {
  const url =
    new URL(request.url);

  /*
   * Preferred format:
   *
   * ?status=pending
   */
  const queryStatus =
    url.searchParams
      .get("status")
      ?.trim()
      .toLowerCase();

  if (queryStatus) {
    return queryStatus;
  }

  /*
   * Also support:
   *
   * /fetch-agent-commission-settlement-batch/pending
   */
  const segments =
    url.pathname
      .split("/")
      .filter(Boolean);

  const functionIndex =
    segments.lastIndexOf(
      FUNCTION_NAME,
    );

  if (
    functionIndex >= 0 &&
    segments.length >
      functionIndex + 1
  ) {
    const pathStatus =
      decodeURIComponent(
        segments[functionIndex + 1],
      )
        .trim()
        .toLowerCase();

    return pathStatus || null;
  }

  return null;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const rawStatus =
      readStatus(request);

    if (!rawStatus) {
      throw new AppError(
        "SETTLEMENT_STATUS_REQUIRED",
        400,
      );
    }

    /*
     * SettlementStatus is a generated TypeScript type.
     * PostgreSQL performs runtime enum validation.
     */
    const settlementStatus =
      rawStatus as SettlementStatus;

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_agent_commission_settlement_batches",
      {
        p_status:
          settlementStatus,
      },
    );

    if (error) {
      console.error(
        "FETCH_AGENT_COMMISSION_SETTLEMENT_BATCHES_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          status:
            rawStatus,
        },
      );

      if (error.code === "22P02") {
        throw new AppError(
          "INVALID_STATUS",
          400,
        );
      }

      throw new AppError(
        error.message ||
          "FETCH_SETTLEMENT_BATCH_FAILED",
      );
    }

    return successResponse(
      data ?? {
        rows: [],
      },
    );
  } catch (error) {
    console.error(
      "FETCH_AGENT_COMMISSION_SETTLEMENT_BATCHES_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_SETTLEMENT_BATCH_FAILED",
    );
  }
});