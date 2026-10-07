import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  successResponse,
} from "../../_shared/api-response.ts";


type FundCreditAgentRequest = {
  merchant_identifier?: string;
  currency?: string;
  amount?: number | string;
  reference?: string;
};


function failureResponse(
  message: string,
  status = 500,
  error?: {
    code?: string;
    details?: string | null;
    hint?: string | null;
  },
) {
  return new Response(
    JSON.stringify({
      success: false,
      message,
      code: error?.code ?? null,
      details: error?.details ?? null,
      hint: error?.hint ?? null,
    }),
    {
      status,
      headers: {
        "Content-Type": "application/json",
      },
    },
  );
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      return failureResponse(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const body =
      await request.json() as FundCreditAgentRequest;

    const merchantIdentifier =
      body.merchant_identifier?.trim() ||
      null;

    const currencyCode =
      body.currency
        ?.trim()
        .toLowerCase() ||
      null;

    const amount =
      Number(body.amount);

    const reference =
      body.reference?.trim() ||
      null;

    if (!merchantIdentifier) {
      return failureResponse(
        "MERCHANT_IDENTIFIER_REQUIRED",
        400,
      );
    }

    if (!currencyCode) {
      return failureResponse(
        "CURRENCY_REQUIRED",
        400,
      );
    }

    if (
      !Number.isFinite(amount) ||
      amount <= 0
    ) {
      return failureResponse(
        "INVALID_AMOUNT",
        400,
      );
    }

    if (!reference) {
      return failureResponse(
        "REFERENCE_REQUIRED",
        400,
      );
    }

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ||
      request.headers.get("x-real-ip") ||
      "unknown";

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "execute_my_credit_agent_funding",
      {
        p_agent_identifier:
          merchantIdentifier,

        p_currency_code:
          currencyCode,

        p_amount:
          amount,

        p_reference:
          reference,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "FUND_CREDIT_AGENT_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          merchantIdentifier,
          currencyCode,
          reference,
        },
      );

      return failureResponse(
        error.message,
        500,
        {
          code: error.code,
          details: error.details,
          hint: error.hint,
        },
      );
    }

    return successResponse(data);
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.error(
      "FUND_CREDIT_AGENT_ERROR",
      {
        message,
      },
    );

    return failureResponse(
      message,
    );
  }
});