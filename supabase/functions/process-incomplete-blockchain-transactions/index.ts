// Replace supabase/functions/process-incomplete-blockchain-transactions/index.ts
import { AppError } from "../../_shared/app-error.ts";
import { errorResponse, successResponse } from "../../_shared/api-response.ts";
import { authenticateRequest, createSupabaseServiceClient } from "../../_shared/supabase-client.ts";
import { sendPushNotification } from "../../_shared/push-notification.ts";
import type { Json } from "../../_shared/database.types.ts";
import { getAddress, parseUnits } from "ethers";
import { createBlockchainReadClient } from "../../_shared/blockchain/client.ts";

type Obj = Record<string, unknown>;
function object(value: unknown): value is Obj {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function text(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) throw new AppError(`RECOVERY_INVALID_${field}`,400);
  return value.trim();
}
function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (object(error) && typeof error.message === "string") return error.message;
  return "INCOMPLETE_BLOCKCHAIN_RECOVERY_FAILED";
}
function sanitize(value: unknown): unknown {
  if (!object(value)) return value;
  const { device_tokens: _tokens, notification: _notification,
    push_title: _title, push_body: _body, push_reference: _reference, ...safe } = value;
  return safe;
}
// Each trade selects its own saved participants. Neither verifier calls the other.
async function verifyGoldBuy(context: Obj): Promise<void> {
  const snapshot = context.snapshot;
  if (!object(snapshot) || !object(snapshot.preparation)) {
    throw new AppError("GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED", 400);
  }
  const saved = snapshot.preparation;
  const sender = getAddress(text(saved.treasury_wallet_address, "SENDER"));
  const receiver = getAddress(text(saved.user_wallet_address, "RECEIVER"));
  await verifyConfirmedTokenTransfer(context, {
    sender,
    receiver,
    feeRecipient: sender,
    quantity: text(saved.token_quantity, "SAVED_QUANTITY"),
  });
}

async function verifyGoldSell(context: Obj): Promise<void> {
  const snapshot = context.snapshot;
  if (!object(snapshot) || !object(snapshot.preparation)) {
    throw new AppError("GOLD_SELL_PREPARATION_MISSING_RECONCILIATION_REQUIRED", 400);
  }
  const saved = snapshot.preparation;
  const sender = getAddress(text(saved.seller_wallet_address, "SENDER"));
  const receiver = getAddress(text(saved.treasury_wallet_address, "RECEIVER"));
  await verifyConfirmedTokenTransfer(context, {
    sender,
    receiver,
    feeRecipient: receiver,
    quantity: text(saved.token_quantity, "SAVED_QUANTITY"),
  });
}

type ExpectedTokenTransfer = {
  sender: string;
  receiver: string;
  feeRecipient: string;
  quantity: string;
};

