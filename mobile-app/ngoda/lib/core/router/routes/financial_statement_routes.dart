import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/ui/screens/finance/financial_statements/balance_sheet_screen.dart';
import 'package:ngoda/ui/screens/finance/financial_statements/financial_statement_entries_screen.dart';
import 'package:ngoda/ui/screens/finance/financial_statements/financial_statements_screen.dart';
import 'package:ngoda/ui/screens/finance/financial_statements/profit_and_loss_screen.dart';
import 'package:ngoda/ui/screens/finance/financial_statements/trial_balance_screen.dart';

final List<GoRoute> financialStatementRoutes = [
  GoRoute(
    path: '/financial-statements',
    builder: (_, _) => const FinancialStatementsScreen(),
    routes: [
      GoRoute(
        path: 'trial-balance',
        pageBuilder: (_, state) {
          return slidePage(const TrialBalanceScreen(), state);
        },
        routes: [
          GoRoute(
            path: 'entries',
            pageBuilder: (context, state) {
              final params = state.extra as FinancialStatementParams;

              return slidePage(
                FinancialStatementEntriesScreen(
                  params: params,
                  title: "Trial Balance",
                ),
                state,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: 'profit-loss',
        pageBuilder: (_, state) {
          return slidePage(const ProfitAndLossScreen(), state);
        },
        routes: [
          GoRoute(
            path: 'entries',
            pageBuilder: (context, state) {
              final params = state.extra as FinancialStatementParams;

              return slidePage(
                FinancialStatementEntriesScreen(
                  params: params,
                  title: "Profit and Loss",
                ),
                state,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: 'balance-sheet',
        pageBuilder: (_, state) {
          return slidePage(const BalanceSheetScreen(), state);
        },
        routes: [
          GoRoute(
            path: 'entries',
            pageBuilder: (context, state) {
              final params = state.extra as FinancialStatementParams;

              return slidePage(
                FinancialStatementEntriesScreen(
                  params: params,
                  title: "Balance Sheet",
                ),
                state,
              );
            },
          ),
        ],
      ),
    ],
  ),
];
