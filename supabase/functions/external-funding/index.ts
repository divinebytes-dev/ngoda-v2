// supabase/functions/external-funding/index.ts

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

type ExternalFundingTransactionType =
  | "external_funding"
  | "external_funding_reversal";

type ExternalFundingRequest = {
  transaction_type?: unknown;
  transactionType?: unknown;
  currency_code?: unknown;
  currencyCode?: unknown;
  amount?: unknown;
  document_number?: unknown;
  documentNumber?: unknown;
};

function parseTransactionType(
  body: ExternalFundingRequest,
): ExternalFundingTransactionType {
  const rawTransactionType =
    body.transaction_type ??
    body.transactionType;

  if (
    typeof rawTransactionType !==
    "string"
  ) {
    throw new AppError(
      "TRANSACTION_TYPE_IS_REQUIRED",
    );
  }

  const transactionType =
    rawTransactionType
      .trim()
      .toLowerCase();

  if (
    transactionType !==
      "external_funding" &&
    transactionType !==
      "external_funding_reversal"
  ) {
    throw new AppError(
      "INVALID_EXTERNAL_FUNDING_TRANSACTION_TYPE",
    );
  }

  return transactionType;
}

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    let body: ExternalFundingRequest;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    const transactionType =
      parseTransactionType(body);

    const isFunding =
      transactionType ===
      "external_funding";

    const isReversal =
      transactionType ===
      "external_funding_reversal";

    let currencyCode:
      string | null = null;

    let amount:
      number | null = null;

    let documentNumber:
      string | null = null;

    if (isFunding) {
      const rawCurrencyCode =
        body.currency_code ??
        body.currencyCode;

      if (
        typeof rawCurrencyCode !==
          "string" ||
        !rawCurrencyCode.trim()
      ) {
        throw new AppError(
          "CURRENCY_IS_REQUIRED",
        );
      }

      currencyCode =
        rawCurrencyCode
          .trim()
          .toLowerCase();

      amount =
        typeof body.amount === "number"
          ? body.amount
          : Number(body.amount);

      if (
        !Number.isFinite(amount) ||
        amount <= 0
      ) {
        throw new AppError(
          "INVALID_AMOUNT",
        );
      }
    }

    if (isReversal) {
      const rawDocumentNumber =
        body.document_number ??
        body.documentNumber;

      if (
        typeof rawDocumentNumber !==
          "string" ||
        !rawDocumentNumber.trim()
      ) {
        throw new AppError(
          "DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL",
        );
      }

      documentNumber =
        rawDocumentNumber.trim();
    }

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";

    console.log(
      "EXTERNAL_FUNDING_REQUEST",
      {
        transactionType,
        currencyCode,
        amount,
        documentNumber,
      },
    );

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "execute_my_external_funding",
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
        "EXTERNAL_FUNDING_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          transactionType,
          documentNumber,
        },
      );

      throw new AppError(
        error.message ||
          "EXTERNAL_FUNDING_FAILED",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "EXTERNAL_FUNDING_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "EXTERNAL_FUNDING_FAILED",
    );
  }
});