/*
 * Run this migration by itself and allow it to commit before running
 * 02_merchant_payment_optional_contribution.sql.
 *
 * PostgreSQL enum values cannot be used safely by later statements until
 * the ALTER TYPE transaction has committed.
 */

alter type public."LoyaltyEventType"
    add value if not exists
    'merchant_payment_fee_contribution';




