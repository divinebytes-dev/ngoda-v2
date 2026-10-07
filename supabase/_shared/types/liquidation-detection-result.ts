export type LiquidationDetectionResult = {
  success: boolean;
  country_code: string;
  fiscal_year: number;
  period: number;
  gold_price: string;
  evaluated: number;
  detected: number;
  already_underway: number;
  skipped: number;
};
