import 'package:ngoda/data_models/params/tax_entry_params.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_periodic_tax.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_tax_summary.dart';
import 'package:ngoda/data_models/reserve-bank/tax_period_drilldown.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReserveBankApiService {
  const ReserveBankApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'reserve-bank-dashboard',
      invalidResponseMessage: 'Invalid reserve bank dashboard response',
      method: HttpMethod.get,
    );
  }

  Future<ReserveBankTaxSummary> fetchTaxPayableSummary() async {
    final data = await _functions.invokeData(
      functionName: 'tax-payable-summary',
      invalidResponseMessage: 'Invalid tax payable summary response',
      method: HttpMethod.get,
    );

    return ReserveBankTaxSummary.fromJson(data);
  }

  Future<ReserveBankTaxBalancePeriod> fetchPeriodicTaxbalance(
    String currency,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'periodic-tax-balances',
      queryParameters: {'currency_code': currency},
      invalidResponseMessage: 'Invalid periodic tax balances response',
      method: HttpMethod.get,
    );

    return ReserveBankTaxBalancePeriod.fromJson(data);
  }

  Future<TaxPeriodDrilldown> fetchPeriodicTaxEntries(
    TaxEntryParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'tax-payable-entries',
      method: HttpMethod.get,
      queryParameters: params.toQueryParameters(),
      invalidResponseMessage: 'Invalid tax entries response',
    );

    return TaxPeriodDrilldown.fromJson(data);
  }
}
