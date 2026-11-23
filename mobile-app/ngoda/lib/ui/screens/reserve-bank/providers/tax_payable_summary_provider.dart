import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_tax_summary.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_api_service_provider.dart';

final taxPayableSummaryProvider =
    FutureProvider.autoDispose<R<ReserveBankTaxSummary>>((ref) async {
      try {
        final api = ref.read(reserveBankApiServiceProvider);
        final response = await api.fetchTaxPayableSummary();
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
