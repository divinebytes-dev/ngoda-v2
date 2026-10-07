import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  fetchAuthenticatedUser,
} from "../../_shared/user-service.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

type TransactionConfigRow = {
  config_key: string;
  currency_code: string;
  percentage: number | string | null;
  fixed_amount: number | string | null;
  min_amount: number | string | null;
  max_amount: number | string | null;
};

type AmountConfig = {
  percentage: number;
  fixed_amount?: number;
  min_amount?: number;
  max_amount?: number;
};

type TransactionConfigResponse = Record<
  string,
  Record<string, AmountConfig>
>;

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }
console.log(
  "transactions-config version",
  "auth-wrapper-v2",
);
    /*
     * This client carries the caller's JWT.
     */
    const authSupabase =  createSupabaseClient(request);

    /*
     * Validate the JWT before calling the database.
     */
    const authUser =
      await fetchAuthenticatedUser(
        authSupabase,
      );

    /*
     * The database function uses auth.uid() to load the user's
     * role and country. No service-role client is needed.
     */
    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_transaction_configs",
    );

    if (error) {
      console.error(
        "Transaction-config RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          authenticatedUserId:
            authUser.id,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_CONFIG",
      );
    }

    const result: TransactionConfigResponse =
      {};

    const rows =
      (data ?? []) as TransactionConfigRow[];

    for (const row of rows) {
      const configKey =
        row.config_key.toLowerCase();

      const currencyCode =
        row.currency_code.toLowerCase();

      if (!result[configKey]) {
        result[configKey] = {};
      }

      const config: AmountConfig = {
        percentage:
          Number(row.percentage ?? 0),
      };

      if (row.fixed_amount != null) {
        config.fixed_amount =
          Number(row.fixed_amount);
      }

      if (row.min_amount != null) {
        config.min_amount =
          Number(row.min_amount);
      }

      if (row.max_amount != null) {
        config.max_amount =
          Number(row.max_amount);
      }

      result[configKey][currencyCode] =
        config;
    }

    return successResponse(result);
  } catch (error) {
    console.error(
      "Error fetching transaction configs",
      {
        message:
          error instanceof Error
            ? error.message
            : "FAILED_TO_FETCH_CONFIG",
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_CONFIG",
    );
  }
});


