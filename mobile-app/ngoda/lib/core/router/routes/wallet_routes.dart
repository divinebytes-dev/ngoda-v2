import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/wallet_entry_params.dart';
import 'package:ngoda/ui/screens/wallet/reports/commission_summary_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/multi_wallet_balance_summary_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/wallet_balance_snapshot_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/wallet_balance_summary_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/wallet_periodic_drilldown_screen.dart';

final List<GoRoute> walletRoutes = [
  /*
   * Customer wallet.
   */
  _singleWalletRoute(path: '/customer-wallet'),

  /*
   * Treasury wallet.
   */
  _singleWalletRoute(path: '/treasury-wallet'),

  /*
   * Agent wallet.
   */
  _multiWalletRoute(path: '/agent-wallet'),

  /*
   * Vendor wallet.
   */
  _multiWalletRoute(path: '/vendor-wallet'),

  /*
   * Merchant wallet.
   */
  _multiWalletRoute(path: '/merchant-wallet'),

  GoRoute(
    path: '/commission-summary',
    pageBuilder: (_, state) {
      return slidePage(CommissionSummaryScreen(), state);
    },
  ),
];

GoRoute _singleWalletRoute({required String path}) {
  return GoRoute(
    path: path,
    builder: (_, _) => const WalletBalanceSummaryScreen(),
    routes: [_walletSnapshotRoute()],
  );
}

GoRoute _multiWalletRoute({required String path}) {
  return GoRoute(
    path: path,
    builder: (_, _) => const MultiWalletBalanceSummaryScreen(),
    routes: [_walletSnapshotRoute()],
  );
}

GoRoute _walletSnapshotRoute() {
  return GoRoute(
    path: ':walletOwner/:currency',
    pageBuilder: (_, state) {
      final walletOwner = state.pathParameters['walletOwner']!
          .trim()
          .toLowerCase();

      final currency = state.pathParameters['currency']!.trim().toLowerCase();

      return slidePage(
        WalletBalanceSnapshotScreen(
          currency: currency,
          walletOwner: walletOwner,
          blockchainCode: state.extra is String ? state.extra as String : null,
        ),
        state,
      );
    },
    routes: [
      GoRoute(
        path: 'wallet-entry',
        pageBuilder: (_, state) {
          final params = state.extra as WalletEntryParams;

          return slidePage(
            WalletPeriodicDrilldownScreen(params: params),
            state,
          );
        },
      ),
    ],
  );
}
