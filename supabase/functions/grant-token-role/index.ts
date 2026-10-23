import {
  getAddress,
  isAddress,
  ZeroAddress,
  ZeroHash,
} from "ethers";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  authenticateRequest,
} from "../../_shared/supabase-client.ts";

import {
  createBlockchainClient,
  type BlockchainClientConfig,
} from "../../_shared/blockchain/client.ts";

import {
  MINTER_ROLE,
  BURNER_ROLE,
} from "../../_shared/blockchain/roles.ts";

export type TokenRole =
  | "MINTER_ROLE"
  | "BURNER_ROLE";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    },
  );
}

function getRoleHash(
  role: TokenRole,
): string {
  switch (role) {
    case "MINTER_ROLE":
      return MINTER_ROLE;

    case "BURNER_ROLE":
      return BURNER_ROLE;

    default:
      throw new AppError(
        "INVALID_ROLE",
        400,
      );
  }
}

function parseBlockchainConfig(
  value: unknown,
): BlockchainClientConfig {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CONFIGURATION",
      500,
    );
  }

  const row = value as Record<string, unknown>;

  if (
    typeof row.code !== "string" ||
    !row.code.trim() ||
    typeof row.chain_id !== "number" ||
    !Number.isSafeInteger(row.chain_id) ||
    row.chain_id <= 0 ||
    typeof row.rpc_url !== "string" ||
    !row.rpc_url.trim() ||
    typeof row.contract_address !== "string" ||
    !isAddress(row.contract_address) ||
    typeof row.native_currency_code !== "string" ||
    !row.native_currency_code.trim() ||
    typeof row.treasury_wallet_address !== "string" ||
    !isAddress(row.treasury_wallet_address)
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CONFIGURATION",
      500,
    );
  }

  const contractAddress = getAddress(
    row.contract_address,
  );

  const treasuryAddress = getAddress(
    row.treasury_wallet_address,
  );

  if (
    contractAddress === ZeroAddress ||
    treasuryAddress === ZeroAddress
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CONFIGURATION",
      500,
    );
  }

  return {
    code: row.code.trim().toLowerCase(),
    chain_id: row.chain_id,
    rpc_url: row.rpc_url.trim(),
    contract_address: contractAddress,
    native_currency_code:
      row.native_currency_code.trim(),

    treasury_wallet_address: treasuryAddress,
  };
}