// General chain-evidence validation only: no pricing, posting or transaction submission.
async function verifyConfirmedTokenTransfer(
  context: Obj,
  expected: ExpectedTokenTransfer,
): Promise<void> {
  const { sender, receiver, feeRecipient } = expected;
  if (getAddress(text(context.sender, "RECORDED_SENDER")) !== sender ||
      getAddress(text(context.receiver, "RECORDED_RECEIVER")) !== receiver) {
    throw new AppError("BLOCKCHAIN_PARTICIPANT_MISMATCH", 400);
  }
  const chainId = BigInt(text(context.chain_id, "CHAIN_ID"));
  const chainIdNumber = Number(chainId);
  if (!Number.isSafeInteger(chainIdNumber) || chainIdNumber <= 0) {
    throw new AppError("INVALID_BLOCKCHAIN_CHAIN_ID", 400);
  }
  const contractAddress = getAddress(text(context.contract_address, "CONTRACT_ADDRESS"));
  const hash = text(context.tx_hash, "TRANSACTION_HASH");
  const snapshot = object(context.snapshot) ? context.snapshot : {};
  const chain = object(snapshot.blockchain) ? snapshot.blockchain : {};
  const blockchain = {
    code: text(context.blockchain_code, "BLOCKCHAIN_CODE"),
    chain_id: chainIdNumber,
    rpc_url: text(context.rpc_url, "RPC_URL"),
    contract_address: contractAddress,
    native_currency_code: typeof chain.native_currency_code === "string"
      ? chain.native_currency_code : "",
    explorer_url: typeof chain.explorer_url === "string" ? chain.explorer_url : "",
  };
  const { provider, contract } = createBlockchainReadClient(blockchain);
  try {
    // All ABI decoding uses the existing shared contract interface.
    if (!contract.interface.getFunction("transferWithPermitAndFee")) {
      throw new AppError("SHARED_TOKEN_ABI_INCOMPLETE", 500);
    }
    if ((await provider.getNetwork()).chainId !== chainId) {
      throw new AppError("BLOCKCHAIN_NETWORK_MISMATCH", 400);
    }
    const [receipt, transaction, decimalsRaw] = await Promise.all([
      provider.getTransactionReceipt(hash),
      provider.getTransaction(hash),
      contract.decimals(),
    ]);
    if (!receipt) throw new AppError("BLOCKCHAIN_TRANSACTION_NOT_CONFIRMED", 409);
    if (receipt.status !== 1) throw new AppError("BLOCKCHAIN_TRANSACTION_REVERTED", 400);
    if (!transaction || !transaction.to || !receipt.to ||
        getAddress(transaction.to) !== contractAddress || getAddress(receipt.to) !== contractAddress ||
        transaction.chainId !== chainId || transaction.value !== 0n ||
        receipt.hash.toLowerCase() !== hash.toLowerCase()) {
      throw new AppError("BLOCKCHAIN_TRANSACTION_MISMATCH", 400);
    }
    const decimals = Number(decimalsRaw);
    if (!Number.isSafeInteger(decimals) || decimals < 0 || decimals > 255) {
      throw new AppError("INVALID_TOKEN_DECIMALS", 400);
    }
    const quantity = parseUnits(expected.quantity, decimals);
    if (quantity <= 0n || parseUnits(text(context.quantity, "RECORDED_QUANTITY"), decimals) !== quantity) {
      throw new AppError("BLOCKCHAIN_QUANTITY_MISMATCH", 400);
    }
    const call = contract.interface.parseTransaction({ data: transaction.data, value: transaction.value });
    // Positional fields use the existing ABI regardless of parameter labels.
    if (!call || call.name !== "transferWithPermitAndFee" ||
        getAddress(call.args[0]) !== sender || getAddress(call.args[1]) !== receiver ||
        getAddress(call.args[2]) !== feeRecipient ||
        BigInt(call.args[3]) !== quantity || BigInt(call.args[4]) !== 0n) {
      throw new AppError("BLOCKCHAIN_TRANSFER_CALL_MISMATCH", 400);
    }
  } finally {
    provider.destroy();
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  let id: string | null=null;
  let postingCommitted=false;
  try {
    if (request.method!=="POST") throw new AppError("METHOD_NOT_ALLOWED",405);
    const {supabase,userId}=await authenticateRequest(request);
    let body: unknown;
    try { body=await request.json(); } catch { throw new AppError("INVALID_REQUEST_BODY",400); }
    if (!object(body)) throw new AppError("INVALID_REQUEST_BODY",400);
    id=text(body.id,"BLOCKCHAIN_TRANSACTION_ID");
    const ip=request.headers.get("x-forwarded-for") || request.headers.get("x-real-ip") || "unknown";
    const {data:context,error:contextError}=await supabase.rpc(
      "fetch_my_blockchain_recovery_context",{p_blockchain_transaction_id:id},
    );
    if (contextError) {
      console.error("RECOVERY_CONTEXT_RPC_FAILED",{id,...contextError});
      throw new AppError(contextError.message,contextError.code==="42501"?403:400);
    }
    if (!object(context)) throw new AppError("INVALID_RECOVERY_CONTEXT",500);

    // Other transaction types retain their existing RPC behavior for now.
    if (context.transaction_type!=="gold_token_buy" && context.transaction_type!=="gold_token_sell") {
      const {data,error}=await supabase.rpc("process_my_incomplete_blockchain_transaction",{
        p_blockchain_transaction_id:id,p_ip_address:ip,
      });
      if (error) {
        console.error("INCOMPLETE_BLOCKCHAIN_POSTING_RPC_FAILED",{id,...error});
        throw new AppError(error.message,error.code==="42501"?403:400);
      }
      postingCommitted=true;
      return successResponse(sanitize(data));
    }

    const service=createSupabaseServiceClient();
    let data: unknown;
    if (context.transaction_type === "gold_token_buy") {
      await verifyGoldBuy(context);
      const result = await service.rpc("complete_verified_gold_buy_recovery", {
        p_executor_id:userId,p_blockchain_transaction_id:id,
        p_verified_context:context as Json,p_ip_address:ip,
      });
      if (result.error) {
        console.error("GOLD_BUY_RECOVERY_COMPLETION_RPC_FAILED",{id,...result.error});
        throw new AppError(result.error.message,result.error.code==="42501"?403:400);
      }
      data=result.data;
    } else {
      await verifyGoldSell(context);
      const result = await service.rpc("complete_verified_gold_sell_recovery", {
        p_executor_id:userId,p_blockchain_transaction_id:id,
        p_verified_context:context as Json,p_ip_address:ip,
      });
      if (result.error) {
        console.error("GOLD_SELL_RECOVERY_COMPLETION_RPC_FAILED",{id,...result.error});
        throw new AppError(result.error.message,result.error.code==="42501"?403:400);
      }
      data=result.data;
    }
    postingCommitted=true;
    // Notification failure must not undo or report failure for committed posting.
    if (object(data) && Array.isArray(data.device_tokens) && data.device_tokens.length>0 &&
        typeof data.push_title==="string" && typeof data.push_body==="string") {
      try {
        await sendPushNotification({
          tokens:data.device_tokens.filter((v):v is string=>typeof v==="string"),
          title:data.push_title,body:data.push_body,
          data:{reference:typeof data.push_reference==="string"?data.push_reference:""},
        });
      } catch (error) { console.error("RECOVERY_PUSH_FAILED",{id,error:message(error)}); }
    }
    return successResponse(sanitize(data));
  } catch (error) {
    console.error("INCOMPLETE_BLOCKCHAIN_POSTING_ERROR",{id,postingCommitted,error:message(error)});
    return errorResponse(error instanceof AppError?error:new AppError(message(error),500));
  }
});


