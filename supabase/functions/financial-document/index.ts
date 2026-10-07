// supabase/functions/financial-document/index.ts

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

function getDocumentNumber(
  request: Request,
): string {
  const url =
    new URL(request.url);

  const queryDocumentNumber =
    url.searchParams
      .get("documentNumber")
      ?.trim();

  if (queryDocumentNumber) {
    return queryDocumentNumber;
  }

  /*
   * Also support:
   *
   * /functions/v1/finance-document/{documentNumber}
   */
  const pathSegments =
    url.pathname
      .split("/")
      .filter(
        (segment) =>
          segment.length > 0,
      );

  const functionIndex =
    pathSegments.lastIndexOf(
      "finance-document",
    );

  const pathDocumentNumber =
    functionIndex >= 0
      ? pathSegments[
        functionIndex + 1
      ]
      : undefined;

  if (pathDocumentNumber) {
    return decodeURIComponent(
      pathDocumentNumber,
    ).trim();
  }

  throw new AppError(
    "ENTER_DOCUMENT_NUMBER",
  );
}

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const documentNumber =
      getDocumentNumber(request);

    if (!documentNumber) {
      throw new AppError(
        "ENTER_DOCUMENT_NUMBER",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_financial_document",
      {
        p_document_number:
          documentNumber,
      },
    );

    if (error) {
      console.error(
        "Display-document RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          documentNumber,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_DISPLAY_DOCUMENT",
      );
    }

    if (!data) {
      throw new AppError(
        "DOCUMENT_NOT_FOUND",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "DISPLAY_DOCUMENT_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_DISPLAY_DOCUMENT",
    );
  }
});