import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/finance/providers/fiscal_periods_provider.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';
import 'package:ngoda/ui/screens/finance/state/open_fiscal_year_state.dart';

class OpenFiscalYearNotifier extends Notifier<OpenFiscalYearState> {
  @override
  OpenFiscalYearState build() {
    return const OpenFiscalYearState();
  }

  Future<bool> openFiscalYear() async {
    if (state.isLoading) {
      return false;
    }

    state = const OpenFiscalYearState(isLoading: true);

    try {
      final api = ref.read(financeApiServiceProvider);

      await api.openNextFiscalYear();

      state = const OpenFiscalYearState(isSuccess: true);

      ref.invalidate(fiscalPeriodsProvider);

      return true;
    } catch (error) {
      state = OpenFiscalYearState(error: error.toString());

      return false;
    }
  }

  Future<bool> closeFiscalYear({required int fiscalYear}) async {
    if (state.isLoading) {
      return false;
    }

    state = const OpenFiscalYearState(isLoading: true);

    try {
      final api = ref.read(financeApiServiceProvider);

      await api.closeFiscalYear(fiscalYear: fiscalYear);

      state = const OpenFiscalYearState(isSuccess: true);

      ref.invalidate(fiscalPeriodsProvider);

      return true;
    } catch (error) {
      state = OpenFiscalYearState(error: error.toString());

      return false;
    }
  }

  void reset() {
    state = const OpenFiscalYearState();
  }
}
