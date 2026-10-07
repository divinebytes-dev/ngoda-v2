import 'package:ngoda/data_models/agent/commission_summary.dart';
import 'package:ngoda/data_models/merchant/credit_agent_balance_drilldown.dart';
import 'package:ngoda/data_models/merchant/credit_agent_balance_report.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/data_models/params/mini_statement_params.dart';
import 'package:ngoda/data_models/params/wallet_entry_params.dart';
import 'package:ngoda/data_models/params/wallet_snapshot_params.dart';
import 'package:ngoda/data_models/payment/mini_statement.dart';
import 'package:ngoda/data_models/wallet/multi_wallet_balance_summary.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
import 'package:ngoda/data_models/wallet/wallet_periodic_balance.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MiniStatementApiService {
  const MiniStatementApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<MiniStatement> getMiniStatement(MiniStatementParams params) async {
    final data = await _functions.invokeData(
      functionName: 'wallet-mini-statement',
      body: {
        'start_date': params.startDate,
        'end_date': params.endDate,
        'currency_code': params.currency,
        'page': params.page,
        'page_size': params.pageSize,
      },
      invalidResponseMessage: 'Invalid mini statement response',
    );

    return MiniStatement.fromJson(data);
  }

  Future<MultiWalletBalanceSummary> getMultiWalletSummary() async {
    final data = await _functions.invokeData(
      functionName: 'multi-wallet-balances',
      invalidResponseMessage: 'Invalid multi wallet balance response',
    );

    return MultiWalletBalanceSummary.fromJson(data);
  }

  Future<WalletBalanceSummary> getWalletSummary() async {
    final data = await _functions.invokeData(
      functionName: 'single-wallet-balances',
      invalidResponseMessage: 'Invalid wallet balance response',
    );

    return WalletBalanceSummary.fromJson(data);
  }

  Future<WalletBalancePeriod> getWalletBalanceSnapshot(
    WalletSnapshotParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'wallet-balance-snapshot',
      body: {
        'currency_code': params.currency.trim().toLowerCase(),
        'wallet_owner': params.walletOwner.trim(),
      },
      invalidResponseMessage: 'Invalid wallet balance snapshot response',
    );

    return WalletBalancePeriod.fromJson(data);
  }

  Future<PeriodicBalanceDrilldown> getPeriodicWalletEntries(
    WalletEntryParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'periodic-wallet-entries',
      body: {
        'currency': params.currency,
        'walletOwner': params.walletOwner,
        'fiscalYear': params.fiscalYear,
        'period': params.period,
        'page': params.page,
        'pageSize': params.pageSize,
      },
      invalidResponseMessage: 'Invalid periodic wallet entries response',
    );

    return PeriodicBalanceDrilldown.fromJson(data);
  }

  Future<CreditAgentBalanceReport> getCreditAgentsBalances(
    CreditAgentBalanceParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-credit-agent-balances',
      method: HttpMethod.get,
      queryParameters: {'page': params.page, 'pageSize': params.pageSize},
      invalidResponseMessage: 'Invalid credit agent balances response',
    );

    return CreditAgentBalanceReport.fromJson(data);
  }

  Future<CreditAgentBalanceDrilldown> getCreditAgentBalanceDrilldown(
    CreditAgentBalanceParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-credit-agent-drilldown',
      method: HttpMethod.get,
      queryParameters: {
        'merchantId': params.merchantId,
        'currency': params.currency,
        'page': params.page,
        'pageSize': params.pageSize,
      },
      invalidResponseMessage: 'Invalid credit agent drilldown response',
    );

    return CreditAgentBalanceDrilldown.fromJson(data);
  }

  Future<CommissionSummary> fetchCommissionSummary() async {
    final data = await _functions.invokeData(
      functionName: 'agent-commission',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid commission summary response',
    );

    return CommissionSummary.fromJson(data);
  }
}
