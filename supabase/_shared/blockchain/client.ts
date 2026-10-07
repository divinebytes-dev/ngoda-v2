import {
  Contract,
  getAddress,
  isAddress,
  JsonRpcProvider,
  Wallet,
} from "ethers";

import type {
  TypedDataDomain,
  TypedDataField,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  deriveWallet,
} from "./wallet.ts";


const TOKEN_ABI = [
  /*
   * Token metadata and balances.
   */
  "function name() view returns (string)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function nonces(address owner) view returns (uint256)",

  /*
   * Access control.
   */
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function grantRole(bytes32 role, address account)",

  /*
   * Token supply adjustment.
   */
  "function mint(address to, uint256 amount)",
  "function burn(address from, uint256 amount)",

  /*
   * Relayed token transfer.
   */
  `function transferWithPermitAndFee(
    address owner,
    address to,
    address feeRecipient,
    uint256 amount,
    uint256 fee,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  )`,
];


function getRequiredEnvironment(
  name: string,
): string {
  const value =
    Deno.env.get(name)?.trim();

  if (!value) {
    throw new AppError(
      `ENV_${name}_MISSING`,
    );
  }

  return value;
}


function getRequiredAddress(
  name: string,
): string {
  const value =
    getRequiredEnvironment(name);

  if (!isAddress(value)) {
    throw new AppError(
      `INVALID_${name}`,
    );
  }

  return getAddress(value);
}


function getRequiredWalletIndex(
  name: string,
): number {
  const rawValue =
    getRequiredEnvironment(name);

  const walletIndex =
    Number(rawValue);

  if (
    !Number.isSafeInteger(
      walletIndex,
    ) ||
    walletIndex < 0
  ) {
    throw new AppError(
      `INVALID_${name}`,
    );
  }

  return walletIndex;
}


