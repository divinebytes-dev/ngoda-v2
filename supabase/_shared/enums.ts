import {
    Constants,
    type Database,
} from "./database.types.ts";

type DatabaseEnums = Database["public"]["Enums"];

function createEnumObject<
    const T extends readonly string[],
>(
    values: T,
): {
        readonly [K in T[number]]: K;
    } {
    return Object.fromEntries(
        values.map((value) => [value, value]),
    ) as {
            readonly [K in T[number]]: K;
        };
}

/* =========================
 * ROLE
 * ========================= */

export type Role = DatabaseEnums["Role"];

export const Role = createEnumObject(
    Constants.public.Enums.Role,
);

/* =========================
 * USER STATUS
 * ========================= */

export type UserStatus =
    DatabaseEnums["UserStatus"];

export const UserStatus = createEnumObject(
    Constants.public.Enums.UserStatus,
);

/* =========================
 * TRANSACTION TYPE
 * ========================= */

export type TransactionType =
    DatabaseEnums["TransactionType"];

export const TransactionType = createEnumObject(
    Constants.public.Enums.TransactionType,
);

/* =========================
 * TRANSACTION STATUS
 * ========================= */

export type TransactionStatus =
    DatabaseEnums["TransactionStatus"];

export const TransactionStatus = createEnumObject(
    Constants.public.Enums.TransactionStatus,
);

/* =========================
 * WALLET OWNER
 * ========================= */

export type WalletOwnerType =
    DatabaseEnums["WalletOwnerType"];

export const WalletOwnerType = createEnumObject(
    Constants.public.Enums.WalletOwnerType,
);

/* =========================
 * COMPONENT TYPE
 * ========================= */

export type ComponentType =
    DatabaseEnums["ComponentType"];

export const ComponentType = createEnumObject(
    Constants.public.Enums.ComponentType,
);

/* =========================
 * PRINCIPAL MODE
 * ========================= */

export type PrincipalMode =
    DatabaseEnums["PrincipalMode"];

export const PrincipalMode = createEnumObject(
    Constants.public.Enums.PrincipalMode,
);

/* =========================
 * AUDIT ACTION
 * ========================= */

export type AuditActionType =
    DatabaseEnums["AuditActionType"];

export const AuditActionType = createEnumObject(
    Constants.public.Enums.AuditActionType,
);

/* =========================
 * NOTIFICATION
 * ========================= */

export type NotificationAudience =
    DatabaseEnums["NotificationAudience"];

export const NotificationAudience = createEnumObject(
    Constants.public.Enums.NotificationAudience,
);

export type NotificationType =
    DatabaseEnums["NotificationType"];

export const NotificationType = createEnumObject(
    Constants.public.Enums.NotificationType,
);