import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  authenticateRequest,
  createSupabaseAnonClient,
} from "../../_shared/supabase-client.ts";


type ChangePasswordBody = {
  currentPassword?: unknown;
  newPassword?: unknown;
};


/*
 * ============================================================
 * REQUIRED PASSWORD
 * ============================================================
 */
function parseRequiredPassword(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value;
}


/*
 * ============================================================
 * NEW PASSWORD VALIDATION
 *
 * Keep these rules aligned with registration.
 * ============================================================
 */
function validateNewPassword(
  password: string,
): void {

  if (password.length < 8) {
    throw new AppError(
      "PASSWORD_TOO_SHORT",
      400,
    );
  }


  if (!/[A-Z]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_UPPERCASE",
      400,
    );
  }


  if (!/[a-z]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_LOWERCASE",
      400,
    );
  }


  if (!/[0-9]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_NUMBER",
      400,
    );
  }
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
    // AUTHENTICATE REQUEST
    //
    // This is CHANGE PASSWORD.
    //
    // The caller MUST already have a valid authenticated
    // Supabase session.
    // ========================================================

    const {
      supabase,
      userId,
    } =
      await authenticateRequest(
        request,
      );


    // ========================================================
    // REQUEST BODY
    // ========================================================

    let body:
      ChangePasswordBody;


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
    // PASSWORDS
    // ========================================================

    const currentPassword =
      parseRequiredPassword(
        body.currentPassword,
        "CURRENT_PASSWORD_MISSING",
      );


    const newPassword =
      parseRequiredPassword(
        body.newPassword,
        "NEW_PASSWORD_MISSING",
      );


    // ========================================================
    // NEW PASSWORD VALIDATION
    // ========================================================

    validateNewPassword(
      newPassword,
    );


    if (
      currentPassword ===
        newPassword
    ) {
      throw new AppError(
        "NEW_PASSWORD_MUST_BE_DIFFERENT",
        400,
      );
    }


    // ========================================================
    // AUTHENTICATED USER
    //
    // We need the user's trusted login identifier so that we
    // can verify the supplied currentPassword.
    // ========================================================

    const {
      data: userData,
      error: userError,
    } =
      await supabase.auth.getUser();


    if (
      userError ||
      !userData.user
    ) {
      throw new AppError(
        "UNAUTHORIZED",
        401,
      );
    }


    const user =
      userData.user;


    if (user.id !== userId) {
      throw new AppError(
        "UNAUTHORIZED",
        401,
      );
    }


    const email =
      user.email?.trim() ||
      null;


    const phone =
      user.phone?.trim() ||
      null;


    if (
      email === null &&
      phone === null
    ) {
      throw new AppError(
        "LOGIN_IDENTIFIER_NOT_FOUND",
        400,
      );
    }


    // ========================================================
    // VERIFY CURRENT PASSWORD
    //
    // Authentication above proves who is making the request.
    //
    // This fresh sign-in separately proves that
    // currentPassword is actually correct.
    // ========================================================

    const verificationClient =
      createSupabaseAnonClient();


    let verificationResult;


    if (email !== null) {

      verificationResult =
        await verificationClient.auth
          .signInWithPassword({
            email,
            password:
              currentPassword,
          });

    } else {

      verificationResult =
        await verificationClient.auth
          .signInWithPassword({
            phone:
              phone!,

            password:
              currentPassword,
          });

    }


    if (
      verificationResult.error ||
      !verificationResult.data.user
    ) {
      throw new AppError(
        "CURRENT_PASSWORD_INCORRECT",
        400,
      );
    }


    // ========================================================
    // IDENTITY CHECK
    //
    // The credentials verified above must belong to the same
    // authenticated user.
    // ========================================================

    if (
      verificationResult.data.user.id !==
        userId
    ) {
      throw new AppError(
        "CURRENT_PASSWORD_INCORRECT",
        400,
      );
    }


    // ========================================================
    // CHANGE PASSWORD
    //
    // Use the authenticated caller's client.
    // ========================================================

    const {
      data: updateData,
      error: updateError,
    } =
      await supabase.auth.updateUser({
        password:
          newPassword,
      });


    if (
      updateError ||
      !updateData.user
    ) {
      console.error(
        "CHANGE_PASSWORD_UPDATE_FAILED",
        {
          userId,
          message:
            updateError?.message,
        },
      );


      throw new AppError(
        updateError?.message ||
          "PASSWORD_UPDATE_FAILED",
        400,
      );
    }


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse({
      passwordChanged:
        true,
    });

  } catch (error) {

    console.error(
      "CHANGE_PASSWORD_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "CHANGE_PASSWORD_FAILED",
    );
  }
});