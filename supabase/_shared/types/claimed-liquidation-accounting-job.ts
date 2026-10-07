/*
 * claim_country_liquidation_accounting_jobs()
 * returns only the information required to call
 * finalise_liquidation_accounting_job().
 *
 * The finalisation RPC fetches and validates the complete
 * liquidation job from PostgreSQL.
 */
export type ClaimedLiquidationAccountingJob = {
  job_id: string;
  country_code: string;
};