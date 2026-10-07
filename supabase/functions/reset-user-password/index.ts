import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseAnonClient,
} from "../../_shared/supabase-client.ts";


type PasswordResetBody = {
  identifier?: unknown;
};


type PasswordResetContext = {
  identifier_type:
    | "email"
    | "phone";

  email:
    string | null;

  phone:
    string | null;
};


/*
 * ============================================================
 * IDENTIFIER
 * ============================================================
 */
function parseIdentifier(
  value: unknown,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      "IDENTIFIER_MISSING",
      400,
    );
  }

  return value.trim();
}


/*
 * ============================================================
 * PASSWORD RESET REDIRECT
 *
 * After the user clicks the recovery link in the email,
 * Supabase redirects back to the Ngoda application.
 *
 * This URL must also be configured as an allowed redirect URL
 * in Supabase Auth.
 * ============================================================
 */
const PASSWORD_RESET_REDIRECT =
  "ngoda://reset-password";


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
    //
    // Flutter sends either:
    //
    // {
    //   "identifier": "user@example.com"
    // }
    //
    // or:
    //
    // {
    //   "identifier": "0771234567"
    // }
    // ========================================================

    let body:
      PasswordResetBody;


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


    const identifier =
      parseIdentifier(
        body.identifier,
      );


    // ========================================================
    // PUBLIC SUPABASE CLIENT
    //
    // Password reset happens before authentication.
    //
    // createSupabaseAnonClient() uses the publishable key
    // without attaching an authenticated user.
    // ========================================================

    const supabase =
      createSupabaseAnonClient();


    // ========================================================
    // RESOLVE IDENTIFIER
    //
    // The RPC determines whether the identifier belongs to:
    //
    //   email
    //
    // or
    //
    //   phone
    //
    // For phone numbers it also resolves a local number such
    // as:
    //
    //   0771234567
    //
    // to the user's stored E.164 number:
    //
    //   +263771234567
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "fetch_password_reset_context",
        {
          p_identifier:
            identifier,
        },
      );


    if (error) {
      console.error(
        "PASSWORD_RESET_CONTEXT_FAILED",
        {
          code:
            error.code,

          message:
            error.message,
        },
      );


      throw new AppError(
        "PASSWORD_RESET_FAILED",
        400,
      );
    }


    // ========================================================
    // CONTEXT
    //
    // RETURNS TABLE means Supabase returns an array.
    // ========================================================

    const context =
      Array.isArray(data)
        ? data[0] as
            PasswordResetContext |
            undefined
        : undefined;


    // ========================================================
    // ACCOUNT NOT FOUND
    //
    // Do not tell an unauthenticated caller whether the
    // identifier exists.
    //
    // Always return the same successful response.
    // ========================================================

    if (!context) {

      return successResponse({
        resetRequested:
          true,
      });

    }


    // ========================================================
    // EMAIL PASSWORD RESET
    //
    // Supabase sends the password recovery email.
    //
    // After the user clicks the link, Supabase redirects to:
    //
    //   ngoda://reset-password
    //
    // Flutter will then receive the recovery session and open
    // the New Password screen.
    // ========================================================

    if (
      context.identifier_type ===
        "email" &&
      context.email
    ) {

      const {
        error: resetError,
      } =
        await supabase.auth
          .resetPasswordForEmail(
            context.email,
            {
              redirectTo:
                PASSWORD_RESET_REDIRECT,
            },
          );


      if (resetError) {

        console.error(
          "PASSWORD_RESET_EMAIL_FAILED",
          {
            message:
              resetError.message,

            status:
              resetError.status,
          },
        );


        throw new AppError(
          "PASSWORD_RESET_FAILED",
          400,
        );

      }


      return successResponse({
        resetRequested:
          true,
      });

    }


    // ========================================================
    // PHONE PASSWORD RESET
    //
    // Supabase does not use resetPasswordForEmail() for phone.
    //
    // Instead, send an SMS OTP.
    //
    // shouldCreateUser = false is important because password
    // recovery must never create a new account when the phone
    // number does not exist.
    // ========================================================

    if (
      context.identifier_type ===
        "phone" &&
      context.phone
    ) {

      const {
        error: otpError,
      } =
        await supabase.auth
          .signInWithOtp({
            phone:
              context.phone,

            options: {
              shouldCreateUser:
                false,
            },
          });


      if (otpError) {

        console.error(
          "PASSWORD_RESET_PHONE_OTP_FAILED",
          {
            message:
              otpError.message,

            status:
              otpError.status,
          },
        );


        throw new AppError(
          "PASSWORD_RESET_FAILED",
          400,
        );

      }


      return successResponse({
        resetRequested:
          true,
      });

    }


    // ========================================================
    // INVALID CONTEXT
    //
    // This should not normally happen because the RPC only
    // returns email or phone.
    //
    // Keep the public response generic.
    // ========================================================

    return successResponse({
      resetRequested:
        true,
    });


  } catch (error) {

    console.error(
      "PASSWORD_RESET_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "PASSWORD_RESET_FAILED",
    );

  }
});

