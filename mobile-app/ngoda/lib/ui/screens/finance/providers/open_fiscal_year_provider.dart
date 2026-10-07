import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/finance/notifier/open_fiscal_year_notifier.dart';
import 'package:ngoda/ui/screens/finance/state/open_fiscal_year_state.dart';

final openFiscalYearProvider =
    NotifierProvider<OpenFiscalYearNotifier, OpenFiscalYearState>(
      OpenFiscalYearNotifier.new,
    );
