import {
  getAddress,
  isAddress,
  parseUnits,
  Signature,
  Wallet,
  ZeroAddress,
  MaxUint256,
} from "ethers";
import { AppError } from "../app-error.ts";
import {
  createPermitDomain,
  getTokenDecimals,
  type BlockchainClientConfig,
  createBlockchainClient,
} from "./client.ts";
import { deriveWallet, getWalletMnemonic } from "./wallet.ts";

export type BlockchainClient = ReturnType<typeof createBlockchainClient>;

export type SignedTokenTransfer = {
  owner: string;
  to: string;
  amount: string;
  fee: string;
  parsedAmount: bigint;
  parsedFee: bigint;
  nonce: bigint;
  deadline: bigint;
  v: number;
  r: string;
  s: string;
};

// Must match GLDW.TRANSFER_WITH_FEE_TYPEHASH exactly. The existing client.ts
// permitTypes describes standard ERC-2612 permits and is NOT used here.
export const transferAuthorizationTypes = {
  TransferWithFee: [
    { name: "owner", type: "address" },
    { name: "to", type: "address" },
    { name: "treasury", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "fee", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

export function buildTransferAuthorizationValue({
  owner, to, treasury, amount, fee, nonce, deadline,
}: {
  owner: string;
  to: string;
  treasury: string;
  amount: bigint;
  fee: bigint;
  nonce: bigint;
  deadline: bigint;
}) {
  return { owner, to, treasury, amount, fee, nonce, deadline };
}

export async function signTransfer({
  fromIndex, expectedOwner, to, amount, fee, client, blockchain,
}: {
  fromIndex: number;
  expectedOwner: string;
  to: string;
  amount: string;
  fee: string;
  client: BlockchainClient;
  blockchain: BlockchainClientConfig;
}): Promise<SignedTokenTransfer> {
  if (!Number.isSafeInteger(fromIndex) || fromIndex < 0) {
    throw new AppError("INVALID_WALLET_INDEX");
  }
  if (!isAddress(expectedOwner) || getAddress(expectedOwner) === ZeroAddress) {
    throw new AppError("INVALID_OWNER_ADDRESS");
  }
  if (!isAddress(to) || getAddress(to) === ZeroAddress) {
    throw new AppError("INVALID_RECEIVER_ADDRESS");
  }
  if (!isAddress(blockchain.treasury_wallet_address) ||
      getAddress(blockchain.treasury_wallet_address) === ZeroAddress) {
    throw new AppError("INVALID_TREASURY_ADDRESS");
  }
  if (client.blockchainCode !== blockchain.code ||
      client.chainId !== blockchain.chain_id ||
      client.contractAddress !== getAddress(blockchain.contract_address) ||
      getAddress(client.treasuryAddress) !== getAddress(blockchain.treasury_wallet_address)) {
    throw new AppError("BLOCKCHAIN_CLIENT_CONFIG_MISMATCH");
  }

  const normalizedOwner = getAddress(expectedOwner);
  const normalizedReceiver = getAddress(to);
  const normalizedTreasury = getAddress(blockchain.treasury_wallet_address);
  const derivedWallet = deriveWallet(getWalletMnemonic(), fromIndex);
  const derivedAddress = getAddress(derivedWallet.address);
  if (derivedAddress !== normalizedOwner) {
    throw new AppError("DERIVED_WALLET_OWNER_MISMATCH");
  }

  const tokenDecimals = await getTokenDecimals(client.providerContract);
  let parsedAmount: bigint;
  let parsedFee: bigint;
  try {
    parsedAmount = parseUnits(amount, tokenDecimals);
    parsedFee = parseUnits(fee, tokenDecimals);
  } catch {
    throw new AppError("INVALID_TOKEN_AMOUNT");
  }
  if (parsedAmount <= 0n) throw new AppError("INVALID_TRANSFER_AMOUNT");
  if (parsedFee < 0n) throw new AppError("INVALID_TRANSFER_FEE");
  if (parsedAmount > MaxUint256 || parsedFee > MaxUint256 ||
      parsedAmount + parsedFee > MaxUint256) {
    throw new AppError("INVALID_TOKEN_AMOUNT");
  }

  const nonceRaw = await client.providerContract.nonces(derivedAddress);
  const nonce = BigInt(nonceRaw.toString());
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
  const authorization = buildTransferAuthorizationValue({
    owner: derivedAddress,
    to: normalizedReceiver,
    treasury: normalizedTreasury,
    amount: parsedAmount,
    fee: parsedFee,
    nonce,
    deadline,
  });
  const wallet = new Wallet(derivedWallet.privateKey);
  const signature = await wallet.signTypedData(
    createPermitDomain(blockchain),
    transferAuthorizationTypes,
    authorization,
  );
  const parsedSignature = Signature.from(signature);
  return {
    owner: derivedAddress,
    to: normalizedReceiver,
    amount,
    fee,
    parsedAmount,
    parsedFee,
    nonce,
    deadline,
    v: parsedSignature.v,
    r: parsedSignature.r,
    s: parsedSignature.s,
  };
}