function validatePrivateKey(
  privateKey: string,
  errorCode: string,
): string {
  if (
    !/^0x[0-9a-fA-F]{64}$/.test(
      privateKey,
    )
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return privateKey;
}


/*
 * General blockchain configuration.
 */
const rpcUrl =
  getRequiredEnvironment(
    "BLOCKCHAIN_RPC_URL",
  );

const contractAddress =
  getRequiredAddress(
    "TOKEN_CONTRACT_ADDRESS",
  );

const configuredTreasuryAddress =
  getRequiredAddress(
    "TREASURY",
  );

const relayerPrivateKey =
  validatePrivateKey(
    getRequiredEnvironment(
      "RELAYER_PK",
    ),
    "INVALID_RELAYER_PRIVATE_KEY",
  );

const chainId =
  Number(
    getRequiredEnvironment(
      "BLOCKCHAIN_CHAIN_ID",
    ),
  );

if (
  !Number.isSafeInteger(chainId) ||
  chainId <= 0
) {
  throw new AppError(
    "INVALID_BLOCKCHAIN_CHAIN_ID",
  );
}


/*
 * Deterministic privileged wallets.
 */
const masterMnemonic =
  getRequiredEnvironment(
    "MASTER_MNEMONIC",
  );

const treasuryWalletIndex =
  getRequiredWalletIndex(
    "MINTER_INDEX",
  );

const adminWalletIndex =
  getRequiredWalletIndex(
    "ADMIN_INDEX",
  );


/*
 * The wallet historically called the minter is the treasury
 * blockchain wallet. It performs mint and burn transactions
 * and also holds the treasury token balance.
 */
const derivedTreasuryWallet =
  deriveWallet(
    masterMnemonic,
    treasuryWalletIndex,
  );

const treasuryPrivateKey =
  validatePrivateKey(
    derivedTreasuryWallet.privateKey,
    "INVALID_TREASURY_PRIVATE_KEY",
  );

const derivedTreasuryAddress =
  getAddress(
    derivedTreasuryWallet.address,
  );


/*
 * This is a critical conversion check.
 *
 * We must continue using the same treasury wallet that minted
 * the existing token supply. A different derived address must
 * never be granted replacement roles automatically.
 */
if (
  derivedTreasuryAddress !==
  configuredTreasuryAddress
) {
  throw new AppError(
    "TREASURY_DERIVED_ADDRESS_MISMATCH",
  );
}


/*
 * Derive the contract administrator separately.
 */
const derivedAdminWallet =
  deriveWallet(
    masterMnemonic,
    adminWalletIndex,
  );

const adminPrivateKey =
  validatePrivateKey(
    derivedAdminWallet.privateKey,
    "INVALID_ADMIN_PRIVATE_KEY",
  );

const adminAddress =
  getAddress(
    derivedAdminWallet.address,
  );


export const blockchainConfig = {
  rpcUrl,
  contractAddress,

  /*
   * This single address is:
   * - the treasury token holder;
   * - the mint transaction signer;
   * - the burn transaction signer.
   */
  treasuryAddress:
    configuredTreasuryAddress,

  adminAddress,
  chainId,
} as const;


/*
 * Shared provider.
 */
export const provider =
  new JsonRpcProvider(
    blockchainConfig.rpcUrl,
    blockchainConfig.chainId,
  );


/*
 * Read-only contract.
 */
export const providerContract =
  new Contract(
    blockchainConfig.contractAddress,
    TOKEN_ABI,
    provider,
  );


/*
 * Relayer wallet and contract.
 */
export const relayerSigner =
  new Wallet(
    relayerPrivateKey,
    provider,
  );

export const relayerAddress =
  getAddress(
    relayerSigner.address,
  );

const configuredRelayerAddress =
  Deno.env
    .get("RELAYER_ADDRESS")
    ?.trim();

if (configuredRelayerAddress) {
  if (
    !isAddress(
      configuredRelayerAddress,
    )
  ) {
    throw new AppError(
      "INVALID_RELAYER_ADDRESS",
    );
  }

  if (
    getAddress(
      configuredRelayerAddress,
    ) !== relayerAddress
  ) {
    throw new AppError(
      "RELAYER_ADDRESS_PRIVATE_KEY_MISMATCH",
    );
  }
}

export const relayerContract =
  new Contract(
    blockchainConfig.contractAddress,
    TOKEN_ABI,
    relayerSigner,
  );


/*
 * Treasury blockchain signer.
 *
 * This signer is derived using MASTER_MNEMONIC and
 * MINTER_INDEX, and its address has already been verified
 * against TREASURY.
 */
export const treasurySigner =
  new Wallet(
    treasuryPrivateKey,
    provider,
  );

if (
  getAddress(
    treasurySigner.address,
  ) !==
  blockchainConfig.treasuryAddress
) {
  throw new AppError(
    "TREASURY_SIGNER_ADDRESS_MISMATCH",
  );
}

export const treasuryContract =
  new Contract(
    blockchainConfig.contractAddress,
    TOKEN_ABI,
    treasurySigner,
  );


/*
 * Compatibility aliases.
 *
 * Existing shared files can continue importing minterSigner
 * and minterContract while the clearer treasury names are
 * adopted gradually.
 */
export const minterSigner =
  treasurySigner;

export const minterContract =
  treasuryContract;


/*
 * Administrator signer and contract.
 */
export const adminSigner =
  new Wallet(
    adminPrivateKey,
    provider,
  );

if (
  getAddress(
    adminSigner.address,
  ) !==
  blockchainConfig.adminAddress
) {
  throw new AppError(
    "ADMIN_SIGNER_ADDRESS_MISMATCH",
  );
}

export const adminContract =
  new Contract(
    blockchainConfig.contractAddress,
    TOKEN_ABI,
    adminSigner,
  );


/*
 * Permit configuration.
 */
export const permitDomain:
  TypedDataDomain = {
    name:
      "Golden Liberty Finance",

    version:
      "1",

    chainId:
      blockchainConfig.chainId,

    verifyingContract:
      blockchainConfig.contractAddress,
  };


export const permitTypes:
  Record<string, TypedDataField[]> = {
    Permit: [
      {
        name: "owner",
        type: "address",
      },
      {
        name: "spender",
        type: "address",
      },
      {
        name: "value",
        type: "uint256",
      },
      {
        name: "nonce",
        type: "uint256",
      },
      {
        name: "deadline",
        type: "uint256",
      },
    ],
  };


export async function getTokenDecimals():
  Promise<number> {
  const rawDecimals =
    await providerContract.decimals();

  const decimals =
    Number(rawDecimals);

  if (
    !Number.isSafeInteger(
      decimals,
    ) ||
    decimals < 0
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return decimals;
}

// import {
//   Contract,
//   getAddress,
//   isAddress,
//   JsonRpcProvider,
//   Wallet,
// } from "ethers";

// import type {
//   TypedDataDomain,
//   TypedDataField,
// } from "ethers";

// import {
//   AppError,
// } from "../app-error.ts";

// import {
//   deriveWallet,
// } from "./wallet.ts";


// const TOKEN_ABI = [
//   /*
//    * Token metadata and balances.
//    */
//   "function name() view returns (string)",
//   "function balanceOf(address account) view returns (uint256)",
//   "function decimals() view returns (uint8)",
//   "function totalSupply() view returns (uint256)",
//   "function nonces(address owner) view returns (uint256)",

//   /*
//    * Access control.
//    */
//   "function hasRole(bytes32 role, address account) view returns (bool)",
//   "function grantRole(bytes32 role, address account)",

//   /*
//    * Token supply adjustment.
//    */
//   "function mint(address to, uint256 amount)",
//   "function burn(address from, uint256 amount)",

//   /*
//    * Relayed transfer.
//    */
//   `function transferWithPermitAndFee(
//     address owner,
//     address to,
//     address feeRecipient,
//     uint256 amount,
//     uint256 fee,
//     uint256 deadline,
//     uint8 v,
//     bytes32 r,
//     bytes32 s
//   )`,
// ];


// function getRequiredEnvironment(
//   name: string,
// ): string {
//   const value =
//     Deno.env.get(name)?.trim();

//   if (!value) {
//     throw new AppError(
//       `ENV_${name}_MISSING`,
//     );
//   }

//   return value;
// }


// function getRequiredAddress(
//   name: string,
// ): string {
//   const value =
//     getRequiredEnvironment(name);

//   if (!isAddress(value)) {
//     throw new AppError(
//       `INVALID_${name}`,
//     );
//   }

//   return getAddress(value);
// }


// function getRequiredWalletIndex(
//   name: string,
// ): number {
//   const rawValue =
//     getRequiredEnvironment(name);

//   const walletIndex =
//     Number(rawValue);

//   if (
//     !Number.isSafeInteger(
//       walletIndex,
//     ) ||
//     walletIndex < 0
//   ) {
//     throw new AppError(
//       `INVALID_${name}`,
//     );
//   }

//   return walletIndex;
// }


// function validatePrivateKey(
//   privateKey: string,
//   errorCode: string,
// ): string {
//   if (
//     !/^0x[0-9a-fA-F]{64}$/.test(
//       privateKey,
//     )
//   ) {
//     throw new AppError(
//       errorCode,
//     );
//   }

//   return privateKey;
// }


// /*
//  * Required blockchain environment.
//  */
// const rpcUrl =
//   getRequiredEnvironment(
//     "BLOCKCHAIN_RPC_URL",
//   );

// const contractAddress =
//   getRequiredAddress(
//     "TOKEN_CONTRACT_ADDRESS",
//   );

// const treasuryAddress =
//   getRequiredAddress(
//     "TREASURY",
//   );

// const relayerPrivateKey =
//   validatePrivateKey(
//     getRequiredEnvironment(
//       "RELAYER_PK",
//     ),
//     "INVALID_RELAYER_PRIVATE_KEY",
//   );

// const chainId =
//   Number(
//     getRequiredEnvironment(
//       "BLOCKCHAIN_CHAIN_ID",
//     ),
//   );

// if (
//   !Number.isSafeInteger(chainId) ||
//   chainId <= 0
// ) {
//   throw new AppError(
//     "INVALID_BLOCKCHAIN_CHAIN_ID",
//   );
// }


// /*
//  * Privileged deterministic-wallet configuration.
//  */
// const masterMnemonic =
//   getRequiredEnvironment(
//     "MASTER_MNEMONIC",
//   );

// const minterIndex =
//   getRequiredWalletIndex(
//     "MINTER_INDEX",
//   );

// const adminIndex =
//   getRequiredWalletIndex(
//     "ADMIN_INDEX",
//   );


// /*
//  * Derive privileged wallets once.
//  */
// const derivedMinterWallet =
//   deriveWallet(
//     masterMnemonic,
//     minterIndex,
//   );

// const derivedAdminWallet =
//   deriveWallet(
//     masterMnemonic,
//     adminIndex,
//   );

// const minterPrivateKey =
//   validatePrivateKey(
//     derivedMinterWallet.privateKey,
//     "INVALID_MINTER_PRIVATE_KEY",
//   );

// const adminPrivateKey =
//   validatePrivateKey(
//     derivedAdminWallet.privateKey,
//     "INVALID_ADMIN_PRIVATE_KEY",
//   );

// const minterAddress =
//   getAddress(
//     derivedMinterWallet.address,
//   );

// const adminAddress =
//   getAddress(
//     derivedAdminWallet.address,
//   );


// export const blockchainConfig = {
//   rpcUrl,
//   contractAddress,
//   treasuryAddress,
//   minterAddress,
//   adminAddress,
//   chainId,
// } as const;


// /*
//  * Shared blockchain provider.
//  */
// export const provider =
//   new JsonRpcProvider(
//     blockchainConfig.rpcUrl,
//     blockchainConfig.chainId,
//   );


// /*
//  * Read-only token contract.
//  */
// export const providerContract =
//   new Contract(
//     blockchainConfig.contractAddress,
//     TOKEN_ABI,
//     provider,
//   );


// /*
//  * Relayer contract.
//  */
// export const relayerSigner =
//   new Wallet(
//     relayerPrivateKey,
//     provider,
//   );

// export const relayerAddress =
//   getAddress(
//     relayerSigner.address,
//   );

// const configuredRelayerAddress =
//   Deno.env
//     .get("RELAYER_ADDRESS")
//     ?.trim();

// if (configuredRelayerAddress) {
//   if (
//     !isAddress(
//       configuredRelayerAddress,
//     )
//   ) {
//     throw new AppError(
//       "INVALID_RELAYER_ADDRESS",
//     );
//   }

//   if (
//     getAddress(
//       configuredRelayerAddress,
//     ) !== relayerAddress
//   ) {
//     throw new AppError(
//       "RELAYER_ADDRESS_PRIVATE_KEY_MISMATCH",
//     );
//   }
// }

// export const relayerContract =
//   new Contract(
//     blockchainConfig.contractAddress,
//     TOKEN_ABI,
//     relayerSigner,
//   );


// /*
//  * Minter contract.
//  *
//  * This signer executes both mint and burn operations, matching
//  * the existing blockchain implementation.
//  */
// export const minterSigner =
//   new Wallet(
//     minterPrivateKey,
//     provider,
//   );

// if (
//   getAddress(
//     minterSigner.address,
//   ) !== minterAddress
// ) {
//   throw new AppError(
//     "MINTER_WALLET_DERIVATION_MISMATCH",
//   );
// }

// export const minterContract =
//   new Contract(
//     blockchainConfig.contractAddress,
//     TOKEN_ABI,
//     minterSigner,
//   );


// /*
//  * Administrator contract used for role management.
//  */
// export const adminSigner =
//   new Wallet(
//     adminPrivateKey,
//     provider,
//   );

// if (
//   getAddress(
//     adminSigner.address,
//   ) !== adminAddress
// ) {
//   throw new AppError(
//     "ADMIN_WALLET_DERIVATION_MISMATCH",
//   );
// }

// export const adminContract =
//   new Contract(
//     blockchainConfig.contractAddress,
//     TOKEN_ABI,
//     adminSigner,
//   );


// /*
//  * Permit configuration.
//  */
// export const permitDomain:
//   TypedDataDomain = {
//     name:
//       "Golden Liberty Finance",

//     version:
//       "1",

//     chainId:
//       blockchainConfig.chainId,

//     verifyingContract:
//       blockchainConfig.contractAddress,
//   };


// export const permitTypes:
//   Record<string, TypedDataField[]> = {
//     Permit: [
//       {
//         name: "owner",
//         type: "address",
//       },
//       {
//         name: "spender",
//         type: "address",
//       },
//       {
//         name: "value",
//         type: "uint256",
//       },
//       {
//         name: "nonce",
//         type: "uint256",
//       },
//       {
//         name: "deadline",
//         type: "uint256",
//       },
//     ],
//   };


// export async function getTokenDecimals():
//   Promise<number> {
//   const rawDecimals =
//     await providerContract.decimals();

//   const decimals =
//     Number(rawDecimals);

//   if (
//     !Number.isSafeInteger(
//       decimals,
//     ) ||
//     decimals < 0
//   ) {
//     throw new AppError(
//       "INVALID_TOKEN_DECIMALS",
//     );
//   }

//   return decimals;
// }