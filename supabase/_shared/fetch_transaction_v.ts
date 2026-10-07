import type { AppSupabaseClient } from "./supabase-client.ts";
import { AppError } from "./app-error.ts";

export async function fetchTransactionV(
    supabase: AppSupabaseClient,
    version: string,
): Promise<number> {
    const { data, error } = await supabase.rpc(
        "get_transaction_v",
        {
            p_v: version,
        },
    );

    if (error) {
        console.error("GET_TRANSACTION_V_ERROR", error);
        throw new AppError("TRANSACTION_VERSION_FETCH_FAILED");
    }

    return data;
}