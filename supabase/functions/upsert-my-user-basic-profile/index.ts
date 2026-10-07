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


type UpsertUserBasicProfileBody = {
  firstName?: unknown;
  middleName?: unknown;
  surname?: unknown;
  dateOfBirth?: unknown;
  gender?: unknown;
  nationality?: unknown;
};


/*
 * ------------------------------------------------------------
 * Optional string
 * ------------------------------------------------------------
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
 * ------------------------------------------------------------
 * Optional date
 *
 * Flutter sends:
 *
 * 1993-09-13T00:00:00.000
 *
 * PostgreSQL RPC expects:
 *
 * 1983-02-14
 *
 * We intentionally take only the calendar-date portion so
 * timezone conversion cannot change the user's date of birth.
 * ------------------------------------------------------------
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
      "INVALID_DATE_OF_BIRTH",
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
      "INVALID_DATE_OF_BIRTH",
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
      "INVALID_DATE_OF_BIRTH",
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
      UpsertUserBasicProfileBody;

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
    // These names match the Flutter request exactly:
    //
    // firstName
    // middleName
    // surname
    // dateOfBirth
    // gender
    // nationality
    // ========================================================

    const firstName =
      parseOptionalString(
        body.firstName,
        "first_name",
      );

    const middleName =
      parseOptionalString(
        body.middleName,
        "middle_name",
      );

    const surname =
      parseOptionalString(
        body.surname,
        "surname",
      );

    const dateOfBirth =
      parseOptionalDate(
        body.dateOfBirth,
      );

    const gender =
      parseOptionalString(
        body.gender,
        "gender",
      );

    const nationality =
      parseOptionalString(
        body.nationality,
        "nationality",
      );


    // ========================================================
    // SUPABASE
    // ========================================================

    const supabase =
      createSupabaseClient(
        request,
      );


    // ========================================================
    // UPSERT USER BASIC PROFILE
    //
    // Flutter uses camelCase.
    //
    // PostgreSQL RPC parameters use snake_case.
    //
    // Translation happens here.
    // ========================================================

    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_my_user_basic_profile",
      {
        p_first_name:
          firstName,

        p_middle_name:
          middleName,

        p_surname:
          surname,

        p_dob:
          dateOfBirth,

        p_gender:
          gender,

        p_nationality:
          nationality,
      },
    );


    // ========================================================
    // RPC ERROR
    // ========================================================

    if (error) {
      console.error(
        "UPSERT_MY_USER_BASIC_PROFILE_RPC_FAILED",
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
          "UPSERT_USER_BASIC_PROFILE_FAILED",
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
        "INVALID_USER_BASIC_PROFILE_RESULT",
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
      "UPSERT_MY_USER_BASIC_PROFILE_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "UPSERT_USER_BASIC_PROFILE_FAILED",
    );
  }
});