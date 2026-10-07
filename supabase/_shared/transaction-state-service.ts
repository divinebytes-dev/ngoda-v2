// supabase/functions/_shared/transaction-state-service.ts

import type { Json } from "./database.types.ts";
import type { AppSupabaseClient } from "./supabase-client.ts";
import {
    TransactionStatus,
    TransactionType,
} from "./enums.ts";
import {TransactionData} from "./types/transaction_data.ts";
import { AppError } from "./app-error.ts";


export async function createTransaction(
    supabase: AppSupabaseClient,
    transaction: TransactionData,
    userId: string,
    countryCode: string,
    transactionType: TransactionType,
): Promise<string> {
  const transactionId = crypto.randomUUID();
  const now = new Date().toISOString();
const transactionJson: Json = {
  v: transaction.v,
  r: transaction.r,
  s: transaction.s,
  a: transaction.a,
  f: transaction.f,
  g: transaction.g,
  c: transaction.c,
  t: transaction.t,
  e: transaction.e,
  ms: transaction.ms,
};

  const { error } = await supabase
    .from("transaction_state")
    .insert({
      id: transactionId,
      reference: transaction.r,
      status: TransactionStatus.processing,
      transaction_type: transactionType,
      country_code: countryCode,
      transaction_data: transactionJson,

      // Authenticated sender
      created_by: userId,

      // Receiver ID
      user_id: transaction.s,

      // Required because these have no database defaults
      updated_at: now,
    });

  if (error) {
    if (error.code === "23505") {
      throw new AppError(
        "TRANSACTION_REPLAY",
        409,
      );
    }

    throw new AppError(error.message, 500);
  }

  return transactionId;
}

export async function updateTransactionState(
    supabase: AppSupabaseClient,
    transactionId: string,
    status: TransactionStatus,
    message?: string,
): Promise<void> {
    const { error } = await supabase
        .from("transaction_state")
        .update({
            status,
            message: message ?? null,
            updated_at: new Date().toISOString(),
        })
        .eq("id", transactionId);

    if (error) {
        throw new AppError(
            "TRANSACTION_STATE_UPDATE_FAILED");
    }
}