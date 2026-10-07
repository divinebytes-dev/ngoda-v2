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


type SyncCreditAgentAccountsBody = {
  country_code?: string;
};


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body: SyncCreditAgentAccountsBody;

    try {
      body =
        await request.json() as
          SyncCreditAgentAccountsBody;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    const countryCode =
      body.country_code
        ?.trim()
        .toLowerCase();

    if (!countryCode) {
      throw new AppError(
        "COUNTRY_CODE_REQUIRED",
      );
    }

    /*
     * The authenticated client forwards the Treasury
     * user's JWT to PostgreSQL.
     *
     * The RPC performs the Treasury role check.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "sync_my_credit_agent_currency_accounts",
      {
        p_country_code:
          countryCode,
      },
    );

    if (error) {
      console.error(
        "SYNC_CREDIT_AGENT_CURRENCY_ACCOUNTS_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          countryCode,
        },
      );

      throw new AppError(
        error.message ||
          "CREDIT_AGENT_CURRENCY_ACCOUNT_SYNC_FAILED",
      );
    }

    if (
      data === null ||
      data === undefined
    ) {
      throw new AppError(
        "CREDIT_AGENT_CURRENCY_ACCOUNT_SYNC_RESULT_NOT_FOUND",
      );
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(
      error,
      "CREDIT_AGENT_CURRENCY_ACCOUNT_SYNC_FAILED",
    );
  }
});