import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  successResponse,
} from "../../_shared/api-response.ts";


type ApproveCreditAgentRequest = {
  merchant_identifier?: string;
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

    let body: ApproveCreditAgentRequest;

    try {
      body =
        await request.json();
    } catch {
      return failureResponse(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const merchantIdentifier =
      body.merchant_identifier?.trim() ||
      null;

    if (!merchantIdentifier) {
      return failureResponse(
        "MERCHANT_IDENTIFIER_REQUIRED",
        400,
      );
    }

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "approve_my_credit_agent",
      {
        p_merchant_identifier:
          merchantIdentifier,
      },
    );

    if (error) {
      console.error(
        "APPROVE_CREDIT_AGENT_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          merchantIdentifier,
        },
      );

      return failureResponse(
        error.message,
        500,
        {
          code:
            error.code,

          details:
            error.details,

          hint:
            error.hint,
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
      "APPROVE_CREDIT_AGENT_ERROR",
      {
        message,
      },
    );

    return failureResponse(
      message,
    );
  }
});