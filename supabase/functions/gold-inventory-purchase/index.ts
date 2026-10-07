// supabase/functions/gold-inventory-purchase/index.ts

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  getTotalSupply,
} from "../../_shared/blockchain/balances.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

type GoldInventoryTransactionType =
  | "gold_inventory_purchase"
  | "gold_inventory_purchase_reversal";

type GoldInventoryRequest = {
  transaction_type?: unknown;
  transactionType?: unknown;

  quantity_grams?: unknown;
  quantityGrams?: unknown;

  price_per_gram?: unknown;
  pricePerGram?: unknown;

  currency?: unknown;
  currency_code?: unknown;

  bar_serial_number?: unknown;
  barSerialNumber?: unknown;

  supplier_name?: unknown;
  supplierName?: unknown;

  custodian_name?: unknown;
  custodianName?: unknown;

  document_number?: unknown;
  documentNumber?: unknown;
};

function optionalString(
  value: unknown,
): string | null {
  if (
    typeof value !== "string"
  ) {
    return null;
  }

  const result =
    value.trim();

  return result || null;
}

function requiredPositiveNumber(
  value: unknown,
  errorCode: string,
): number {
  const result =
    typeof value === "number"
      ? value
      : Number(value);

  if (
    !Number.isFinite(result) ||
    result <= 0
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return result;
}

function parseTransactionType(
  body: GoldInventoryRequest,
): GoldInventoryTransactionType {
  const rawTransactionType =
    body.transaction_type ??
    body.transactionType;

  if (
    typeof rawTransactionType !==
    "string"
  ) {
    throw new AppError(
      "TRANSACTION_TYPE_IS_REQUIRED",
    );
  }

  const transactionType =
    rawTransactionType
      .trim()
      .toLowerCase();

  if (
    transactionType !==
      "gold_inventory_purchase" &&
    transactionType !==
      "gold_inventory_purchase_reversal"
  ) {
    throw new AppError(
      "INVALID_GOLD_INVENTORY_TRANSACTION_TYPE",
    );
  }

  return transactionType;
}

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    let body:
      GoldInventoryRequest;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    const transactionType =
      parseTransactionType(body);

    const isReversal =
      transactionType ===
      "gold_inventory_purchase_reversal";

    let quantityGrams:
      number | null = null;

    let pricePerGram:
      number | null = null;

    let currency:
      string | null = null;

    let barSerialNumber:
      string | null = null;

    let documentNumber:
      string | null = null;

    if (!isReversal) {
      quantityGrams =
        requiredPositiveNumber(
          body.quantity_grams ??
            body.quantityGrams,
          "INVALID_GOLD_QUANTITY",
        );

      pricePerGram =
        requiredPositiveNumber(
          body.price_per_gram ??
            body.pricePerGram,
          "INVALID_GOLD_PRICE",
        );

      currency =
        optionalString(
          body.currency ??
            body.currency_code,
        )?.toLowerCase() ??
        null;

      if (!currency) {
        throw new AppError(
          "CURRENCY_REQUIRED",
        );
      }

      barSerialNumber =
        optionalString(
          body.bar_serial_number ??
            body.barSerialNumber,
        );

      if (!barSerialNumber) {
        throw new AppError(
          "BAR_SERIAL_NUMBER_REQUIRED",
        );
      }
    } else {
      documentNumber =
        optionalString(
          body.document_number ??
            body.documentNumber,
        );

      if (!documentNumber) {
        throw new AppError(
          "DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL",
        );
      }
    }

    /*
     * Read the actual on-chain token supply before beginning
     * the database reconciliation.
     */
    const totalSupply =
      await getTotalSupply();

    const tokenTotalSupply =
      Number(
        totalSupply.token_balance,
      );

    if (
      !Number.isFinite(
        tokenTotalSupply,
      ) ||
      tokenTotalSupply < 0
    ) {
      throw new AppError(
        "INVALID_TOKEN_TOTAL_SUPPLY",
      );
    }

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
      "execute_my_gold_inventory_purchase",
      {
        p_transaction_type:
          transactionType,

        p_token_total_supply:
          tokenTotalSupply,

        p_quantity_grams:
          quantityGrams,

        p_price_per_gram:
          pricePerGram,

        p_currency_code:
          currency,

        p_bar_serial_number:
          barSerialNumber,

        p_supplier_name:
          optionalString(
            body.supplier_name ??
              body.supplierName,
          ),

        p_custodian_name:
          optionalString(
            body.custodian_name ??
              body.custodianName,
          ),


        p_document_number:
          documentNumber,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "Gold inventory purchase RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          transactionType,
          documentNumber,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_CAPTURE_GOLD_PURCHASE",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "GOLD_INVENTORY_PURCHASE_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_CAPTURE_GOLD_PURCHASE",
    );
  }
});