import {
  AppError,
} from "../app-error.ts";

import type {
  AcknowledgeGamificationNotificationRequest,
  ParsedAcknowledgeGamificationNotificationRequest,
} from "../types/loyalty-read.ts";


const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;


export function parsePositiveInteger(
  value: string | null,
  defaultValue: number,
  errorMessage: string,
  maximum: number,
): number {
  if (
    value === null ||
    value.trim() === ""
  ) {
    return defaultValue;
  }

  const normalizedValue =
    value.trim();

  if (!/^\d+$/.test(normalizedValue)) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const parsedValue =
    Number(normalizedValue);

  if (
    !Number.isSafeInteger(parsedValue) ||
    parsedValue < 1 ||
    parsedValue > maximum
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return parsedValue;
}


export function parseAcknowledgeNotificationRequest(
  request: AcknowledgeGamificationNotificationRequest,
): ParsedAcknowledgeGamificationNotificationRequest {
  const rawNotificationId =
    request.notification_id ??
    request.notificationId;

  if (
    typeof rawNotificationId !== "string" ||
    !UUID_PATTERN.test(rawNotificationId.trim())
  ) {
    throw new AppError(
      "INVALID_GAMIFICATION_NOTIFICATION_ID",
      400,
    );
  }

  const rawMarkSeen =
    request.mark_seen ??
    request.markSeen ??
    false;

  if (typeof rawMarkSeen !== "boolean") {
    throw new AppError(
      "INVALID_GAMIFICATION_NOTIFICATION_SEEN_VALUE",
      400,
    );
  }

  return {
    notificationId:
      rawNotificationId
        .trim()
        .toLowerCase(),

    markSeen:
      rawMarkSeen,
  };
}

