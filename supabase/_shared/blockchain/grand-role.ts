import {
  adminContract,
  blockchainConfig,
} from "./client.ts";

import {
  MINTER_ROLE,
  BURNER_ROLE,
} from "./roles.ts";

import {
  AppError,
} from "../app-error.ts";


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
) {
  const roleHash =
    getRoleHash(role);

  const account =
    blockchainConfig.treasuryAddress;

  /*
   * Do not submit another blockchain
   * transaction if the treasury already
   * has this role.
   */
  const alreadyGranted =
    await adminContract.hasRole(
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

  /*
   * adminContract is connected to the
   * administrator signer.
   *
   * The role itself is granted to the
   * treasury address.
   */
  const tx =
    await adminContract.grantRole(
      roleHash,
      account,
    );

  const receipt =
    await tx.wait();

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