import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  authenticateRequest,
} from "../../_shared/supabase-client.ts";

import {
  getTotalSupply,
} from "../../_shared/blockchain/balances.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

type GoldInventoryTransactionType =
  | "gold_inventory_purchase"
  | "gold_inventory_purchase_reversal";

type RequestBody = Record<string, unknown>;

function optionalString(
  value: unknown,
): string | null {
  if (typeof value !== "string") {
    return null;
  }

  return value.trim() || null;
}

function requiredPositiveNumber(
  value: unknown,
  errorCode: string,
): number {
  if (
    typeof value !== "string" &&
    typeof value !== "number"
  ) {
    throw new AppError(errorCode, 400);
  }

  const result = Number(value);

  if (!Number.isFinite(result) || result <= 0) {
    throw new AppError(errorCode, 400);
  }

  return result;
}

function parseTransactionType(
  body: RequestBody,
): GoldInventoryTransactionType {
  const value = optionalString(
    body.transaction_type ?? body.transactionType,
  )?.toLowerCase();

  if (
    value !== "gold_inventory_purchase" &&
    value !== "gold_inventory_purchase_reversal"
  ) {
    throw new AppError(
      "INVALID_GOLD_INVENTORY_TRANSACTION_TYPE",
      400,
    );
  }

  return value;
}

function parseBlockchains(
  value: unknown,
): SupportedBlockchainConfig[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new AppError(
      "ACTIVE_BLOCKCHAINS_NOT_FOUND",
      500,
    );
  }

  const seenCodes = new Set<string>();
  const seenContracts = new Set<string>();

  return value.map((item): SupportedBlockchainConfig => {
    if (
      typeof item !== "object" ||
      item === null ||
      Array.isArray(item)
    ) {
      throw new AppError(
        "INVALID_BLOCKCHAIN_CONFIGURATION",
        500,
      );
    }

    const row = item as Record<string, unknown>;

    const code = optionalString(row.code)?.toLowerCase();
    const rpcUrl = optionalString(row.rpc_url);
    const contractAddress = optionalString(
      row.contract_address,
    );
    const nativeCurrencyCode = optionalString(
      row.native_currency_code,
    );

    if (
      !code ||
      !rpcUrl ||
      !contractAddress ||
      !nativeCurrencyCode ||
      typeof row.chain_id !== "number" ||
      !Number.isSafeInteger(row.chain_id) ||
      row.chain_id <= 0
    ) {
      throw new AppError(
        "INVALID_BLOCKCHAIN_CONFIGURATION",
        500,
      );
    }

    const contractKey =
      `${row.chain_id}:${contractAddress.toLowerCase()}`;

    if (
      seenCodes.has(code) ||
      seenContracts.has(contractKey)
    ) {
      throw new AppError(
        "DUPLICATE_BLOCKCHAIN_CONFIGURATION",
        500,
      );
    }

    seenCodes.add(code);
    seenContracts.add(contractKey);

    return {
      code,
      chain_id: row.chain_id,
      rpc_url: rpcUrl,
      contract_address: contractAddress,
      native_currency_code: nativeCurrencyCode,
    };
  });
}

/*
 * Add decimal strings using integer arithmetic.
 *
 * Different chains may report different decimal lengths.
 * No floating-point conversion or truncation is used.
 */
function sumDecimalAmounts(
  amounts: string[],
): string {
  let total = 0n;
  let totalScale = 0;

  for (const amount of amounts) {
    const value = amount.trim();

    if (!/^\d+(\.\d+)?$/.test(value)) {
      throw new AppError(
        "INVALID_TOKEN_TOTAL_SUPPLY",
        500,
      );
    }

    const [whole, fraction = ""] = value.split(".");
    const scale = fraction.length;
    const units = BigInt(`${whole}${fraction}`);

    if (scale > totalScale) {
      total *= 10n ** BigInt(scale - totalScale);
      totalScale = scale;
    }

    total += units * (
      10n ** BigInt(totalScale - scale)
    );
  }

  if (totalScale === 0) {
    return total.toString();
  }

  const digits = total.toString().padStart(
    totalScale + 1,
    "0",
  );

  const whole = digits.slice(0, -totalScale);
  const fraction = digits
    .slice(-totalScale)
    .replace(/0+$/, "");

  return fraction ? `${whole}.${fraction}` : whole;
}

