import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/tax_entry_params.dart';
import 'package:ngoda/ui/screens/reserve-bank/reserve_bank_tax_entries_screen.dart';
import 'package:ngoda/ui/screens/reserve-bank/reserve_bank_tax_period_screen.dart';
import 'package:ngoda/ui/screens/reserve-bank/reserve_bank_tax_summary_screen.dart';

final List<GoRoute> reserveBankRoutes = [
  GoRoute(
    path: '/tax',
    builder: (_, _) => const ReserveBankTaxSummaryScreen(),
    routes: [_taxSnapshotRoute()],
  ),
];

GoRoute _taxSnapshotRoute() {
  return GoRoute(
    path: ':currency',
    pageBuilder: (_, state) {
      final currency = state.pathParameters['currency']!.trim().toLowerCase();

      return slidePage(ReserveBankTaxPeriodScreen(currency: currency), state);
    },
    routes: [
      GoRoute(
        path: 'tax-entry',
        pageBuilder: (_, state) {
          final params = state.extra as TaxEntryParams;

          return slidePage(ReserveBankTaxEntriesScreen(params: params), state);
        },
      ),
    ],
  );
}
