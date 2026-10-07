// supabase/functions/customer-direct-deposit/index.ts

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  sendPushNotification,
} from "../../_shared/push-notification.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

type CustomerDirectDepositRequest = {
  identifier?: unknown;
  currency?: unknown;
  amount?: unknown;
  reference?: unknown;
};

type CustomerDirectDepositResult = {
  success: boolean;
  document_number: string;
  reference: string;
  user_id: string;
  currency_code: string;
  funded_amount: string;
  fee: string;
  net_amount: string;
  receiver_notification_id:
    string | null;
  device_tokens?: string[];
  push_title?: string | null;
  push_body?: string | null;
  push_reference?: string | null;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    let body:
      CustomerDirectDepositRequest;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    if (
      typeof body.identifier !==
        "string" ||
      !body.identifier.trim()
    ) {
      throw new AppError(
        "IDENTIFIER_REQUIRED",
      );
    }

    if (
      typeof body.currency !==
        "string" ||
      !body.currency.trim()
    ) {
      throw new AppError(
        "CURRENCY_REQUIRED",
      );
    }

    if (
      typeof body.reference !==
        "string" ||
      !body.reference.trim()
    ) {
      throw new AppError(
        "REFERENCE_REQUIRED",
      );
    }

    const amount =
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

    const identifier =
      body.identifier.trim();

    const currency =
      body.currency
        .trim()
        .toLowerCase();

    const reference =
      body.reference.trim();

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "execute_my_customer_direct_deposit",
      {
        p_identifier:
          identifier,

        p_currency_code:
          currency,

        p_amount:
          amount,

        p_reference:
          reference,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "Customer direct deposit RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          identifier,
          currency,
          reference,
        },
      );

      throw new AppError(
        error.message ||
          "CUSTOMER_DIRECT_DEPOSIT_FAILED",
      );
    }

    if (
      !data ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "CUSTOMER_DIRECT_DEPOSIT_FAILED",
      );
    }

    const result =
      data as unknown as
        CustomerDirectDepositResult;

    const deviceTokens =
      Array.isArray(
        result.device_tokens,
      )
        ? result.device_tokens
            .filter(
              (
                token,
              ): token is string =>
                typeof token ===
                  "string" &&
                token.length > 0,
            )
        : [];

    /*
     * Push delivery occurs after the financial transaction
     * has committed. A push failure must not reverse or report
     * the successful deposit as failed.
     */
    if (
      deviceTokens.length > 0 &&
      result.push_title &&
      result.push_body
    ) {
      try {
        await sendPushNotification({
          tokens:
            deviceTokens,

          title:
            result.push_title,

          body:
            result.push_body,

          data: {
            notification_id:
              result.receiver_notification_id ??
              "",

            reference:
              result.push_reference ??
              result.reference,
          },
        });
      } catch (pushError) {
        console.error(
          "Customer direct deposit push failed",
          {
            documentNumber:
              result.document_number,

            error:
              pushError instanceof Error
                ? pushError.message
                : String(pushError),
          },
        );
      }
    }

    /*
     * Do not expose device tokens or internal push fields.
     */
    return successResponse({
      success:
        result.success,

      document_number:
        result.document_number,

      reference:
        result.reference,

      user_id:
        result.user_id,

      currency_code:
        result.currency_code,

      funded_amount:
        result.funded_amount,

      fee:
        result.fee,

      net_amount:
        result.net_amount,

      receiver_notification_id:
        result.receiver_notification_id,
    });
  } catch (error) {
    console.error(
      "CUSTOMER_DIRECT_DEPOSIT_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "CUSTOMER_DIRECT_DEPOSIT_FAILED",
    );
  }
});