// // Replace supabase/functions/process-incomplete-blockchain-transactions/index.ts
// import { AppError } from "../../_shared/app-error.ts";
// import { errorResponse, successResponse } from "../../_shared/api-response.ts";
// import { authenticateRequest, createSupabaseServiceClient } from "../../_shared/supabase-client.ts";
// import { sendPushNotification } from "../../_shared/push-notification.ts";
// import type { Json } from "../../_shared/database.types.ts";
// import { Contract, Interface, JsonRpcProvider, getAddress, parseUnits, type Log } from "ethers";

// type Obj = Record<string, unknown>;
// function object(value: unknown): value is Obj {
//   return typeof value === "object" && value !== null && !Array.isArray(value);
// }
// function text(value: unknown, field: string): string {
//   if (typeof value !== "string" || !value.trim()) throw new AppError(`RECOVERY_INVALID_${field}`,400);
//   return value.trim();
// }
// function message(error: unknown): string {
//   if (error instanceof Error) return error.message;
//   if (object(error) && typeof error.message === "string") return error.message;
//   return "INCOMPLETE_BLOCKCHAIN_RECOVERY_FAILED";
// }
// function sanitize(value: unknown): unknown {
//   if (!object(value)) return value;
//   const { device_tokens: _tokens, notification: _notification,
//     push_title: _title, push_body: _body, push_reference: _reference, ...safe } = value;
//   return safe;
// }
// const abi = new Interface([
//   "function transferWithPermitAndFee(address owner,address to,address treasury,uint256 amount,uint256 fee,uint256 deadline,uint8 v,bytes32 r,bytes32 s) returns (bool)",
//   "event Transfer(address indexed from,address indexed to,uint256 value)",
// ]);

