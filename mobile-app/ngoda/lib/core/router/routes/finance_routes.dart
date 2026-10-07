import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/ui/screens/finance/approvals/approve_commission_payment.dart';
import 'package:ngoda/ui/screens/finance/approvals/approve_tax_payment_screen.dart';
import 'package:ngoda/ui/screens/finance/approvals/commission_settlement_items_screen.dart';
import 'package:ngoda/ui/screens/finance/approvals/tax_settlement_items_screen.dart';
import 'package:ngoda/ui/screens/finance/fiscal-periods/fiscal_periods_screen.dart';
import 'package:ngoda/ui/screens/finance/funding/customer_direct_deposit_screen.dart';
import 'package:ngoda/ui/screens/finance/funding/external_funding_screen.dart';
import 'package:ngoda/ui/screens/finance/funding/finance_funding_screen.dart';
import 'package:ngoda/ui/screens/finance/funding/gold_purchase_screen.dart';
import 'package:ngoda/ui/screens/finance/loans/finance_loans_screen.dart';
import 'package:ngoda/ui/screens/finance/loans/incomplete_liquidation_jobs_screen.dart.dart';
import 'package:ngoda/ui/screens/finance/loans/last_accrual_date_screen.dart';
import 'package:ngoda/ui/screens/finance/loans/liquidated_loans_screen.dart.dart';
import 'package:ngoda/ui/screens/finance/loans/manual_review_liquidation_job_screen.dart';
import 'package:ngoda/ui/screens/finance/loans/manual_review_liquidation_jobs_screen.dart';
import 'package:ngoda/ui/screens/finance/loans/manual_review_reconciliation_screen.dart';

final List<GoRoute> financeRoutes = [
  /*
   * Finance funding operations.
   */
  GoRoute(
    path: '/funding',
    builder: (_, _) => const FinanceFundingScreen(),
    routes: [
      GoRoute(
        path: 'external-funding',
        pageBuilder: (_, state) {
          return slidePage(const ExternalFundingScreen(), state);
        },
      ),
      GoRoute(
        path: 'customer-direct-deposit',
        pageBuilder: (_, state) {
          return slidePage(const CustomerDirectDepositScreen(), state);
        },
      ),
      GoRoute(
        path: 'gold-purchase',
        pageBuilder: (_, state) {
          return slidePage(const GoldPurchaseScreen(), state);
        },
      ),
    ],
  ),

  /*
   * Finance loan administration.
   */
  GoRoute(
    path: '/finance-loans',
    builder: (_, _) => const FinanceLoansScreen(),
    routes: [
      GoRoute(
        path: 'last-accrual-date',
        pageBuilder: (_, state) {
          return slidePage(const LastAccrualDateScreen(), state);
        },
      ),
      GoRoute(
        path: 'liquidated-loans',
        pageBuilder: (_, state) {
          final params = state.extra as LoanLiquidationParams;
          return slidePage(LiquidatedLoansScreen(params: params), state);
        },
      ),
      GoRoute(
        path: 'incomplete-liquidation-jobs',
        pageBuilder: (_, state) {
          final params = state.extra as LoanLiquidationParams;
          return slidePage(
            IncompleteLiquidationJobsScreen(params: params),
            state,
          );
        },
      ),
      GoRoute(
        path: 'manual-review-liquidation-jobs',
        pageBuilder: (_, state) {
          final params = state.extra as LoanLiquidationParams;
          return slidePage(
            ManualReviewLiquidationJobsScreen(params: params),
            state,
          );
        },
        routes: [
          GoRoute(
            path: 'job',
            pageBuilder: (context, state) {
              final jobId = state.extra as String;

              return slidePage(
                ManualReviewLiquidationJobScreen(jobId: jobId),
                state,
              );
            },
            routes: [
              GoRoute(
                path: 'reconcile',
                pageBuilder: (context, state) {
                  final jobId = state.extra as String;

                  return slidePage(
                    ReconcileManualReviewLiquidationJobScreen(jobId: jobId),
                    state,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  ),

  /*
   * Commission settlement approval.
   *
   * This is launched from the More/Profile navigation
   * surface for roles that are allowed to approve
   * commission settlements.
   */
  GoRoute(
    path: '/approve-commission-settlement',
    pageBuilder: (_, state) {
      return slidePage(ApproveCommissionPaymentScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'entries',
        pageBuilder: (_, state) {
          final params = state.extra as SettlementItemsParams;

          return slidePage(
            CommissionSettlementDrilldownScreen(params: params),
            state,
          );
        },
      ),
    ],
  ),

  /*
   * Government tax settlement approval.
   *
   * This is also launched directly from the
   * More/Profile navigation surface.
   */
  GoRoute(
    path: '/approve-tax-settlement',
    pageBuilder: (_, state) {
      return slidePage(ApproveTaxPaymentScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'entries',
        pageBuilder: (_, state) {
          final params = state.extra as SettlementItemsParams;

          return slidePage(TaxSettlementItemsScreen(params: params), state);
        },
      ),
    ],
  ),
  GoRoute(
    path: '/more-screen/fiscal-periods',
    pageBuilder: (_, state) {
      return slidePage(FiscalPeriodsScreen(), state);
    },
  ),
];
