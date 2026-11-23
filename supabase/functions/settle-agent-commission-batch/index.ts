import { sendPushNotification } from "../../_shared/push-notification.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";


type SettleAgentCommissionBatchBody = {
  batch_id?: unknown;
};


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


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body:
      SettleAgentCommissionBatchBody;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const batchId =
      parseRequiredString(
        body.batch_id,
        "BATCH_ID_REQUIRED",
      );

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";

    /*
     * The authenticated RPC derives the Accounts user
     * and country from auth.uid().
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "execute_my_agent_commission_settlement_batch",
      {
        p_batch_id:
          batchId,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "SETTLE_AGENT_COMMISSION_BATCH_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          batchId,
        },
      );

      throw new AppError(
        error.message ||
          "POST_SETTLEMENT_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "AGENT_COMMISSION_SETTLEMENT_RESULT_NOT_FOUND",
      );
    }

    const { push_notification_ids: notificationIds, ...settlement } =
      data as Record<string, unknown> & { push_notification_ids?: string[] };

    if (notificationIds?.length) {
      try {
        const serviceClient = createSupabaseServiceClient();
        const { data: targets, error: pushLookupError } = await serviceClient.rpc(
          "fetch_agent_commission_settlement_push_targets",
          { p_notification_ids: notificationIds },
        );

        if (pushLookupError) {
          console.error("COMMISSION_SETTLEMENT_PUSH_LOOKUP_FAILED", {
            batchId,
            code: pushLookupError.code,
          });
        } else {
          for (const target of targets ?? []) {
            const rawTokens: unknown = target.device_tokens;
            const tokens = new Set<string>();

            if (Array.isArray(rawTokens)) {
              for (const value of rawTokens) {
                if (typeof value === "string") {
                  const token = value.trim();
                  if (token) {
                    tokens.add(token);
                  }
                }
              }
            }

            if (!tokens.size || !target.title || !target.body) {
              continue;
            }

            try {
              const result = await sendPushNotification({
                tokens: [...tokens],
                title: target.title,
                body: target.body,
                data: {
                  notification_id: target.notification_id ?? "",
                  reference: target.reference ?? "",
                },
              });

              if (result?.failureCount) {
                console.error("COMMISSION_SETTLEMENT_PUSH_PARTIAL_FAILURE", {
                  batchId,
                  notificationId: target.notification_id,
                  failureCount: result.failureCount,
                });
              }
            } catch {
              console.error("COMMISSION_SETTLEMENT_PUSH_FAILED", {
                batchId,
                notificationId: target.notification_id,
              });
            }
          }
        }
      } catch {
        console.error("COMMISSION_SETTLEMENT_PUSH_LOOKUP_FAILED", { batchId });
      }
    }

    return successResponse(settlement);
  } catch (error) {
    console.error(
      "SETTLE_AGENT_COMMISSION_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "POST_SETTLEMENT_FAILED",
    );
  }
});




// import {
//   errorResponse,
//   successResponse,
// } from "../../_shared/api-response.ts";

// import {
//   createSupabaseClient,
// } from "../../_shared/supabase-client.ts";

// import {
//   AppError,
// } from "../../_shared/app-error.ts";


// type SettleAgentCommissionBatchBody = {
//   batch_id?: unknown;
// };


// function parseRequiredString(
//   value: unknown,
//   errorMessage: string,
// ): string {
//   if (
//     typeof value !== "string" ||
//     value.trim() === ""
//   ) {
//     throw new AppError(
//       errorMessage,
//       400,
//     );
//   }

//   return value.trim();
// }


// Deno.serve(async (request: Request) => {
//   try {
//     if (request.method !== "POST") {
//       throw new AppError(
//         "METHOD_NOT_ALLOWED",
//         405,
//       );
//     }

//     let body:
//       SettleAgentCommissionBatchBody;

//     try {
//       body =
//         await request.json();
//     } catch {
//       throw new AppError(
//         "INVALID_REQUEST_BODY",
//         400,
//       );
//     }

//     const batchId =
//       parseRequiredString(
//         body.batch_id,
//         "BATCH_ID_REQUIRED",
//       );

//     const ipAddress =
//       request.headers
//         .get("x-forwarded-for")
//         ?.split(",")[0]
//         ?.trim() ??
//       request.headers
//         .get("x-real-ip")
//         ?.trim() ??
//       "unknown";

//     /*
//      * The authenticated RPC derives the Accounts user
//      * and country from auth.uid().
//      */
//     const supabase =
//       createSupabaseClient(request);

//     const {
//       data,
//       error,
//     } = await supabase.rpc(
//       "execute_my_agent_commission_settlement_batch",
//       {
//         p_batch_id:
//           batchId,

//         p_ip_address:
//           ipAddress,
//       },
//     );

//     if (error) {
//       console.error(
//         "SETTLE_AGENT_COMMISSION_BATCH_RPC_FAILED",
//         {
//           code:
//             error.code,

//           message:
//             error.message,

//           details:
//             error.details,

//           hint:
//             error.hint,

//           batchId,
//         },
//       );

//       throw new AppError(
//         error.message ||
//           "POST_SETTLEMENT_FAILED",
//       );
//     }

//     if (!data) {
//       throw new AppError(
//         "AGENT_COMMISSION_SETTLEMENT_RESULT_NOT_FOUND",
//       );
//     }

//     return successResponse(
//       data,
//     );
//   } catch (error) {
//     console.error(
//       "SETTLE_AGENT_COMMISSION_BATCH_ERROR",
//       {
//         error:
//           error instanceof Error
//             ? error.message
//             : String(error),
//       },
//     );

//     return errorResponse(
//       error,
//       "POST_SETTLEMENT_FAILED",
//     );
//   }
// });