// supabase/functions/_shared/user-service.ts

import type { User } from "@supabase/supabase-js";
import type { Database } from "./database.types.ts";
import type { AppSupabaseClient } from "./supabase-client.ts";
import type { Role } from "./enums.ts";
import { AppError } from "./app-error.ts";

export type AppUser = {
    id: string;
    email: string | null;
    phone: string | null;
    country_code: string;
    wallet_address: string;
    wallet_index: Number;
    referral_code: string;
    status: string;
    role: Role;
};

export async function fetchAuthenticatedUser(
    supabase: AppSupabaseClient,
): Promise<User> {
    const {
        data: { user },
        error,
    } = await supabase.auth.getUser();

    if (error || !user) {
        throw new AppError("UNAUTHORIZED");
    }

    return user;
}

export async function fetchUserWithId(
    supabase: AppSupabaseClient,
    userId: string,
): Promise<AppUser> {
    const { data, error } = await supabase
        .from("users")
        .select(`
      id,
      email,
      phone,
      country_code,
      wallet_address,
      wallet_index,
      status,
      referral_code,
      role:role_id (
        name
      )
    `)
        .eq("id", userId)
        .maybeSingle();

    if (error) {
        throw new AppError(error.message, 500);
    }

    if (!data) {
        throw new AppError("USER_NOT_FOUND", 404);
    }

    if (data.status !== "active") {
        throw new AppError("USER_NOT_ACTIVE");
    }

    const roleData = Array.isArray(data.role)
        ? data.role[0]
        : data.role;

    if (!roleData?.name) {
        throw new AppError("INVALID_ROLE");
    }

    return {
        id: data.id,
        email: data.email,
        phone: data.phone,
        country_code: data.country_code,
        wallet_address: data.wallet_address,
        wallet_index: data.wallet_index,
        status: data.status,
        referral_code: data.referral_code,
        role: roleData.name as Role,
    };
}

export function requireRole(
    user: AppUser,
    allowedRoles: readonly Role[],
): void {
    if (!allowedRoles.includes(user.role)) {
        throw new AppError("FORBIDDEN");
    }
}



type AppRole =
  Database["public"]["Enums"]["Role"];

export function validateRequiredRoles(
  userRole: AppRole | null | undefined,
  allowedRoles: readonly AppRole[],
): void {
  if (
    !userRole ||
    !allowedRoles.includes(userRole)
  ) {
    throw new AppError("FORBIDDEN");
  }
}