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

type LoanDetailRequest = {
  loan_id?: string;
  page?: number;
  page_size?: number;
};

type LoanDetailParams = {
  loanId: string;
  page: number;
  pageSize: number;
};

type RpcError = {
  code?: string;
  message: string;
  details?: string | null;
  hint?: string | null;
};

type RpcResult = {
  data: unknown;
  error: RpcError | null;
};

type UntypedRpcClient = {
  rpc(
    functionName: string,
    parameters?: Record<string, unknown>,
  ): Promise<RpcResult>;
};

function getErrorMessage(
  error: unknown,
  fallback: string,
): string {
  if (
    error instanceof Error &&
    error.message
  ) {
    return error.message;
  }

  if (typeof error === "string") {
    return error;
  }

  return fallback;
}

function parsePositiveInteger(
  value: unknown,
  fallback: number,
  errorCode: string,
): number {
  if (
    value === undefined ||
    value === null
  ) {
    return fallback;
  }

  if (
    typeof value !== "number" &&
    typeof value !== "string"
  ) {
    throw new AppError(errorCode);
  }

  if (
    typeof value === "string" &&
    value.trim() === ""
  ) {
    throw new AppError(errorCode);
  }

  const parsed = Number(value);

  if (
    !Number.isSafeInteger(parsed) ||
    parsed < 1
  ) {
    throw new AppError(errorCode);
  }

  return parsed;
}

async function getLoanDetailParams(
  request: Request,
): Promise<LoanDetailParams> {
  let input: LoanDetailRequest;

  if (request.method === "GET") {
    const url = new URL(request.url);

    input = {
      loan_id:
        url.searchParams.get("loan_id") ??
        undefined,

      page:
        url.searchParams.has("page")
          ? url.searchParams.get("page") as unknown as number
          : undefined,

      page_size:
        url.searchParams.has("page_size")
          ? url.searchParams.get("page_size") as unknown as number
          : undefined,
    };
  } else {
    try {
      const body: unknown = await request.json();

      if (
        body === null ||
        typeof body !== "object" ||
        Array.isArray(body)
      ) {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      input = body as LoanDetailRequest;
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }

      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }
  }

  if (typeof input.loan_id !== "string") {
    throw new AppError(
      "LOAN_ID_UNDEFINED",
    );
  }

  const loanId = input.loan_id.trim();

  if (!loanId) {
    throw new AppError(
      "LOAN_ID_UNDEFINED",
    );
  }

  const page = parsePositiveInteger(
    input.page,
    1,
    "INVALID_PAGE",
  );

  const pageSize = parsePositiveInteger(
    input.page_size,
    50,
    "INVALID_PAGE_SIZE",
  );

  return {
    loanId,
    page,
    pageSize,
  };
}

Deno.serve(async (request: Request) => {
  try {
    if (
      request.method !== "GET" &&
      request.method !== "POST"
    ) {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const {
      loanId,
      page,
      pageSize,
    } = await getLoanDetailParams(request);

    const authSupabase =
      createSupabaseClient(request);

    const rpcClient =
      authSupabase as unknown as UntypedRpcClient;

    const {
      data,
      error: rpcError,
    } = await rpcClient.rpc(
      "fetch_my_active_loan_detail",
      {
        p_loan_id: loanId,
        p_page: page,
        p_page_size: pageSize,
      },
    );

    if (rpcError) {
      console.error(
        "FETCH_LOAN_DETAIL_RPC_FAILED",
        {
          code: rpcError.code,
          message: rpcError.message,
          details: rpcError.details,
          hint: rpcError.hint,
          loanId,
          page,
          pageSize,
        },
      );

      throw new AppError(
        rpcError.message ||
          "FETCH_LOAN_DRILLDOWN_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "ACTIVE_LOAN_NOT_FOUND",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "FETCH_LOAN_DETAIL_ERROR",
      {
        error: getErrorMessage(
          error,
          "FETCH_LOAN_DRILLDOWN_FAILED",
        ),
      },
    );

    return errorResponse(
      error,
      "FETCH_LOAN_DRILLDOWN_FAILED",
    );
  }
});

// // supabase/functions/loan-detail/index.ts

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


// type LoanDetailRequest = {
//   loan_id?: string;
// };


// type RpcError = {
//   code?: string;
//   message: string;
//   details?: string | null;
//   hint?: string | null;
// };


// type RpcResult = {
//   data: unknown;
//   error: RpcError | null;
// };


// type UntypedRpcClient = {
//   rpc(
//     functionName: string,
//     parameters?: Record<string, unknown>,
//   ): Promise<RpcResult>;
// };


// function getErrorMessage(
//   error: unknown,
//   fallback: string,
// ): string {
//   if (
//     error instanceof Error &&
//     error.message
//   ) {
//     return error.message;
//   }

//   if (typeof error === "string") {
//     return error;
//   }

//   return fallback;
// }


// async function getLoanId(
//   request: Request,
// ): Promise<string | null> {
//   if (request.method === "GET") {
//     const url =
//       new URL(request.url);

//     return (
//       url.searchParams
//         .get("loan_id")
//         ?.trim() ??
//       null
//     );
//   }

//   let body: LoanDetailRequest;

//   try {
//     body = await request.json();
//   } catch {
//     throw new AppError(
//       "INVALID_REQUEST_BODY",
//     );
//   }

//   return (
//     body.loan_id?.trim() ??
//     null
//   );
// }


// Deno.serve(async (request: Request) => {
//   try {
//     /*
//      * Supabase functions.invoke() uses POST.
//      * GET remains available for direct HTTP calls.
//      */
//     if (
//       request.method !== "GET" &&
//       request.method !== "POST"
//     ) {
//       throw new AppError(
//         "METHOD_NOT_ALLOWED",
//       );
//     }

//     const loanId =
//       await getLoanId(request);

//     if (!loanId) {
//       throw new AppError(
//         "LOAN_ID_UNDEFINED",
//       );
//     }

//     const authSupabase =
//       createSupabaseClient(request);

//     const rpcClient =
//       authSupabase as unknown as
//         UntypedRpcClient;

//     /*
//      * PostgreSQL validates that:
//      * - the caller is an authenticated customer
//      * - the loan is active
//      * - the loan belongs to the caller
//      */
//     const {
//       data,
//       error: rpcError,
//     } = await rpcClient.rpc(
//       "fetch_my_active_loan_detail",
//       {
//         p_loan_id:
//           loanId,
//       },
//     );

//     if (rpcError) {
//       console.error(
//         "FETCH_LOAN_DETAIL_RPC_FAILED",
//         {
//           code:
//             rpcError.code,

//           message:
//             rpcError.message,

//           details:
//             rpcError.details,

//           hint:
//             rpcError.hint,

//           loanId,
//         },
//       );

//       throw new AppError(
//         rpcError.message ||
//           "FETCH_LOAN_DRILLDOWN_FAILED",
//       );
//     }

//     if (!data) {
//       throw new AppError(
//         "ACTIVE_LOAN_NOT_FOUND",
//       );
//     }

//     return successResponse(
//       data,
//     );
//   } catch (error) {
//     console.error(
//       "FETCH_LOAN_DETAIL_ERROR",
//       {
//         error:
//           getErrorMessage(
//             error,
//             "FETCH_LOAN_DRILLDOWN_FAILED",
//           ),
//       },
//     );

//     return errorResponse(
//       error,
//       "FETCH_LOAN_DRILLDOWN_FAILED",
//     );
//   }
// });