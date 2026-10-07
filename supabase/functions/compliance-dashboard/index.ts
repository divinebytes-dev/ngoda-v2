import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  authenticateRequest,
} from "../../_shared/supabase-client.ts";


type ComplianceKycStatistics = {

  total_users: number;

  started: number;

  not_started: number;

  verified: number;

  rejected: number;

  pending_review: number;
};


type ComplianceRoleStatistics =
  ComplianceKycStatistics;


type ComplianceRoleCounts = {

  customer: ComplianceRoleStatistics;

  agent: ComplianceRoleStatistics;

  vendor: ComplianceRoleStatistics;

  merchant: ComplianceRoleStatistics;
};


type ComplianceSummary =
  ComplianceKycStatistics & {

    role_counts:
      ComplianceRoleCounts;
  };


type ComplianceCountry =
  ComplianceKycStatistics & {

    country_code: string;

    country_name: string;

    role_counts:
      ComplianceRoleCounts;
  };


type ComplianceDashboardResult = {

  summary:
    ComplianceSummary;

  countries:
    ComplianceCountry[];
};


Deno.serve(async (request: Request) => {
  try {

    // ========================================================
    // METHOD
    // ========================================================

    if (request.method !== "GET") {

      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );

    }


    // ========================================================
    // AUTHENTICATION
    //
    // authenticateRequest validates the user's access token.
    //
    // The SQL function performs the compliance role
    // authorization.
    // ========================================================

    const {
      supabase,
      userId,
    } =
      await authenticateRequest(
        request,
      );


    // ========================================================
    // BUILD COMPLIANCE DASHBOARD
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "build_my_compliance_dashboard",
      );


    // ========================================================
    // RPC ERROR
    // ========================================================

    if (error) {

      console.error(
        "BUILD_COMPLIANCE_DASHBOARD_RPC_FAILED",
        {
          userId,

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
          "BUILD_COMPLIANCE_DASHBOARD_FAILED",
        400,
      );

    }


    // ========================================================
    // RESULT
    // ========================================================

    if (!data) {

      throw new AppError(
        "BUILD_COMPLIANCE_DASHBOARD_FAILED",
        500,
      );

    }


    const result =
      data as
        ComplianceDashboardResult;


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse(
      result,
    );


  } catch (error) {

    // ========================================================
    // ERROR
    // ========================================================

    console.error(
      "BUILD_COMPLIANCE_DASHBOARD_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "BUILD_COMPLIANCE_DASHBOARD_FAILED",
    );

  }
});