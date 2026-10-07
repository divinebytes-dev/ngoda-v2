import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/ui/screens/accounts/commission/accounts_payment_screen.dart';
import 'package:ngoda/ui/screens/accounts/commission/commission_summary_screen.dart';
import 'package:ngoda/ui/screens/accounts/commission/create_batch_payment_screen.dart';
import 'package:ngoda/ui/screens/accounts/commission/settle_commission_payment.dart';
import 'package:ngoda/ui/screens/accounts/commission/settled_commission_summary_screen.dart';
import 'package:ngoda/ui/screens/accounts/funding/accounts_funding_screen.dart';
import 'package:ngoda/ui/screens/accounts/funding/credit_agent_cash_settlement_request_screen.dart';
import 'package:ngoda/ui/screens/accounts/funding/fund_treasury_screen.dart';
import 'package:ngoda/ui/screens/accounts/tax/create_tax_batch_payment_screen.dart';
import 'package:ngoda/ui/screens/accounts/tax/settle_tax_batch_payment_screen.dart';
import 'package:ngoda/ui/screens/accounts/tax/settled_tax_summary_screen.dart';
import 'package:ngoda/ui/screens/accounts/tax/tax_summary_screen.dart';
import 'package:ngoda/ui/screens/finance/approvals/commission_settlement_items_screen.dart';
import 'package:ngoda/ui/screens/finance/approvals/tax_settlement_items_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/credit_agent_balance_drilldown_screen.dart';
import 'package:ngoda/ui/screens/wallet/reports/credit_agents_balance_screen.dart';

final List<GoRoute> accountsRoutes = [
  /*
   * Accounts funding and settlement.
   */
  GoRoute(
    path: '/accounts-funding',
    builder: (_, _) => const AccountsFundingScreen(),
    routes: [
      GoRoute(
        path: 'treasury-funding',
        pageBuilder: (_, state) {
          return slidePage(TreasuryFundingScreen(), state);
        },
      ),
      GoRoute(
        path: 'credit-agents-balances',
        pageBuilder: (_, state) {
          return slidePage(CreditAgentsBalanceScreen(), state);
        },
        routes: [
          GoRoute(
            path: 'entries',
            pageBuilder: (_, state) {
              final params = state.extra as CreditAgentBalanceParams;

              return slidePage(
                CreditAgentBalanceDrilldownScreen(params: params),
                state,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: 'credit-agent-cash-settlement',
        pageBuilder: (_, state) {
          return slidePage(CreditAgentCashSettlementRequestScreen(), state);
        },
      ),
    ],
  ),

  /*
   * Commission and tax payments.
   */
  GoRoute(
    path: '/payments',
    builder: (_, _) => AccountsPaymentScreen(),
    routes: [
      /*
       * Commission.
       */
      GoRoute(
        path: 'commission-summary',
        pageBuilder: (_, state) {
          return slidePage(CommissionSummaryScreen(), state);
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
      GoRoute(
        path: 'create-commission-batch',
        pageBuilder: (_, state) {
          return slidePage(CreateBatchPaymentScreen(), state);
        },
      ),
      GoRoute(
        path: 'settle-commission-batch',
        pageBuilder: (_, state) {
          return slidePage(SettleCommissionPaymentScreen(), state);
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
      GoRoute(
        path: 'settled-commission-batches',
        pageBuilder: (_, state) {
          return slidePage(SettledCommissionSummaryScreen(), state);
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
       * Government tax.
       */
      GoRoute(
        path: 'tax-summary',
        pageBuilder: (_, state) {
          return slidePage(TaxSummaryScreen(), state);
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
        path: 'create-tax-payment',
        pageBuilder: (_, state) {
          return slidePage(CreateTaxBatchPaymentScreen(), state);
        },
      ),
      GoRoute(
        path: 'settle-tax-payment',
        pageBuilder: (_, state) {
          return slidePage(SettleTaxBatchPaymentScreen(), state);
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
        path: 'settled-tax-payments',
        pageBuilder: (_, state) {
          return slidePage(SettledTaxSummaryScreen(), state);
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
    ],
  ),
];