// // This function only reads the chain. It never signs or submits a transaction.
// async function verifyGoldBuy(context: Obj): Promise<void> {
//   const snapshot = context.snapshot;
//   if (!object(snapshot) || !object(snapshot.preparation)) {
//     throw new AppError("GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED",400);
//   }
//   const saved = snapshot.preparation;
//   const expected = text(saved.token_quantity,"SAVED_QUANTITY");
//   const sender = getAddress(text(saved.treasury_wallet_address,"SENDER"));
//   const receiver = getAddress(text(saved.user_wallet_address,"RECEIVER"));
//   if (getAddress(text(context.sender,"RECORDED_SENDER")) !== sender ||
//       getAddress(text(context.receiver,"RECORDED_RECEIVER")) !== receiver) {
//     throw new AppError("BLOCKCHAIN_PARTICIPANT_MISMATCH",400);
//   }
//   const chainId = BigInt(text(context.chain_id,"CHAIN_ID"));
//   const contractAddress = getAddress(text(context.contract_address,"CONTRACT_ADDRESS"));
//   const hash = text(context.tx_hash,"TRANSACTION_HASH");
//   const provider = new JsonRpcProvider(text(context.rpc_url,"RPC_URL"));
//   try {
//     if ((await provider.getNetwork()).chainId !== chainId) {
//       throw new AppError("BLOCKCHAIN_NETWORK_MISMATCH",400);
//     }
//     const [receipt, transaction, decimalsRaw] = await Promise.all([
//       provider.getTransactionReceipt(hash),
//       provider.getTransaction(hash),
//       new Contract(contractAddress,["function decimals() view returns (uint8)"],provider).decimals(),
//     ]);
//     if (!receipt) throw new AppError("BLOCKCHAIN_TRANSACTION_NOT_CONFIRMED",409);
//     if (receipt.status !== 1) throw new AppError("BLOCKCHAIN_TRANSACTION_REVERTED",400);
//     if (!transaction || !transaction.to || !receipt.to ||
//         getAddress(transaction.to)!==contractAddress || getAddress(receipt.to)!==contractAddress ||
//         transaction.chainId!==chainId || transaction.value!==0n ||
//         receipt.hash.toLowerCase()!==hash.toLowerCase()) {
//       throw new AppError("BLOCKCHAIN_TRANSACTION_MISMATCH",400);
//     }
//     const decimals=Number(decimalsRaw);
//     if (!Number.isSafeInteger(decimals) || decimals<0 || decimals>255) {
//       throw new AppError("INVALID_TOKEN_DECIMALS",400);
//     }
//     const quantity=parseUnits(expected,decimals);
//     if (quantity<=0n || parseUnits(text(context.quantity,"RECORDED_QUANTITY"),decimals)!==quantity) {
//       throw new AppError("BLOCKCHAIN_QUANTITY_MISMATCH",400);
//     }
//     const call=abi.parseTransaction({data:transaction.data,value:transaction.value});
//     if (!call || call.name!=="transferWithPermitAndFee" ||
//         getAddress(call.args.owner)!==sender || getAddress(call.args.to)!==receiver ||
//         getAddress(call.args.treasury)!==sender ||
//         BigInt(call.args.amount)!==quantity || BigInt(call.args.fee)!==0n) {
//       throw new AppError("BLOCKCHAIN_TRANSFER_CALL_MISMATCH",400);
//     }
//     const transfers=receipt.logs.flatMap((log: Log)=>{
//       if (getAddress(log.address)!==contractAddress) return [];
//       try {
//         const event=abi.parseLog({topics:[...log.topics],data:log.data});
//         return event?.name==="Transfer" ? [event] : [];
//       } catch { return []; }
//     });
//     if (transfers.length!==1 || getAddress(transfers[0].args.from)!==sender ||
//         getAddress(transfers[0].args.to)!==receiver ||
//         BigInt(transfers[0].args.value)!==quantity) {
//       throw new AppError("BLOCKCHAIN_TRANSFER_EVENT_MISMATCH",400);
//     }
//   } finally {
//     provider.destroy();
//   }
// }

