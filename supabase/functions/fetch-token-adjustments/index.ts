import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  getTotalSupply,
} from "../../_shared/blockchain/balances.ts";

import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

type TokenAdjustmentRecord = {
  id: string;
  document_number: string;
  adjustment_type: string;
  quantity: string | number;
  uom: string;
  status: string;
  description: string | null;
  available_gold: string | number;
};

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "Content-Type": "application/json",
      },
    },
  );
}

function successResponse(
  data: unknown,
): Response {
  return jsonResponse({
    success: true,
    data,
  });
}

function errorResponse(
  error: string,
  status = 400,
): Response {
  return jsonResponse(
    {
      success: false,
      error,
    },
    status,
  );
}

function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }

  return String(error);
}

function parseBlockchains(
  value: unknown,
): SupportedBlockchainConfig[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error(
      "ACTIVE_BLOCKCHAINS_NOT_FOUND",
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
      throw new Error(
        "INVALID_BLOCKCHAIN_CONFIGURATION",
      );
    }

    const row = item as Record<string, unknown>;

    if (
      typeof row.code !== "string" ||
      !row.code.trim() ||
      typeof row.chain_id !== "number" ||
      !Number.isSafeInteger(row.chain_id) ||
      row.chain_id <= 0 ||
      typeof row.rpc_url !== "string" ||
      !row.rpc_url.trim() ||
      typeof row.contract_address !== "string" ||
      !row.contract_address.trim() ||
      typeof row.native_currency_code !== "string" ||
      !row.native_currency_code.trim()
    ) {
      throw new Error(
        "INVALID_BLOCKCHAIN_CONFIGURATION",
      );
    }

    const code = row.code.trim().toLowerCase();

    const contractAddress =
      row.contract_address.trim();

    const contractKey =
      `${row.chain_id}:${contractAddress.toLowerCase()}`;

    if (
      seenCodes.has(code) ||
      seenContracts.has(contractKey)
    ) {
      throw new Error(
        "DUPLICATE_BLOCKCHAIN_CONFIGURATION",
      );
    }

    seenCodes.add(code);
    seenContracts.add(contractKey);

    return {
      code,
      chain_id: row.chain_id,
      rpc_url: row.rpc_url.trim(),
      contract_address: contractAddress,
      native_currency_code:
        row.native_currency_code.trim(),
    };
  });
}

/*
 * Combine token quantities without floating-point rounding.
 */
function sumDecimalAmounts(
  amounts: string[],
): string {
  let total = 0n;
  let totalScale = 0;

  for (const amount of amounts) {
    if (typeof amount !== "string") {
      throw new Error(
        "INVALID_TOKEN_TOTAL_SUPPLY",
      );
    }

    const value = amount.trim();

    if (!/^\d+(\.\d+)?$/.test(value)) {
      throw new Error(
        "INVALID_TOKEN_TOTAL_SUPPLY",
      );
    }

    const [whole, fraction = ""] = value.split(".");
    const scale = fraction.length;

    const units = BigInt(
      `${whole}${fraction}`,
    );

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

  return fraction
    ? `${whole}.${fraction}`
    : whole;
}

async function getCombinedTokenSupply(
  blockchains: SupportedBlockchainConfig[],
): Promise<string> {
  const results = await Promise.allSettled(
    blockchains.map(async (blockchain) => {
      const supply = await getTotalSupply(
        blockchain,
      );

      return supply.token_balance;
    }),
  );

  const supplies: string[] = [];
  let hasFailure = false;

  for (let index = 0; index < results.length; index++) {
    const result = results[index];

    if (result.status === "rejected") {
      hasFailure = true;

      console.error(
        "TOKEN_ADJUSTMENTS_SUPPLY_FETCH_FAILED",
        {
          blockchainCode: blockchains[index].code,
          chainId: blockchains[index].chain_id,
          error: getErrorMessage(result.reason),
        },
      );

      continue;
    }

    supplies.push(result.value);
  }

  /*
   * Do not display a partial total as the global supply.
   */
  if (hasFailure) {
    throw new Error(
      "TOKEN_TOTAL_SUPPLY_UNAVAILABLE",
    );
  }

  return sumDecimalAmounts(supplies);
}

async function getTokenAdjustmentsByStatus(
  request: Request,
  status: string,
): Promise<Array<Record<string, unknown>>> {
  const supabase = createSupabaseClient(
    request,
  );

  /*
   * This RPC must authorize the caller before returning
   * adjustments. Complete it before blockchain calls.
   */
  const adjustmentResult = await supabase.rpc(
    "fetch_token_adjustments_by_status",
    {
      p_status: status,
    },
  );

  if (adjustmentResult.error) {
    console.error(
      "TOKEN_ADJUSTMENTS_RPC_FAILED",
      {
        code: adjustmentResult.error.code,
        message: adjustmentResult.error.message,
        details: adjustmentResult.error.details,
        hint: adjustmentResult.error.hint,
        status,
      },
    );

    throw new Error(
      adjustmentResult.error.message,
    );
  }

  const adjustmentData =
    adjustmentResult.data ?? [];

  if (!Array.isArray(adjustmentData)) {
    throw new Error(
      "INVALID_TOKEN_ADJUSTMENTS_RESPONSE",
    );
  }

  const adjustments =
    adjustmentData as TokenAdjustmentRecord[];

  /*
   * No supply is needed when there are no records to return.
   */
  if (adjustments.length === 0) {
    return [];
  }

  const {
    data: configurationData,
    error: configurationError,
  } = await supabase.rpc(
    "fetch_active_supported_blockchains",
  );

  if (configurationError) {
    console.error(
      "TOKEN_ADJUSTMENTS_BLOCKCHAINS_RPC_FAILED",
      {
        code: configurationError.code,
        message: configurationError.message,
        details: configurationError.details,
        hint: configurationError.hint,
      },
    );

    throw new Error(
      configurationError.message,
    );
  }

  const blockchains = parseBlockchains(
    configurationData,
  );

  const totalTokens =
    await getCombinedTokenSupply(blockchains);

  return adjustments.map((adjustment) => ({
    ...adjustment,
    quantity: adjustment.quantity.toString(),
    available_gold:
      adjustment.available_gold.toString(),
    total_tokens: totalTokens,
  }));
}

Deno.serve(
  async (request: Request): Promise<Response> => {
    if (request.method !== "GET") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    try {
      const url = new URL(request.url);

      const status = url.searchParams
        .get("status")
        ?.trim()
        .toLowerCase();

      if (!status) {
        return errorResponse(
          "STATUS_IS_REQUIRED",
        );
      }

      const adjustments =
        await getTokenAdjustmentsByStatus(
          request,
          status,
        );

      console.log(
        "TOKEN_ADJUSTMENTS_FETCHED",
        {
          status,
          count: adjustments.length,
        },
      );

      return successResponse(adjustments);
    } catch (error) {
      const message = getErrorMessage(error);

      console.error(
        "TOKEN_ADJUSTMENTS_ERROR",
        { error: message },
      );

      if (
        message === "UNAUTHENTICATED" ||
        message === "UNAUTHORIZED"
      ) {
        return errorResponse(message, 401);
      }

      if (message === "FORBIDDEN") {
        return errorResponse(message, 403);
      }

      if (message === "TOKEN_TOTAL_SUPPLY_UNAVAILABLE") {
        return errorResponse(message, 503);
      }

      return errorResponse(
        message || "FAILED_TO_FETCH_ADJUSTMENTS",
        400,
      );
    }
  },
);