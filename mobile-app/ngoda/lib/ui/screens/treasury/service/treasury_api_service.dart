import 'package:ngoda/data_models/gl/token_gl_summary.dart';
import 'package:ngoda/data_models/operations/blockchain/incomplete_blockchain_transaction.dart';
import 'package:ngoda/data_models/params/blockchain_transaction_params.dart';
import 'package:ngoda/data_models/treasury/treasury_balances.dart';
import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_snapshot_drill.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TreasuryApiService {
  TreasuryApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<TreasuryDashboard> getSummary() async {
    final data = await _functions.invokeData(
      functionName: 'treasury-dashboard',
      invalidResponseMessage: 'Invalid treasury dashboard response',
    );

    return TreasuryDashboard.fromJson(data);
  }

  Future<TreasuryBalances> fetchWalletBalanceSnapshot() async {
    final data = await _functions.invokeData(
      functionName: 'wallet-balance-snapshot',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid wallet balance snapshot response',
    );

    return TreasuryBalances.fromJson(data);
  }

  Future<IncompleteBlockchainTransactions>
  fetchIncompleteBlockchainTransactions(
    BlockchainTransactionParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-incomplete-blockchain-transactions',
      method: HttpMethod.get,
      queryParameters: {'page': params.page, 'pageSize': params.pageSize},
      invalidResponseMessage:
          'Invalid incomplete blockchain '
          'transactions response',
    );

    return IncompleteBlockchainTransactions.fromJson(data);
  }

  Future<WalletBalanceSnapshotDrill> fetchWalletBalanceSnapshotDrilldown(
    String currencyCode,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'wallet-balance-snapshot/$currencyCode',
      method: HttpMethod.get,
      invalidResponseMessage:
          'Invalid wallet balance snapshot '
          'drilldown response',
    );

    return WalletBalanceSnapshotDrill.fromJson(data);
  }

  Future<TokenGLSummary> fetchTokenGlBalances() async {
    final data = await _functions.invokeData(
      functionName: 'token-gl-balances',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid token GL balances response',
    );

    return TokenGLSummary.fromJson(data);
  }

  Future<void> executeTokenAdjustment({required String id}) async {
    await _functions.invokeVoid(
      functionName: 'gold-token-adjustment-execution',
      body: {'adjustment_request_id': id},
    );
  }

  Future<void> processIncompleteBlockchainTransaction({
    required String id,
  }) async {
    await _functions.invokeVoid(
      functionName: 'process-incomplete-blockchain-transactions',
      body: {'id': id},
    );
  }

  Future<void> fundAgent({
    required String email,
    required double amount,
    required String currency,
    required String reference,
  }) async {
    await _functions.invokeVoid(
      functionName: 'fund-agent',
      body: {
        'agent_identifier': email,
        'amount': amount,
        'currency': currency,
        'reference': reference,
      },
    );
  }

  Future<void> fundCreditAgent({
    required String email,
    required double amount,
    required String currency,
    required String reference,
  }) async {
    await _functions.invokeVoid(
      functionName: 'fund-credit-agent',
      body: {
        'merchant_identifier': email,
        'amount': amount,
        'currency': currency,
        'reference': reference,
      },
    );
  }

  Future<void> approveCreditAgent({required String email}) async {
    await _functions.invokeVoid(
      functionName: 'approve-credit-agent',
      body: {'merchant_identifier': email},
    );
  }
}
