import 'package:logging/logging.dart';

import 'package:ngoda/data_models/accounts/finance_document.dart';
import 'package:ngoda/data_models/commission/settlement_batch_data.dart';
import 'package:ngoda/data_models/commission/settlement_items_page.dart';
import 'package:ngoda/data_models/fee/transaction_config.dart';
import 'package:ngoda/data_models/finance/finance_summary.dart';
import 'package:ngoda/data_models/finance/finance_transaction_summary.dart';
import 'package:ngoda/data_models/finance/financial_statement_drilldown.dart';
import 'package:ngoda/data_models/finance/fiscal_period_summary.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/profit_and_loss.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance.dart';
import 'package:ngoda/data_models/gl/gl_balance_summary.dart';
import 'package:ngoda/data_models/gl/gl_drilldown.dart';
import 'package:ngoda/data_models/loan/liquidation/incomplete_liquidation_jobs.dart';
import 'package:ngoda/data_models/loan/liquidation/liquidated_loans_today.dart';
import 'package:ngoda/data_models/loan/liquidation/manual_review_liquidation.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/data_models/params/gl_entry_params.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/tax/tax_settlement_batch_data.dart';
import 'package:ngoda/data_models/tax/tax_settlement_items_page.dart';
import 'package:ngoda/data_models/transaction/transaction_v.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:ngoda/ui/functions/list_to_csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FinanceApiService {
  FinanceApiService(this._functions);

  final SupabaseFunctionService _functions;

  final Logger logger = Logger('FinanceApiService');

  Future<FinanceSummary> getFinanceSummary() async {
    final data = await _functions.invokeData(functionName: 'finance-dashboard');

    return FinanceSummary.fromJson(data);
  }

  Future<TrialBalance> fetchTrialBalance(
    FinancialStatementParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'trial-balance',
      method: HttpMethod.get,
      body: {
        'startDate': params.startDate,
        'endDate': params.endDate,
        'currency': null,
      },
    );

    return TrialBalance.fromJson(data);
  }

  Future<ProfitAndLoss> fetchProfitnLoss(
    FinancialStatementParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'profit-and-loss',
      method: HttpMethod.get,
      queryParameters: {
        'startDate': params.startDate,
        'endDate': params.endDate,
        'currency': '',
      },
    );

    return ProfitAndLoss.fromJson(data);
  }

  Future<BalanceSheet> fetchBalanceSheet(
    FinancialStatementParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'balance-sheet',
      method: HttpMethod.get,
      queryParameters: {'asOfDate': params.endDate},
    );

    return BalanceSheet.fromJson(data);
  }

  Future<FinanceTransactionSummary> getRecentTransactions(
    FinancialStatementParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'recent-transactions',
      method: HttpMethod.get,
      body: {
        'asOfDate': params.endDate,
        'endDate': params.endDate,
        'page': params.page,
        'pageSize': params.pageSize,
        if (params.currency != null && params.currency!.isNotEmpty)
          'currency': params.currency,
      },
    );

    return FinanceTransactionSummary.fromJson(data);
  }

  Future<GLBalanceSummary> fetchGlBalances() async {
    final data = await _functions.invokeData(
      functionName: 'gl-balances',
      method: HttpMethod.get,
    );

    return GLBalanceSummary.fromJson(data);
  }

  Future<PeriodicBalanceDrilldown> fetchGlEntries(GlEntryParams params) async {
    final queryParameters = <String, Object?>{
      'gl': params.gl,
      'currency': params.currency.toLowerCase(),
      'fiscalYear': params.fiscalYear,
      'period': params.period,
      'page': params.page,
      'pageSize': params.pageSize,
    };

    logger.info(
      'invoking gl-periodic-entries: '
      '$queryParameters',
    );

    final data = await _functions.invokeData(
      functionName: 'gl-periodic-entries',
      method: HttpMethod.get,
      queryParameters: queryParameters,
    );

    return PeriodicBalanceDrilldown.fromJson(data);
  }

  Future<GLDrilldown> fetchDrilldownGlBalance(
    GlDrilldownParams glParams,
  ) async {
    final gl = glParams.gl.trim();
    final currency = glParams.currency.trim();

    final data = await _functions.invokeData(
      functionName: 'gl-periodic-balances/$gl',
      method: HttpMethod.get,
      queryParameters: {'currency': currency},
      invalidResponseMessage: 'Invalid GL periodic balances response',
    );

    return GLDrilldown.fromJson(data);
  }

  Future<FinancialStatementDrilldown> fetchFinancialStatementEntries(
    FinancialStatementParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'financial-statement-gl-entries',
      method: HttpMethod.get,
      queryParameters: params.toDrilldownQueryParameters(),
    );

    return FinancialStatementDrilldown.fromJson(data);
  }

  Future<SettlementBatchData> fetchBatchSettlement(List<String> status) async {
    final statusCsv = listToCsv(status);

    final data = await _functions.invokeData(
      functionName: 'fetch-agent-commission-settlement-batchs',
      method: HttpMethod.get,
      queryParameters: {'status': statusCsv},
    );

    return SettlementBatchData.fromJson(data);
  }

  Future<SettlementItemsPage> fetchBatchSettlementItems(
    SettlementItemsParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-agent-commission-settlement-items',
      method: HttpMethod.get,
      queryParameters: params.toQueryParameters(),
    );

    return SettlementItemsPage.fromJson(data);
  }

  Future<TaxSettlementItemsPage> fetchTaxSettlementItems(
    SettlementItemsParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-government-tax-settlement-items',
      method: HttpMethod.get,
      queryParameters: params.toQueryParameters(),
    );

    return TaxSettlementItemsPage.fromJson(data);
  }

  Future<TaxSettlementBatchData> fetchTaxSettlementData(
    List<String> status,
  ) async {
    final statusCsv = listToCsv(status);

    final data = await _functions.invokeData(
      functionName: 'fetch-government-tax-settlement-batch',
      method: HttpMethod.get,
      queryParameters: {'status': statusCsv},
    );

    return TaxSettlementBatchData.fromJson(data);
  }

  Future<FinanceDocument> getFinanceDocument(String documentNumber) async {
    final data = await _functions.invokeData(
      functionName: 'financial-document',
      method: HttpMethod.get,
      queryParameters: {'documentNumber': documentNumber},
    );

    return FinanceDocument.fromJson(data);
  }

  Future<DateTime?> getLastAcrual() async {
    final data = await _functions.invokeData(
      functionName: 'loan-interest-accrual-date',
      method: HttpMethod.get,
    );

    final rawDate = data['last_accrual_run']?.toString();

    if (rawDate == null || rawDate.trim().isEmpty) {
      return null;
    }

    return DateTime.parse(rawDate);
  }

  Future<TransactionConfig> fetchTransactionsConfig() async {
    final data = await _functions.invokeData(
      functionName: 'transactions-config',
    );

    return TransactionConfig.fromJson(data);
  }

  Future<TransactionV> fetchTransactionV() async {
    final data = await _functions.invokeData(functionName: 'transactions-v');

    return TransactionV.fromJson(data);
  }

  Future<void> externalFunding({
    required double amount,
    required String currency,
  }) async {
    await _functions.invokeVoid(
      functionName: 'external-funding',
      body: {
        'amount': amount,
        'currency_code': currency,
        'transactionType': 'external_funding',
      },
    );
  }

  Future<void> reverseDocument({
    required String docNo,
    required String transactionType,
    required String edgeFunction,
  }) async {
    final revTransaction = '${transactionType}_reversal';

    logger.info('rev trx : $revTransaction');

    await _functions.invokeVoid(
      functionName: edgeFunction,
      body: {'documentNumber': docNo, 'transactionType': revTransaction},
    );
  }

  Future<void> customerDirectDeposit({
    required String email,
    required double amount,
    required String currency,
    required String reference,
  }) async {
    await _functions.invokeVoid(
      functionName: 'customer-direct-deposit',
      body: {
        'identifier': email,
        'amount': amount,
        'currency': currency,
        'reference': reference,
      },
    );
  }

  Future<void> goldPurchase({
    required double grams,
    required double price,
    required String currency,
    required String serial,
  }) async {
    await _functions.invokeVoid(
      functionName: 'gold-inventory-purchase',
      body: {
        'quantity_grams': grams,
        'price_per_gram': price,
        'currency': currency,
        'bar_serial_number': serial,
        'transactionType': 'gold_inventory_purchase',
      },
    );
  }

  Future<void> commissionPaymentBatchApproval({
    required String batchId,
    required String action,
  }) async {
    await _functions.invokeVoid(
      functionName: 'update-agent-commission-settlement-batch',
      body: {'batch_id': batchId, 'action': action},
    );
  }

  Future<void> taxPaymentBatchApproval({
    required String batchId,
    required String action,
  }) async {
    await _functions.invokeVoid(
      functionName: 'update-government-tax-settlement-batch',
      body: {'batch_id': batchId, 'action': action},
    );
  }

  Future<LiquidatedLoansToday> fetchLiquidatedLoans(
    LoanLiquidationParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-liquidated-loans',
      method: HttpMethod.get,
      queryParameters: {
        'liquidation_date': params.startDate,
        'page': params.page,
        'pageSize': params.pageSize,
      },
    );

    return LiquidatedLoansToday.fromJson(data);
  }

  Future<IncompleteBlockchainTransactions> fetchIncompleteLiquidationJobs(
    LoanLiquidationParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-incomplete-liquidation-jobs',
      method: HttpMethod.get,
      queryParameters: {'page': params.page, 'pageSize': params.pageSize},
    );

    return IncompleteBlockchainTransactions.fromJson(data);
  }

  Future<ManualReviewLiquidations> fetchLiquidationManualReviewJobs(
    LoanLiquidationParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-manual-review-liquidation-jobs',
      method: HttpMethod.get,
      queryParameters: {'page': params.page, 'pageSize': params.pageSize},
    );

    return ManualReviewLiquidations.fromJson(data);
  }

  Future<ManualReviewLiquidationDetail> fetchLiquidationManualReviewJob(
    String jobId,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-manual-review-liquidation-job',
      method: HttpMethod.get,
      queryParameters: {'jobId': jobId},
    );

    return ManualReviewLiquidationDetail.fromJson(data);
  }

  Future<void> reconcilManualReviewLiquidationJob({
    required String jobId,
    required String txHash,
  }) async {
    await _functions.invokeVoid(
      functionName: 'reconcile-manual-review-liquidation',
      body: {'job_id': jobId, 'tx_hash': txHash},
    );
  }

  Future<FiscalPeriodSummary> fetchFiscalPeriods() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-fiscal-periods',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid fiscal periods response',
    );

    return FiscalPeriodSummary.fromJson(data);
  }

  Future<void> openNextFiscalYear() async {
    await _functions.invokeVoid(
      functionName: 'open-fiscal-periods',
      method: HttpMethod.post,
    );
  }

  Future<void> closeFiscalYear({required int fiscalYear}) async {
    await _functions.invokeVoid(
      functionName: 'close-fiscal-periods',
      method: HttpMethod.post,
      body: {'fiscal_year': fiscalYear},
    );
  }
}
