import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/ui/screens/wallet/loan/active_loan/active_loan_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/active_loan/loan_detail_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/borrow/borrow_loan_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/borrow/loan_preview_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/loan_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/repay/repay_loan_screen.dart';
import 'package:ngoda/ui/screens/wallet/loan/topup_collateral/topup_collateral_screen.dart';

final List<GoRoute> loanRoutes = [
  GoRoute(
    path: '/loans',
    builder: (_, _) => const LoanScreen(),
    routes: [
      GoRoute(
        path: 'borrow',
        pageBuilder: (_, state) {
          return slidePage(BorrowLoanScreen(), state);
        },
        routes: [
          GoRoute(
            path: 'loan-preview',
            pageBuilder: (_, state) {
              final amount = state.extra as String;

              return slidePage(LoanPreviewScreen(amount: amount), state);
            },
          ),
        ],
      ),
      GoRoute(
        path: 'repay',
        pageBuilder: (_, state) {
          return slidePage(RepayLoanScreen(), state);
        },
      ),
      GoRoute(
        path: 'active-loans',
        pageBuilder: (_, state) {
          return slidePage(ActiveLoansScreen(), state);
        },
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (_, state) {
              final loanId = state.pathParameters['id']!;

              return slidePage(LoanDetailScreen(loanId: loanId), state);
            },
          ),
        ],
      ),
      GoRoute(
        path: 'topup-collateral',
        pageBuilder: (_, state) {
          return slidePage(TopupCollateralScreen(), state);
        },
      ),
    ],
  ),
];
