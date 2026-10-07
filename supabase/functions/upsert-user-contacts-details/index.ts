import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";


type UpsertUserContactDetailsBody = {
  email?: unknown;
  phone?: unknown;
  countryCode?: unknown;
  countryName?: unknown;
  residentialAddress?: unknown;
  city?: unknown;
  provinceState?: unknown;
};


type UserContactContext = {
  user_id: string;
  current_email: string | null;
  current_phone: string | null;
  country_code: string;
  country_name: string;
  calling_code: string;
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
 * REQUIRED STRING
 * ============================================================
 */
function parseRequiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


/*
 * ============================================================
 * EMAIL
 * ============================================================
 */
function parseOptionalEmail(
  value: unknown,
): string | null {
  const email =
    parseOptionalString(
      value,
      "email",
    );

  if (email === null) {
    return null;
  }

  const normalizedEmail =
    email.toLowerCase();

  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
      normalizedEmail,
    )
  ) {
    throw new AppError(
      "INVALID_EMAIL",
      400,
    );
  }

  return normalizedEmail;
}


/*
 * ============================================================
 * PHONE TO E.164
 *
 * Examples:
 *
 * calling code: +263
 *
 * 0661874837
 *      -> +263661874837
 *
 * +263661874837
 *      -> +263661874837
 *
 * 263661874837
 *      -> +263661874837
 * ============================================================
 */
