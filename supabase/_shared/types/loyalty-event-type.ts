export const loyaltyEarningEventTypes = [
  "kyc_completed",
  "user_deposit",
  "user_transfer",
  "merchant_payment",
  "merchant_payment_fee_contribution",
  "gold_token_buy",
  "gold_token_sell",
  "loan_repayment",
  "loan_repayment_on_time_bonus",
  "referral_completed",
  "monthly_activity_bonus",
  "challenge_completed",
  "manual_adjustment",
] as const;


export type LoyaltyEarningEventType =
  typeof loyaltyEarningEventTypes[number];


export type GamificationEventStatus =
  | "pending"
  | "processing"
  | "completed"
  | "ignored"
  | "failed"
  | "reversed";
