import {
  FinancialActivityType,
} from "../types/financial-activity-type.ts";

export type RecordFinancialActivityInput = {
  reference: string;
  userId: string;
  countryCode: string;
  currencyCode: string;

  transactionType: string;
  activityType: FinancialActivityType;

  amount: string;
  amountUsd: string;

  cashAmount?: string;
  cashAmountUsd?: string;

  goldQuantity?: string;
  investmentCostUsd?: string;

  principalAmount?: string;
  principalAmountUsd?: string;

  interestAmount?: string;
  interestAmountUsd?: string;
};