import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


type UpsertUserKycDetailsBody = {
  idType?: unknown;
  idNumber?: unknown;
  expiryDate?: unknown;
  occupation?: unknown;
  sourceOfFunds?: unknown;
  taxNumber?: unknown;
};


/*
 * ============================================================
 * OPTIONAL STRING
 * ============================================================
 */
function parseOptionalString(
  value: unknown,
  fieldName: string,
): string | null {
  if (
    value === null ||
    value === undefined
  ) {
    return null;
  }

  if (typeof value !== "string") {
    throw new AppError(
      `INVALID_${fieldName.toUpperCase()}`,
      400,
    );
  }


  const parsed =
    value.trim();


  return parsed === ""
    ? null
    : parsed;
}


/*
 * ============================================================
 * OPTIONAL DATE
 *
 * Flutter may send:
 *
 * 2030-09-13
 *
 * or:
 *
 * 2030-09-13T00:00:00.000
 *
 * PostgreSQL expects YYYY-MM-DD.
 * ============================================================
 */
function parseOptionalDate(
  value: unknown,
): string | null {
  if (
    value === null ||
    value === undefined
  ) {
    return null;
  }


  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      "INVALID_EXPIRY_DATE",
      400,
    );
  }


  const parsedValue =
    value.trim();


  const isoDateMatch =
    parsedValue.match(
      /^(\d{4}-\d{2}-\d{2})/,
    );


  if (isoDateMatch === null) {
    throw new AppError(
      "INVALID_EXPIRY_DATE",
      400,
    );
  }


  const dateValue =
    isoDateMatch[1];


  const parsedDate =
    new Date(
      `${dateValue}T00:00:00Z`,
    );


  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    throw new AppError(
      "INVALID_EXPIRY_DATE",
      400,
    );
  }


  return dateValue;
}


Deno.serve(async (request: Request) => {
  try {

    // ========================================================
    // METHOD
    // ========================================================

    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    // ========================================================
    // BODY
    // ========================================================

    let body:
      UpsertUserKycDetailsBody;


    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    if (
      body === null ||
      typeof body !== "object" ||
      Array.isArray(body)
    ) {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    // ========================================================
    // VALUES
    //
    // Flutter:
    //
    // idType
    // idNumber
    // expiryDate
    // occupation
    // sourceOfFunds
    // taxNumber
    //
    // SQL parameters remain snake_case.
    // ========================================================

    const idType =
      parseOptionalString(
        body.idType,
        "id_type",
      );


    const idNumber =
      parseOptionalString(
        body.idNumber,
        "id_number",
      );


    const expiryDate =
      parseOptionalDate(
        body.expiryDate,
      );


    const occupation =
      parseOptionalString(
        body.occupation,
        "occupation",
      );


    const sourceOfFunds =
      parseOptionalString(
        body.sourceOfFunds,
        "source_of_funds",
      );


    const taxNumber =
      parseOptionalString(
        body.taxNumber,
        "tax_number",
      );


    // ========================================================
    // AUTHENTICATED CLIENT
    // ========================================================

    const supabase =
      createSupabaseClient(
        request,
      );


    // ========================================================
    // UPSERT KYC DETAILS
    // ========================================================

    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_my_user_kyc_details",
      {
        p_id_type:
          idType,

        p_id_number:
          idNumber,

        p_expiry_date:
          expiryDate,

        p_occupation:
          occupation,

        p_source_of_funds:
          sourceOfFunds,

        p_tax_number:
          taxNumber,
      },
    );


    // ========================================================
    // RPC ERROR
    // ========================================================

    if (error) {
      console.error(
        "UPSERT_MY_USER_KYC_DETAILS_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );


      throw new AppError(
        error.message ||
          "UPSERT_USER_KYC_DETAILS_FAILED",
      );
    }


    // ========================================================
    // RESULT VALIDATION
    // ========================================================

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_USER_KYC_DETAILS_RESULT",
      );
    }


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse(
      data,
    );

  } catch (error) {

    console.error(
      "UPSERT_MY_USER_KYC_DETAILS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "UPSERT_USER_KYC_DETAILS_FAILED",
    );
  }
});