async function fetchCombinedTokenSupply(
  blockchains: SupportedBlockchainConfig[],
): Promise<string> {
  const results = await Promise.allSettled(
    blockchains.map(async (blockchain) => {
      const supply = await getTotalSupply(blockchain);

      return supply.token_balance;
    }),
  );

  const supplies: string[] = [];
  let failed = false;

  for (let index = 0; index < results.length; index++) {
    const result = results[index];

    if (result.status === "rejected") {
      failed = true;

      console.error(
        "GOLD_INVENTORY_TOKEN_SUPPLY_FETCH_FAILED",
        {
          blockchainCode: blockchains[index].code,
          chainId: blockchains[index].chain_id,
          error:
            result.reason instanceof Error
              ? result.reason.message
              : String(result.reason),
        },
      );

      continue;
    }

    supplies.push(result.value);
  }

  /*
   * Never reconcile against an incomplete supply total.
   */
  if (failed) {
    throw new AppError(
      "GOLD_INVENTORY_TOKEN_SUPPLY_UNAVAILABLE",
      503,
    );
  }

  return sumDecimalAmounts(supplies);
}

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const { supabase } = await authenticateRequest(
      request,
    );

    let rawBody: unknown;

    try {
      rawBody = await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    if (
      typeof rawBody !== "object" ||
      rawBody === null ||
      Array.isArray(rawBody)
    ) {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const body = rawBody as RequestBody;

    const transactionType = parseTransactionType(body);

    const isReversal =
      transactionType === "gold_inventory_purchase_reversal";

    let quantityGrams: number | null = null;
    let pricePerGram: number | null = null;
    let currency: string | null = null;
    let barSerialNumber: string | null = null;
    let documentNumber: string | null = null;

    if (!isReversal) {
      quantityGrams = requiredPositiveNumber(
        body.quantity_grams ?? body.quantityGrams,
        "INVALID_GOLD_QUANTITY",
      );

      pricePerGram = requiredPositiveNumber(
        body.price_per_gram ?? body.pricePerGram,
        "INVALID_GOLD_PRICE",
      );

      currency = optionalString(
        body.currency ?? body.currency_code,
      )?.toLowerCase() ?? null;

      if (!currency) {
        throw new AppError(
          "CURRENCY_REQUIRED",
          400,
        );
      }

      barSerialNumber = optionalString(
        body.bar_serial_number ?? body.barSerialNumber,
      );

      if (!barSerialNumber) {
        throw new AppError(
          "BAR_SERIAL_NUMBER_REQUIRED",
          400,
        );
      }
    } else {
      documentNumber = optionalString(
        body.document_number ?? body.documentNumber,
      );

      if (!documentNumber) {
        throw new AppError(
          "DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL",
          400,
        );
      }
    }

    /*
     * This user-scoped RPC authorizes finance before any
     * external blockchain calls are made.
     */
  const {
    data: configurationData,
    error: configurationError,
  } = await supabase.rpc(
    "fetch_active_supported_blockchains",
  );

    if (configurationError) {
      console.error(
        "GOLD_INVENTORY_BLOCKCHAINS_RPC_FAILED",
        {
          code: configurationError.code,
          message: configurationError.message,
          details: configurationError.details,
          hint: configurationError.hint,
        },
      );

      throw new AppError(
        configurationError.message ||
          "GOLD_INVENTORY_BLOCKCHAINS_FETCH_FAILED",
        configurationError.code === "42501" ? 403 : 500,
      );
    }

    const blockchains = parseBlockchains(
      configurationData,
    );

    const tokenTotalSupply =
      await fetchCombinedTokenSupply(blockchains);

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ||
      request.headers.get("x-real-ip")?.trim() ||
      "unknown";

    const { data, error } = await supabase.rpc(
      "execute_my_gold_inventory_purchase",
      {
        p_transaction_type: transactionType,

        /*
         * Generated types represent numeric as number.
         * The runtime value remains an exact decimal string
         * for PostgreSQL numeric input.
         */
        p_token_total_supply:
          tokenTotalSupply as unknown as number,

        p_quantity_grams: quantityGrams,
        p_price_per_gram: pricePerGram,
        p_currency_code: currency,
        p_bar_serial_number: barSerialNumber,

        p_supplier_name: optionalString(
          body.supplier_name ?? body.supplierName,
        ),

        p_custodian_name: optionalString(
          body.custodian_name ?? body.custodianName,
        ),

        p_document_number: documentNumber,
        p_ip_address: ipAddress,
      },
    );

    if (error) {
      console.error(
        "GOLD_INVENTORY_PURCHASE_RPC_FAILED",
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

    if (data === null || data === undefined) {
      throw new AppError(
        "GOLD_INVENTORY_PURCHASE_RESULT_NOT_FOUND",
        500,
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