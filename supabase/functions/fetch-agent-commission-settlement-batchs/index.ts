import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  Database,
} from "../../_shared/database.types.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";


type SettlementStatus =
  Database["public"]["Enums"]["SettlementStatus"];


const ALLOWED_SETTLEMENT_STATUSES:
  readonly SettlementStatus[] = [
    "draft",
    "pending",
    "approved",
    "settled",
    "cancelled",
    "partial",
    "failed",
    "processing",
  ];


function readStatuses(
  request: Request,
): SettlementStatus[] {
  const url =
    new URL(request.url);

  /*
   * Supported formats:
   *
   * ?status=approved
   *
   * ?status=approved,partial,failed
   *
   * ?status=approved&status=partial
   *
   * ?statuses=approved,partial,failed
   */
  const rawValues = [
    ...url.searchParams.getAll(
      "status",
    ),

    ...url.searchParams.getAll(
      "status[]",
    ),

    ...url.searchParams.getAll(
      "statuses",
    ),
  ];

  const normalizedValues =
    rawValues
      .flatMap(
        (value) =>
          value.split(","),
      )
      .map(
        (value) =>
          value
            .trim()
            .toLowerCase(),
      )
      .filter(
        (value) =>
          value !== "",
      );

  if (normalizedValues.length === 0) {
    throw new AppError(
      "SETTLEMENT_STATUSES_REQUIRED",
      400,
    );
  }

  const allowedStatuses =
    new Set<string>(
      ALLOWED_SETTLEMENT_STATUSES,
    );

  for (
    const status of normalizedValues
  ) {
    if (
      !allowedStatuses.has(status)
    ) {
      throw new AppError(
        `INVALID_SETTLEMENT_STATUS_${status.toUpperCase()}`,
        400,
      );
    }
  }

  /*
   * Remove duplicates while preserving order.
   */
  return [
    ...new Set(normalizedValues),
  ] as SettlementStatus[];
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const statuses =
      readStatuses(request);

    console.log(
      "FETCH_AGENT_COMMISSION_SETTLEMENT_BATCHES_REQUEST",
      {
        statuses,
      },
    );

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_agent_commission_settlement_batches",
      {
        p_statuses:
          statuses,
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

          statuses,
        },
      );

      if (error.code === "22P02") {
        throw new AppError(
          "INVALID_SETTLEMENT_STATUS",
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
        settlementBatch: [],
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