export async function grantTokenRole({
  role,
  blockchain,
}: {
  role: TokenRole;
  blockchain: BlockchainClientConfig;
}) {
  const roleHash = getRoleHash(role);

  const client = createBlockchainClient(
    blockchain,
  );

  try {
    /*
     * Verify the RPC is connected to the configured chain.
     */
    const network = await client.provider.getNetwork();

    if (
      network.chainId !== BigInt(blockchain.chain_id)
    ) {
      throw new AppError(
        "BLOCKCHAIN_CHAIN_ID_MISMATCH",
        500,
      );
    }

    const contractCode =
      await client.provider.getCode(
        client.contractAddress,
      );

    if (contractCode === "0x") {
      throw new AppError(
        "TOKEN_CONTRACT_NOT_DEPLOYED",
        500,
      );
    }

    /*
     * Use only the database-configured treasury.
     * createBlockchainClient also verifies that this
     * matches the wallet derived from MINTER_INDEX.
     */
    const account = client.treasuryAddress;

    const alreadyGranted =
      await client.providerContract.hasRole(
        roleHash,
        account,
      );

    if (alreadyGranted) {
      return {
        blockchain_code: client.blockchainCode,
        chain_id: client.chainId,
        contract_address: client.contractAddress,
        role,
        account,
        already_granted: true,
        transaction_hash: null,
        block_number: null,
      };
    }

    /*
     * GLDW uses DEFAULT_ADMIN_ROLE to grant these roles.
     */
    const administratorAuthorized =
      await client.providerContract.hasRole(
        ZeroHash,
        client.adminAddress,
      );

    if (!administratorAuthorized) {
      throw new AppError(
        "BLOCKCHAIN_ADMIN_ROLE_REQUIRED",
        403,
      );
    }

    const tx = await client.adminContract.grantRole(
      roleHash,
      account,
    );

    console.log(
      "TOKEN_ROLE_GRANT_SUBMITTED",
      {
        blockchainCode: client.blockchainCode,
        contractAddress: client.contractAddress,
        role,
        account,
        transactionHash: tx.hash,
      },
    );

    const receipt = await tx.wait();

    if (!receipt) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_RECEIPT_NOT_FOUND",
        500,
      );
    }

    if (receipt.status !== 1) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_FAILED",
        500,
      );
    }

    const granted =
      await client.providerContract.hasRole(
        roleHash,
        account,
      );

    if (!granted) {
      throw new AppError(
        "TOKEN_ROLE_GRANT_NOT_CONFIRMED",
        500,
      );
    }

    return {
      blockchain_code: client.blockchainCode,
      chain_id: client.chainId,
      contract_address: client.contractAddress,
      role,
      account,
      already_granted: false,
      transaction_hash: receipt.hash,
      block_number: receipt.blockNumber,
    };
  } finally {
    client.provider.destroy();
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(
      null,
      {
        status: 204,
        headers: corsHeaders,
      },
    );
  }

  if (request.method !== "POST") {
    return jsonResponse(
      {
        success: false,
        message: "METHOD_NOT_ALLOWED",
      },
      405,
    );
  }

  try {
    const { supabase } =
      await authenticateRequest(request);

    let body: unknown;

    try {
      body = await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    if (
      typeof body !== "object" ||
      body === null ||
      Array.isArray(body)
    ) {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const input = body as Record<string, unknown>;

    const blockchainCode =
      typeof input.blockchain_code === "string"
        ? input.blockchain_code.trim().toLowerCase()
        : "";

    if (!blockchainCode) {
      throw new AppError(
        "BLOCKCHAIN_CODE_REQUIRED",
        400,
      );
    }

    if (
      input.role !== "MINTER_ROLE" &&
      input.role !== "BURNER_ROLE"
    ) {
      throw new AppError(
        "INVALID_ROLE",
        400,
      );
    }

    /*
     * User-scoped RPC verifies that the caller is admin.
     * No caller-supplied wallet address or RPC URL is used.
     */
    const { data, error } = await supabase.rpc(
      "fetch_token_role_grant_config",
      {
        p_blockchain_code: blockchainCode,
      },
    );

    if (error) {
      console.error(
        "FETCH_TOKEN_ROLE_GRANT_CONFIG_FAILED",
        {
          code: error.code,
          message: error.message,
          blockchainCode,
        },
      );

      throw new AppError(
        error.message ||
          "BLOCKCHAIN_CONFIGURATION_FETCH_FAILED",
        error.code === "42501" ? 403 : 400,
      );
    }

    const blockchain = parseBlockchainConfig(data);

    if (blockchain.code !== blockchainCode) {
      throw new AppError(
        "BLOCKCHAIN_CONFIGURATION_MISMATCH",
        500,
      );
    }

    const result = await grantTokenRole({
      role: input.role,
      blockchain,
    });

    return jsonResponse({
      success: true,
      message: "SUCCESS",
      data: result,
    });
  } catch (error: unknown) {
    const message =
      error instanceof Error
        ? error.message
        : "TOKEN_ROLE_GRANT_FAILED";

    console.error(
      "TOKEN_ROLE_GRANT_FAILED",
      { message },
    );

    const status =
      error instanceof AppError
        ? (
          error as AppError & {
            statusCode?: number;
            status?: number;
          }
        ).statusCode ??
          (
            error as AppError & {
              status?: number;
            }
          ).status ??
          500
        : 500;

    return jsonResponse(
      {
        success: false,
        message:
          error instanceof AppError
            ? message
            : "TOKEN_ROLE_GRANT_FAILED",
      },
      status,
    );
  }
});