import {
  AppError,
} from "../app-error.ts";

import {
  loyaltyEarningEventTypes,
  type LoyaltyEarningEventType,
} from "../types/loyalty-event-type.ts";

import type {
  AwardLoyaltyPointsRequest,
  ParsedAwardLoyaltyPointsRequest,
  ParsedReverseLoyaltyPointsRequest,
  ReverseLoyaltyPointsRequest,
} from "../types/loyalty-award.ts";


const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const DECIMAL_PATTERN =
  /^\d+(?:\.\d{1,6})?$/;


function requiredString(
  value: unknown,
  errorMessage: string,
  maximumLength = 256,
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

  const normalizedValue =
    value.trim();

  if (normalizedValue.length > maximumLength) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return normalizedValue;
}


function optionalString(
  value: unknown,
  errorMessage: string,
  maximumLength = 256,
): string | null {
  if (
    value === undefined ||
    value === null ||
    (
      typeof value === "string" &&
      value.trim() === ""
    )
  ) {
    return null;
  }

  return requiredString(
    value,
    errorMessage,
    maximumLength,
  );
}


function uuid(
  value: unknown,
  requiredMessage: string,
  invalidMessage: string,
): string {
  const parsedValue =
    requiredString(
      value,
      requiredMessage,
      36,
    );

  if (!UUID_PATTERN.test(parsedValue)) {
    throw new AppError(
      invalidMessage,
      400,
    );
  }

  return parsedValue.toLowerCase();
}


function optionalDecimal(
  value: unknown,
  errorMessage: string,
): string | null {
  if (
    value === undefined ||
    value === null ||
    value === ""
  ) {
    return null;
  }

  if (
    typeof value !== "string" &&
    typeof value !== "number"
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const decimalValue =
    String(value).trim();

  if (!DECIMAL_PATTERN.test(decimalValue)) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const [
    integerPart,
    fractionalPart = "",
  ] = decimalValue.split(".");

  if (
    integerPart.length > 14 ||
    fractionalPart.length > 6
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const normalizedInteger =
    integerPart.replace(
      /^0+(?=\d)/,
      "",
    );

  const normalizedFraction =
    fractionalPart.replace(
      /0+$/,
      "",
    );

  return normalizedFraction
    ? `${normalizedInteger}.${normalizedFraction}`
    : normalizedInteger;
}


function optionalCode(
  value: unknown,
  errorMessage: string,
): string | null {
  const parsedValue =
    optionalString(
      value,
      errorMessage,
      16,
    );

  if (parsedValue === null) {
    return null;
  }

  const normalizedValue =
    parsedValue.toLowerCase();

  if (!/^[a-z0-9_]+$/.test(normalizedValue)) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return normalizedValue;
}


function metadata(
  value: unknown,
): Record<string, unknown> {
  if (
    value === undefined ||
    value === null
  ) {
    return {};
  }

  if (
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "INVALID_GAMIFICATION_METADATA",
      400,
    );
  }

  return value as Record<string, unknown>;
}


function eventType(
  value: unknown,
): LoyaltyEarningEventType {
  const parsedValue =
    requiredString(
      value,
      "GAMIFICATION_EVENT_TYPE_REQUIRED",
      64,
    ).toLowerCase();

  if (
    !loyaltyEarningEventTypes.includes(
      parsedValue as LoyaltyEarningEventType,
    )
  ) {
    throw new AppError(
      "INVALID_GAMIFICATION_EVENT_TYPE",
      400,
    );
  }

  return parsedValue as LoyaltyEarningEventType;
}


export async function parseJsonBody(
  request: Request,
): Promise<Record<string, unknown>> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    throw new AppError(
      "INVALID_JSON_BODY",
      400,
    );
  }

  if (
    typeof body !== "object" ||
    body === null ||
    Array.isArray(body)
  ) {
    throw new AppError(
      "INVALID_JSON_BODY",
      400,
    );
  }

  return body as Record<string, unknown>;
}


export function parseAwardLoyaltyPointsRequest(
  request: AwardLoyaltyPointsRequest,
): ParsedAwardLoyaltyPointsRequest {
  return {
    idempotencyKey:
      requiredString(
        request.idempotency_key ??
          request.idempotencyKey,
        "GAMIFICATION_IDEMPOTENCY_KEY_REQUIRED",
      ),

    eventType:
      eventType(
        request.event_type ??
          request.eventType,
      ),

    userId:
      uuid(
        request.user_id ??
          request.userId,
        "GAMIFICATION_USER_ID_REQUIRED",
        "INVALID_GAMIFICATION_USER_ID",
      ),

    sourceReference:
      requiredString(
        request.source_reference ??
          request.sourceReference,
        "GAMIFICATION_SOURCE_REFERENCE_REQUIRED",
      ),

    sourceTransactionId:
      optionalString(
        request.source_transaction_id ??
          request.sourceTransactionId,
        "INVALID_GAMIFICATION_SOURCE_TRANSACTION_ID",
      ),

    transactionType:
      optionalCode(
        request.transaction_type ??
          request.transactionType,
        "INVALID_GAMIFICATION_TRANSACTION_TYPE",
      ),

    amount:
      optionalDecimal(
        request.amount,
        "INVALID_GAMIFICATION_AMOUNT",
      ),

    amountUsd:
      optionalDecimal(
        request.amount_usd ??
          request.amountUsd,
        "INVALID_GAMIFICATION_USD_AMOUNT",
      ),

    countryCode:
      optionalCode(
        request.country_code ??
          request.countryCode,
        "INVALID_GAMIFICATION_COUNTRY_CODE",
      ),

    currencyCode:
      optionalCode(
        request.currency_code ??
          request.currencyCode,
        "INVALID_GAMIFICATION_CURRENCY_CODE",
      ),

    metadata:
      metadata(request.metadata),
  };
}


export function parseReverseLoyaltyPointsRequest(
  request: ReverseLoyaltyPointsRequest,
): ParsedReverseLoyaltyPointsRequest {
  return {
    originalEventId:
      uuid(
        request.original_event_id ??
          request.originalEventId,
        "ORIGINAL_GAMIFICATION_EVENT_ID_REQUIRED",
        "INVALID_ORIGINAL_GAMIFICATION_EVENT_ID",
      ),

    idempotencyKey:
      requiredString(
        request.idempotency_key ??
          request.idempotencyKey,
        "GAMIFICATION_IDEMPOTENCY_KEY_REQUIRED",
      ),

    sourceReference:
      requiredString(
        request.source_reference ??
          request.sourceReference,
        "GAMIFICATION_SOURCE_REFERENCE_REQUIRED",
      ),

    metadata:
      metadata(request.metadata),
  };
}

