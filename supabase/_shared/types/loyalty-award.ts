import type {
  GamificationEventStatus,
  LoyaltyEarningEventType,
} from "./loyalty-event-type.ts";


export type AwardLoyaltyPointsRequest = {
  idempotency_key?: unknown;
  idempotencyKey?: unknown;

  event_type?: unknown;
  eventType?: unknown;

  user_id?: unknown;
  userId?: unknown;

  source_reference?: unknown;
  sourceReference?: unknown;

  source_transaction_id?: unknown;
  sourceTransactionId?: unknown;

  transaction_type?: unknown;
  transactionType?: unknown;

  amount?: unknown;

  amount_usd?: unknown;
  amountUsd?: unknown;

  country_code?: unknown;
  countryCode?: unknown;

  currency_code?: unknown;
  currencyCode?: unknown;

  metadata?: unknown;
};


export type ParsedAwardLoyaltyPointsRequest = {
  idempotencyKey: string;
  eventType: LoyaltyEarningEventType;
  userId: string;
  sourceReference: string;
  sourceTransactionId: string | null;
  transactionType: string | null;
  amount: string | null;
  amountUsd: string | null;
  countryCode: string | null;
  currencyCode: string | null;
  metadata: Record<string, unknown>;
};


export type LoyaltyAwardResult = {
  success: boolean;
  idempotent_replay: boolean;
  event_id: string;
  event_status: GamificationEventStatus;
  user_id: string;
  event_type: LoyaltyEarningEventType;
  source_reference: string;
  rule_code?: string;
  calculated_points?: number;
  points_awarded: number;
  available_points?: number;
  tier_points?: number;
  lifetime_earned_points?: number;
  previous_level_code?: string;
  level_code?: string;
  level_changed?: boolean;
  ledger_id?: string;
  reason?: string | null;
};


export type ReverseLoyaltyPointsRequest = {
  original_event_id?: unknown;
  originalEventId?: unknown;

  idempotency_key?: unknown;
  idempotencyKey?: unknown;

  source_reference?: unknown;
  sourceReference?: unknown;

  metadata?: unknown;
};


export type ParsedReverseLoyaltyPointsRequest = {
  originalEventId: string;
  idempotencyKey: string;
  sourceReference: string;
  metadata: Record<string, unknown>;
};


export type LoyaltyReversalResult = {
  success: true;
  idempotent_replay: boolean;
  original_event_id: string;
  reversal_event_id: string;
  reversal_ledger_id: string;
  points_reversed: number;
  available_points: number;
  tier_points: number;
  previous_level_code?: string;
  level_code?: string;
  level_changed?: boolean;
};

