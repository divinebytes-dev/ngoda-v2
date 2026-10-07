import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/data_models/params/gl_entry_params.dart';
import 'package:ngoda/ui/screens/finance/transactions/finance_document_screen.dart';
import 'package:ngoda/ui/screens/finance/transactions/gl_account_balances_screen.dart';
import 'package:ngoda/ui/screens/finance/transactions/gl_account_drilldown_screen.dart';
import 'package:ngoda/ui/screens/finance/transactions/gl_account_entries_screen.dart';
import 'package:ngoda/ui/screens/finance/transactions/recent_transaction_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/transaction_history_screen.dart';

final List<GoRoute> transactionRoutes = [
  GoRoute(
    path: '/transactions',
    pageBuilder: (_, state) {
      return slidePage(TransactionHistoryScreen(), state);
    },
  ),

  GoRoute(
    path: '/recent-transactions',
    pageBuilder: (_, state) {
      return slidePage(RecentTransactionScreen(), state);
    },
    routes: [
      GoRoute(
        path: ':documentNumber',
        pageBuilder: (_, state) {
          final documentNumber = state.pathParameters['documentNumber']!;

          return slidePage(
            FinanceDocumentScreen(documentNumber: documentNumber),
            state,
          );
        },
      ),
    ],
  ),

  GoRoute(
    path: '/gl-balances',
    pageBuilder: (_, state) {
      return slidePage(GlAccountBalancesScreen(), state);
    },
    routes: [
      GoRoute(
        path: ':account',
        pageBuilder: (_, state) {
          final params = state.extra as GlDrilldownParams;

          return slidePage(GlAccountDrilldownScreen(params: params), state);
        },
      ),
      GoRoute(
        path: ':account/entries',
        pageBuilder: (_, state) {
          final params = state.extra as GlEntryParams;

          return slidePage(GlAccountEntriesScreen(params: params), state);
        },
      ),
    ],
  ),
];
