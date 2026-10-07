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


type CreateAgentCommissionBatchBody = {
  currency_code?: unknown;
  start_date?: unknown;
  end_date?: unknown;
};


function parseRequiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


function parseIsoDate(
  value: unknown,
  errorMessage: string,
): string {
  const dateValue =
    parseRequiredString(
      value,
      errorMessage,
    );

  /*
   * PostgreSQL expects YYYY-MM-DD.
   */
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(
      dateValue,
    )
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const parsedDate =
    new Date(
      `${dateValue}T00:00:00.000Z`,
    );

  if (
    Number.isNaN(
      parsedDate.getTime(),
    ) ||
    parsedDate
      .toISOString()
      .slice(0, 10) !== dateValue
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return dateValue;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body:
      CreateAgentCommissionBatchBody;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const currencyCode =
      parseRequiredString(
        body.currency_code,
        "CURRENCY_CODE_REQUIRED",
      ).toLowerCase();

    const startDate =
      parseIsoDate(
        body.start_date,
        "INVALID_START_DATE",
      );

    const endDate =
      parseIsoDate(
        body.end_date,
        "INVALID_END_DATE",
      );

    /*
     * YYYY-MM-DD values can be compared safely in
     * lexical order.
     */
    if (startDate > endDate) {
      throw new AppError(
        "INVALID_SETTLEMENT_DATE_RANGE",
        400,
      );
    }

    if (currencyCode === "gold") {
      throw new AppError(
        "INVALID_COMMISSION_SETTLEMENT_CURRENCY",
        400,
      );
    }

    /*
     * PostgreSQL resolves the Accounts user from
     * auth.uid() and enforces the Accounts role.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error: rpcError,
    } = await supabase.rpc(
      "create_my_agent_commission_settlement_batch",
      {
        p_currency_code:
          currencyCode,

        p_start_date:
          startDate,

        p_end_date:
          endDate,
      },
    );

    if (rpcError) {
      console.error(
        "CREATE_AGENT_COMMISSION_BATCH_PAYMENT_RPC_FAILED",
        {
          code:
            rpcError.code,

          message:
            rpcError.message,

          details:
            rpcError.details,

          hint:
            rpcError.hint,

          currencyCode,
          startDate,
          endDate,
        },
      );

      /*
       * The selected date range contains no eligible,
       * unbatched commission entries.
       */
      if (
        rpcError.message.includes(
          "NO_PENDING_AGENT_COMMISSIONS_FOR_DATE_RANGE",
        )
      ) {
        throw new AppError(
          "NO_PENDING_AGENT_COMMISSIONS_FOR_DATE_RANGE",
          422,
        );
      }

      /*
       * A draft, approved or otherwise unfinished batch
       * already exists for this country and currency.
       */
      if (
        rpcError.message.includes(
          "AGENT_COMMISSION_PAYMENT_ALREADY_UNDERWAY",
        ) ||
        rpcError.code === "23505"
      ) {
        throw new AppError(
          "AGENT_COMMISSION_PAYMENT_ALREADY_UNDERWAY",
          409,
        );
      }

      if (rpcError.code === "42501") {
        throw new AppError(
          rpcError.message ||
            "FORBIDDEN",
          403,
        );
      }

      if (rpcError.code === "22P02") {
        throw new AppError(
          "INVALID_SETTLEMENT_INPUT",
          400,
        );
      }

      throw new AppError(
        rpcError.message ||
          "CREATE_AGENT_COMMISSION_BATCH_PAYMENT_FAILED",
      );
    }

    /*
     * A successful creation must return the batch and
     * its settlement items. No eligible commissions are
     * now reported as a 422 error by PostgreSQL.
     */
    if (!data) {
      throw new AppError(
        "AGENT_COMMISSION_BATCH_RESULT_NOT_FOUND",
        500,
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "CREATE_AGENT_COMMISSION_BATCH_PAYMENT_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "CREATE_AGENT_COMMISSION_BATCH_PAYMENT_FAILED",
    );
  }
});