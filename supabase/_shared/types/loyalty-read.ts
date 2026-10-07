export type LoyaltyLevel = {
  code: string;
  name: string;
  min_tier_points: number;
  max_tier_points: number | null;
  sort_order: number;
  benefits: Record<string, unknown>;
};


export type LoyaltyProgress = {
  points_in_current_level: number;
  points_to_next_level: number;
  percent: number;
  is_highest_level: boolean;
};


export type LoyaltySummary = {
  user_id: string;
  account_id: string | null;
  available_points: number;
  tier_points: number;
  lifetime_earned_points: number;
  level: LoyaltyLevel;
  next_level: LoyaltyLevel | null;
  progress: LoyaltyProgress;
  last_event_at: string | null;
  updated_at: string | null;
};


export type LoyaltyLedgerEntry = {
  id: string;
  event_id: string | null;
  ledger_type:
    | "earn"
    | "redeem"
    | "reverse"
    | "expire"
    | "adjustment";
  event_type: string | null;
  points_delta: number;
  available_balance_after: number;
  tier_points_delta: number;
  tier_balance_after: number;
  source_reference: string | null;
  description: string | null;
  reversal_of_ledger_id: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};


export type Pagination = {
  page: number;
  page_size: number;
  total_entries: number;
  total_pages: number;
  has_previous: boolean;
  has_next: boolean;
};


export type LoyaltyLedgerPage = {
  rows: LoyaltyLedgerEntry[];
  pagination: Pagination;
};


export type GamificationNotification = {
  id: string;
  event_id: string | null;
  notification_type:
    | "points_earned"
    | "level_up"
    | "level_down"
    | "badge_awarded"
    | "challenge_completed"
    | "reward_available";
  points: number;
  title: string | null;
  subtitle: string | null;
  display_priority: number;
  payload: Record<string, unknown>;
  seen_at: string | null;
  displayed_at: string | null;
  created_at: string;
};


export type GamificationNotificationFeed = {
  rows: GamificationNotification[];
  count: number;
};


export type AcknowledgeGamificationNotificationRequest = {
  notification_id?: unknown;
  notificationId?: unknown;
  mark_seen?: unknown;
  markSeen?: unknown;
};


export type ParsedAcknowledgeGamificationNotificationRequest = {
  notificationId: string;
  markSeen: boolean;
};


export type AcknowledgeGamificationNotificationResult = {
  success: true;
  notification_id: string;
  displayed_at: string;
  seen_at: string | null;
};


export type LoyaltyBadge = {
  id: string;
  badge_code: string;
  name: string;
  description: string;
  category:
    | "wallet"
    | "gold"
    | "lending"
    | "community"
    | "merchant"
    | "agent";
  icon_key: string;
  sort_order: number;
  is_secret: boolean;
  user_badge_id: string | null;
  awarded_at: string | null;
  is_earned: boolean;
  current_value: number;
  target_value: number;
  progress_percent: number;
};


export type LoyaltyBadgeSummary = {
  total: number;
  earned: number;
  remaining: number;
};


export type LoyaltyBadgeCollection = {
  rows: LoyaltyBadge[];
  summary: LoyaltyBadgeSummary;
};