function normalizePhoneToE164(
  phone: string | null,
  callingCode: string,
): string | null {
  if (phone === null) {
    return null;
  }


  let normalizedCallingCode =
    callingCode
      .trim()
      .replace(/[^\d+]/g, "");


  if (
    !normalizedCallingCode.startsWith("+")
  ) {
    normalizedCallingCode =
      `+${normalizedCallingCode}`;
  }


  const callingCodeDigits =
    normalizedCallingCode.substring(1);


  /*
   * Remove formatting characters from the supplied number.
   */
  let normalizedPhone =
    phone
      .trim()
      .replace(/[^\d+]/g, "");


  /*
   * Already international.
   */
  if (
    normalizedPhone.startsWith("+")
  ) {
    if (
      !/^\+[1-9]\d{7,14}$/.test(
        normalizedPhone,
      )
    ) {
      throw new AppError(
        "INVALID_PHONE",
        400,
      );
    }

    return normalizedPhone;
  }


  /*
   * Number already contains the country's calling code
   * but does not contain +.
   *
   * Example:
   *
   * 263661874837
   */
  if (
    normalizedPhone.startsWith(
      callingCodeDigits,
    )
  ) {
    normalizedPhone =
      `+${normalizedPhone}`;
  } else {

    /*
     * Local number.
     *
     * Remove trunk-prefix zero(s).
     *
     * 0661874837
     *      -> 661874837
     */
    normalizedPhone =
      normalizedPhone.replace(
        /^0+/,
        "",
      );

    normalizedPhone =
      `${normalizedCallingCode}${normalizedPhone}`;
  }


  if (
    !/^\+[1-9]\d{7,14}$/.test(
      normalizedPhone,
    )
  ) {
    throw new AppError(
      "INVALID_PHONE",
      400,
    );
  }


  return normalizedPhone;
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
    // REQUEST BODY
    // ========================================================

    let body:
      UpsertUserContactDetailsBody;

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
    // BASIC VALIDATION
    // ========================================================

    const email =
      parseOptionalEmail(
        body.email,
      );


    const rawPhone =
      parseOptionalString(
        body.phone,
        "phone",
      );


    const countryCode =
      parseRequiredString(
        body.countryCode,
        "COUNTRY_CODE_MISSING",
      )
        .toUpperCase();


    const residentialAddress =
      parseOptionalString(
        body.residentialAddress,
        "residential_address",
      );


    const city =
      parseOptionalString(
        body.city,
        "city",
      );


    const provinceState =
      parseOptionalString(
        body.provinceState,
        "province_state",
      );


    // ========================================================
    // AUTHENTICATED CLIENT
    // ========================================================

    const supabase =
      createSupabaseClient(
        request,
      );


    // ========================================================
    // FETCH TRUSTED CONTACT CONTEXT
    //
    // We trust the country/calling code returned from the DB,
    // not countryName or a calling code supplied by Flutter.
    // ========================================================

    const {
      data: contextData,
      error: contextError,
    } = await supabase.rpc(
      "fetch_my_user_contact_context",
      {
        p_country_code:
          countryCode,
      },
    );


    if (contextError) {
      console.error(
        "FETCH_MY_USER_CONTACT_CONTEXT_FAILED",
        {
          code:
            contextError.code,

          message:
            contextError.message,

          details:
            contextError.details,

          hint:
            contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "USER_CONTACT_CONTEXT_FAILED",
      );
    }


    if (
      !Array.isArray(contextData) ||
      contextData.length === 0
    ) {
      throw new AppError(
        "USER_CONTACT_CONTEXT_NOT_FOUND",
      );
    }


    const context =
      contextData[0] as UserContactContext;


    // ========================================================
    // NORMALIZE PHONE
    //
    // calling_code is trusted because it came from
    // operational_country.
    // ========================================================

    const phone =
      normalizePhoneToE164(
        rawPhone,
        context.calling_code,
      );


    // ========================================================
    // DETERMINE AUTH CHANGES
    // ========================================================

    const currentEmail =
      context.current_email
        ?.trim()
        .toLowerCase() ??
      null;


    const currentPhone =
      context.current_phone
        ?.trim() ??
      null;


    const emailChanged =
      email !== currentEmail;


    const phoneChanged =
      phone !== currentPhone;


    // ========================================================
    // UPDATE SUPABASE AUTH
    //
    // Email/phone are login identifiers.
    // ========================================================

    if (
      emailChanged ||
      phoneChanged
    ) {
      const serviceSupabase =
        createSupabaseServiceClient();


      const authUpdate: {
        email?: string;
        phone?: string;
      } = {};


      if (
        emailChanged &&
        email !== null
      ) {
        authUpdate.email =
          email;
      }


      if (
        phoneChanged &&
        phone !== null
      ) {
        authUpdate.phone =
          phone;
      }


      if (
        Object.keys(
          authUpdate,
        ).length > 0
      ) {
        const {
          error: authUpdateError,
        } =
          await serviceSupabase
            .auth
            .admin
            .updateUserById(
              context.user_id,
              authUpdate,
            );


        if (authUpdateError) {
          console.error(
            "UPDATE_AUTH_CONTACT_DETAILS_FAILED",
            {
              userId:
                context.user_id,

              message:
                authUpdateError.message,
            },
          );

          throw new AppError(
            authUpdateError.message ||
              "UPDATE_AUTH_CONTACT_DETAILS_FAILED",
            400,
          );
        }
      }
    }


    // ========================================================
    // UPDATE APPLICATION USER
    //
    // We use trusted country_code from the context rather
    // than simply forwarding the request value.
    // ========================================================

    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_my_user_contact_details",
      {
        p_email:
          email,

        p_phone:
          phone,

        p_country_code:
          context.country_code,

        p_residential_address:
          residentialAddress,

        p_city:
          city,

        p_province_state:
          provinceState,
      },
    );


    // ========================================================
    // RPC ERROR
    // ========================================================

    if (error) {
      console.error(
        "UPSERT_MY_USER_CONTACT_DETAILS_RPC_FAILED",
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
          "UPSERT_USER_CONTACT_DETAILS_FAILED",
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
        "INVALID_USER_CONTACT_DETAILS_RESULT",
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
      "UPSERT_MY_USER_CONTACT_DETAILS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "UPSERT_USER_CONTACT_DETAILS_FAILED",
    );
  }
});