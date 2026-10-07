import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  successResponse,
} from "../../_shared/api-response.ts";


type FundAgentRequest = {
  transaction_type?: string;
  agent_identifier?: string;
  currency?: string;
  amount?: number | string;
  reference?: string;
  document_number?: string;
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
      await request.json() as FundAgentRequest;

    /*
     * Preserve the original API behaviour:
     *
     * - Missing transaction_type means normal agent funding.
     * - Reversal must explicitly send agent_funding_reversal.
     */
    const transactionType =
      body.transaction_type
        ?.trim()
        .toLowerCase() ||
      "agent_funding";

    if (
      transactionType !== "agent_funding" &&
      transactionType !== "agent_funding_reversal"
    ) {
      return failureResponse(
        "INVALID_AGENT_FUNDING_TRANSACTION_TYPE",
        400,
      );
    }

    const isReversal =
      transactionType ===
      "agent_funding_reversal";

    let agentIdentifier: string | null =
      null;

    let currencyCode: string | null =
      null;

    let amount: number | null =
      null;

    let reference: string | null =
      null;

    let documentNumber: string | null =
      null;

    if (isReversal) {
      documentNumber =
        body.document_number?.trim() ||
        null;

      if (!documentNumber) {
        return failureResponse(
          "DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL",
          400,
        );
      }
    } else {
      agentIdentifier =
        body.agent_identifier?.trim() ||
        null;

      currencyCode =
        body.currency
          ?.trim()
          .toLowerCase() ||
        null;

      reference =
        body.reference?.trim() ||
        null;

      amount =
        Number(body.amount);

      if (!agentIdentifier) {
        return failureResponse(
          "AGENT_IDENTIFIER_REQUIRED",
          400,
        );
      }

      if (!currencyCode) {
        return failureResponse(
          "CURRENCY_REQUIRED",
          400,
        );
      }

      if (!reference) {
        return failureResponse(
          "REFERENCE_REQUIRED",
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
      "execute_my_agent_funding",
      {
        p_transaction_type:
          transactionType,

        p_agent_identifier:
          agentIdentifier,

        p_currency_code:
          currencyCode,

        p_amount:
          amount,

        p_reference:
          reference,

        p_document_number:
          documentNumber,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "FUND_AGENT_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          transactionType,
          documentNumber,
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
      "FUND_AGENT_ERROR",
      {
        message,
      },
    );

    return failureResponse(
      message,
    );
  }
});