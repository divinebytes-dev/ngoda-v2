export type StoredSignedTokenTransfer = {
  owner: string;
  to: string;

  amount: string;
  fee: string;

  parsedAmount: string;
  parsedFee: string;

  nonce: string;
  deadline: string;

  v: number;
  r: string;
  s: string;
};