import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  successResponse,
} from "../../_shared/api-response.ts";


type FundTreasuryRequest = {
  transaction_type?: string;
  currency?: string;
  amount?: number | string;
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
      await request.json() as FundTreasuryRequest;

    /*
     * Preserve Treasury Funding behaviour:
     *
     * - Missing transaction_type means normal treasury funding.
     * - Reversal must explicitly send treasury_funding_reversal.
     */
    const transactionType =
      body.transaction_type
        ?.trim()
        .toLowerCase() ||
      "treasury_funding";

    if (
      transactionType !== "treasury_funding" &&
      transactionType !== "treasury_funding_reversal"
    ) {
      return failureResponse(
        "INVALID_TREASURY_FUNDING_TRANSACTION_TYPE",
        400,
      );
    }

    const isReversal =
      transactionType ===
      "treasury_funding_reversal";

    let currencyCode: string | null =
      null;

    let amount: number | null =
      null;

    let documentNumber: string | null =
      null;

    /*
     * Normal funding receives currency + amount.
     *
     * Reversal receives the original treasury-funding
     * document number. The SQL function resolves the
     * original currency and amount.
     */
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
      currencyCode =
        body.currency
          ?.trim()
          .toLowerCase() ||
        null;

      amount =
        Number(body.amount);

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
      "execute_my_treasury_funding",
      {
        p_transaction_type:
          transactionType,

        p_currency_code:
          currencyCode,

        p_amount:
          amount,

        p_document_number:
          documentNumber,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "FUND_TREASURY_RPC_FAILED",
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
      "FUND_TREASURY_ERROR",
      {
        message,
      },
    );

    return failureResponse(
      message,
    );
  }
});