// Deno.serve(async (request: Request): Promise<Response> => {
//   let id: string | null=null;
//   let postingCommitted=false;
//   try {
//     if (request.method!=="POST") throw new AppError("METHOD_NOT_ALLOWED",405);
//     const {supabase,userId}=await authenticateRequest(request);
//     let body: unknown;
//     try { body=await request.json(); } catch { throw new AppError("INVALID_REQUEST_BODY",400); }
//     if (!object(body)) throw new AppError("INVALID_REQUEST_BODY",400);
//     id=text(body.id,"BLOCKCHAIN_TRANSACTION_ID");
//     const ip=request.headers.get("x-forwarded-for") || request.headers.get("x-real-ip") || "unknown";
//     const {data:context,error:contextError}=await supabase.rpc(
//       "fetch_my_blockchain_recovery_context",{p_blockchain_transaction_id:id},
//     );
//     if (contextError) {
//       console.error("RECOVERY_CONTEXT_RPC_FAILED",{id,...contextError});
//       throw new AppError(contextError.message,contextError.code==="42501"?403:400);
//     }
//     if (!object(context)) throw new AppError("INVALID_RECOVERY_CONTEXT",500);

//     // Other transaction types retain their existing RPC behavior for now.
//     if (context.transaction_type!=="gold_token_buy") {
//       const {data,error}=await supabase.rpc("process_my_incomplete_blockchain_transaction",{
//         p_blockchain_transaction_id:id,p_ip_address:ip,
//       });
//       if (error) {
//         console.error("INCOMPLETE_BLOCKCHAIN_POSTING_RPC_FAILED",{id,...error});
//         throw new AppError(error.message,error.code==="42501"?403:400);
//       }
//       postingCommitted=true;
//       return successResponse(sanitize(data));
//     }

//     await verifyGoldBuy(context);
//     const service=createSupabaseServiceClient();
//     const {data,error}=await service.rpc("complete_verified_gold_buy_recovery",{
//       p_executor_id:userId,p_blockchain_transaction_id:id,
//       p_verified_context:context as Json,p_ip_address:ip,
//     });
//     if (error) {
//       console.error("GOLD_BUY_RECOVERY_COMPLETION_RPC_FAILED",{id,...error});
//       throw new AppError(error.message,error.code==="42501"?403:400);
//     }
//     postingCommitted=true;
//     // Notification failure must not undo or report failure for committed posting.
//     if (object(data) && Array.isArray(data.device_tokens) && data.device_tokens.length>0 &&
//         typeof data.push_title==="string" && typeof data.push_body==="string") {
//       try {
//         await sendPushNotification({
//           tokens:data.device_tokens.filter((v):v is string=>typeof v==="string"),
//           title:data.push_title,body:data.push_body,
//           data:{reference:typeof data.push_reference==="string"?data.push_reference:""},
//         });
//       } catch (error) { console.error("RECOVERY_PUSH_FAILED",{id,error:message(error)}); }
//     }
//     return successResponse(sanitize(data));
//   } catch (error) {
//     console.error("INCOMPLETE_BLOCKCHAIN_POSTING_ERROR",{id,postingCommitted,error:message(error)});
//     return errorResponse(error instanceof AppError?error:new AppError(message(error),500));
//   }
// });
