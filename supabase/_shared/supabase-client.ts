// supabase/functions/_shared/supabase-client.ts

import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2";

import type { Database } from "./database.types.ts";
import { AppError } from "./app-error.ts";

export type AppSupabaseClient =
  SupabaseClient<Database>;

/* -------------------------------------------------------------------------- */
/* SUPABASE URL                                                               */
/* -------------------------------------------------------------------------- */

function getSupabaseUrl(): string {
  const supabaseUrl =
    Deno.env.get("SUPABASE_URL")?.trim();

  if (!supabaseUrl) {
    throw new AppError(
      "SUPABASE_CONFIGURATION_MISSING",
    );
  }

  return supabaseUrl;
}

/* -------------------------------------------------------------------------- */
/* NEW API KEYS                                                               */
/* -------------------------------------------------------------------------- */

function getKeyFromJsonEnv(
  envName: string,
  errorCode: string,
): string {
  const raw =
    Deno.env.get(envName)?.trim();

  if (!raw) {
    throw new AppError(errorCode);
  }

  try {
    const keys =
      JSON.parse(raw) as Record<string, string>;

    const key = keys.default?.trim();

    if (!key) {
      throw new Error(
        `Default key missing in ${envName}`,
      );
    }

    return key;
  } catch (error) {
    console.error(
      `Failed to parse ${envName}`,
      error,
    );

    throw new AppError(errorCode);
  }
}

function getPublishableKey(): string {
  return getKeyFromJsonEnv(
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_CONFIGURATION_MISSING",
  );
}

function getSecretKey(): string {
  return getKeyFromJsonEnv(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_CONFIGURATION_MISSING",
  );
}

/* -------------------------------------------------------------------------- */
/* AUTHORIZATION                                                              */
/* -------------------------------------------------------------------------- */

function getAuthorization(
  request: Request,
): string {
  const authorization =
    request.headers
      .get("Authorization")
      ?.trim();

  if (
    !authorization ||
    !/^Bearer\s+\S+$/i.test(authorization)
  ) {
    throw new AppError("UNAUTHORIZED");
  }

  return authorization;
}

/* -------------------------------------------------------------------------- */
/* USER-SCOPED CLIENT                                                         */
/* -------------------------------------------------------------------------- */

/*
 * User-scoped Supabase client.
 *
 * Uses:
 *
 *   apikey        -> publishable key
 *   Authorization -> authenticated user's JWT
 *
 * Therefore:
 *
 * - auth.uid() resolves to the authenticated user.
 * - RLS policies apply.
 * - RPC functions can inspect auth.uid().
 *
 * Use this client for user-authorized operations.
 */
export function createSupabaseClient(
  request: Request,
): AppSupabaseClient {
  const supabaseUrl =
    getSupabaseUrl();

  const publishableKey =
    getPublishableKey();

  const authorization =
    getAuthorization(request);

  return createClient<Database>(
    supabaseUrl,
    publishableKey,
    {
      global: {
        headers: {
          Authorization: authorization,
        },
      },

      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}

/* -------------------------------------------------------------------------- */
/* AUTHENTICATE REQUEST                                                       */
/* -------------------------------------------------------------------------- */

/*
 * Validates the caller and returns
 * the authenticated Supabase identity.
 */
export async function authenticateRequest(
  request: Request,
): Promise<{
  supabase: AppSupabaseClient;
  userId: string;
}> {
  const authorization =
    getAuthorization(request);

  const accessToken =
    authorization.replace(
      /^Bearer\s+/i,
      "",
    );

  const supabase =
    createSupabaseClient(request);

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(
    accessToken,
  );

  if (error || !user) {
    console.error(
      "Supabase authentication failed",
      {
        message: error?.message,
        status: error?.status,
      },
    );

    throw new AppError(
      "UNAUTHORIZED",
    );
  }

  return {
    supabase,
    userId: user.id,
  };
}

/* -------------------------------------------------------------------------- */
/* SERVER / ADMIN CLIENT                                                      */
/* -------------------------------------------------------------------------- */

/*
 * Server-scoped privileged client.
 *
 * Uses the Supabase secret key.
 *
 * - Bypasses RLS.
 * - Does not represent the caller.
 * - Must NEVER be exposed to a browser/mobile client.
 *
 * Use only for trusted server-side operations.
 */
export function createSupabaseServiceClient():
  AppSupabaseClient {
  const supabaseUrl =
    getSupabaseUrl();

  const secretKey =
    getSecretKey();

  return createClient<Database>(
    supabaseUrl,
    secretKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}

/* -------------------------------------------------------------------------- */
/* PUBLIC / UNAUTHENTICATED CLIENT                                            */
/* -------------------------------------------------------------------------- */

/*
 * Public Supabase client.
 *
 * Uses only the publishable key.
 *
 * No authenticated user is attached.
 * RLS therefore applies as an unauthenticated request.
 */
export function createSupabaseAnonClient():
  AppSupabaseClient {
  const supabaseUrl =
    getSupabaseUrl();

  const publishableKey =
    getPublishableKey();

  return createClient<Database>(
    supabaseUrl,
    publishableKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}


