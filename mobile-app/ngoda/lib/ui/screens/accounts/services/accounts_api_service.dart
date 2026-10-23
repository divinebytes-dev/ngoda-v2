import 'package:ngoda/data_models/accounts/accounts_dashboard.dart';
import 'package:ngoda/data_models/commission/agents_commission_summary.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/profit_and_loss.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/tax/tax_settlement_batch_data.dart';
import 'package:ngoda/data_models/tax/tax_summary.dart';
import 'package:ngoda/data_models/treasury/token_adjustment.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountsApiService {
  const AccountsApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<AccountsDashboard> getAccountsSummary() async {
    final data = await _functions.invokeData(
      functionName: 'accounts-dashboard',
      invalidResponseMessage: 'Invalid accounts dashboard response',
    );

    return AccountsDashboard.fromJson(data);
  }

  Future<TrialBalance> fetchTrialBalance(
    FinancialStatementParams tbParams,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'trial-balance',
      method: HttpMethod.get,
      queryParameters: {
        'startDate': tbParams.startDate,
        'endDate': tbParams.endDate,
        'currency': '',
      },
      invalidResponseMessage: 'Invalid trial balance response',
    );

    return TrialBalance.fromJson(data);
  }

  Future<ProfitAndLoss> fetchProfitnLoss(
    FinancialStatementParams pnlParams,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'profit-and-loss',
      method: HttpMethod.get,
      queryParameters: {
        'startDate': pnlParams.startDate,
        'endDate': pnlParams.endDate,
        'currency': '',
      },
      invalidResponseMessage: 'Invalid profit and loss response',
    );

    return ProfitAndLoss.fromJson(data);
  }

  Future<BalanceSheet> fetchBalanceSheet(
    FinancialStatementParams bsParams,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'balance-sheet',
      method: HttpMethod.get,
      queryParameters: {'asOfDate': bsParams.endDate},
      invalidResponseMessage: 'Invalid balance sheet response',
    );

    return BalanceSheet.fromJson(data);
  }

  Future<AgentsCommissionSummary> fetchAgentsCommissionSummary() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-agent-commission-settlement-batch/draft',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid agent commission summary response',
    );

    return AgentsCommissionSummary.fromJson(data);
  }

  Future<TaxSummary> fetchGovernmentTaxSummary(List<String> status) async {
    /*
     * This method is intentionally not implemented
     * against SupabaseFunctionService yet.
     *
     * The supplied AccountsApiService still uses:
     *
     * /api/v1/admin/accounts/government/tax-summary
     *
     * No corresponding Edge Function name exists in
     * the supplied source, so we must not invent one.
     *
     * We will connect this method when we review the
     * Government Tax flow.
     */
    throw UnimplementedError(
      'Government tax summary Edge Function '
      'has not yet been migrated.',
    );
  }

  Future<AgentsCommissionSummary> fetchBatchSettlement(String status) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-agent-commission-settlement-batch',
      method: HttpMethod.get,
      queryParameters: {'status': status},
      invalidResponseMessage: 'Invalid agent commission settlement response',
    );

    return AgentsCommissionSummary.fromJson(data);
  }

  Future<TaxSettlementBatchData> fetchTaxSettlementData(
    List<String> status,
  ) async {
    final statusCsv = status.join(',');

    final data = await _functions.invokeData(
      functionName: 'fetch-government-tax-settlement-batch',
      method: HttpMethod.get,
      queryParameters: {'status': statusCsv},
      invalidResponseMessage: 'Invalid government tax settlement response',
    );

    return TaxSettlementBatchData.fromJson(data);
  }

  Future<TokenAdjustment> fetchTokenenAdjustmentData(String status) async {
    final data = await _functions.invokeList(
      functionName: 'fetch-token-adjustments',
      method: HttpMethod.get,
      queryParameters: {'status': status},
      invalidResponseMessage: 'Invalid token adjustments response',
    );

    if (data.isEmpty) {
      throw Exception('NO_DATA');
    }

    final first = data.first;

    if (first is! Map) {
      throw Exception('Invalid token adjustment response');
    }

    return TokenAdjustment.fromJson(Map<String, dynamic>.from(first));
  }

  Future<void> createPaymentBatch({
    required DateTime startDate,
    required DateTime endDate,
    required String currency,
  }) async {
    await _functions.invokeVoid(
      functionName: 'create-agent-commission-batch-payment',
      method: HttpMethod.post,
      body: {
        'start_date': DateFormatService.formatQueryDate(startDate),
        'end_date': DateFormatService.formatQueryDate(endDate),
        'currency_code': currency,
      },
    );
  }

  Future<void> createGovermentTaxPaymentBatch({
    required DateTime startDate,
    required DateTime endDate,
    required String currency,
  }) async {
    await _functions.invokeVoid(
      functionName: 'create-government-tax-settlement-batch',
      method: HttpMethod.post,
      body: {
        'start_date': DateFormatService.formatQueryDate(startDate),
        'end_date': DateFormatService.formatQueryDate(endDate),
        'currency_code': currency,
      },
    );
  }

  Future<void> appoveTokenAdjustment({
    required String id,
    required String status,
  }) async {
    await _functions.invokeVoid(
      functionName: 'approve-token-adjustment/${status.trim()}',
      method: HttpMethod.post,
      body: {'adjustment_request_id': id},
    );
  }

  Future<void> settleCommissionPaymentBatch({required String batchId}) async {
    await _functions.invokeVoid(
      functionName: 'settle-agent-commission-batch',
      method: HttpMethod.post,
      body: {'batch_id': batchId},
    );
  }

  Future<void> settleTaxPaymentBatch({required String batchId}) async {
    await _functions.invokeVoid(
      functionName: 'settle-government-tax-settlement-batch',
      method: HttpMethod.post,
      body: {'batch_id': batchId},
    );
  }

  Future<void> fundTreasury({
    required double amount,
    required String currency,
  }) async {
    await _functions.invokeVoid(
      functionName: 'fund-treasury',
      method: HttpMethod.post,
      body: {'amount': amount, "currency": currency},
    );
  }
}
