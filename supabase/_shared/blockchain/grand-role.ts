import {
  createBlockchainClient,
} from "./client.ts";

import {
  MINTER_ROLE,
  BURNER_ROLE,
} from "./roles.ts";

import {
  AppError,
} from "../app-error.ts";

import type {
  SupportedBlockchainConfig,
} from "../types/supported_blockchain_config.ts";

export type TokenRole =
  | "MINTER_ROLE"
  | "BURNER_ROLE";

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

export async function grantTokenRole(
  role: TokenRole,
  blockchain: SupportedBlockchainConfig & {
    treasury_wallet_address: string;
  },
) {
  const roleHash = getRoleHash(role);

  const client = createBlockchainClient(blockchain);

  const account = blockchain.treasury_wallet_address;

  const alreadyGranted =
    await client.adminContract.hasRole(
      roleHash,
      account,
    );

  if (alreadyGranted) {
    return {
      role,
      account,
      already_granted: true,
      transaction_hash: null,
    };
  }

  const tx =
    await client.adminContract.grantRole(
      roleHash,
      account,
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

  return {
    role,
    account,
    already_granted: false,
    transaction_hash: tx.hash,
    block_number: receipt.blockNumber,
  };
}