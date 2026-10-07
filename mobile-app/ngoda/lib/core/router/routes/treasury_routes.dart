import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/ui/screens/treasury/funding/treasury_funding_screen.dart';
import 'package:ngoda/ui/screens/accounts/tokenisation/approve_token_adjustment_screen.dart';
import 'package:ngoda/ui/screens/finance/transactions/gl_account_drilldown_screen.dart';
import 'package:ngoda/ui/screens/treasury/approval/approve_credit_agent_screen.dart';
import 'package:ngoda/ui/screens/treasury/balances/token_balances_screen.dart';
import 'package:ngoda/ui/screens/treasury/funding/fund_agent_screen.dart';
import 'package:ngoda/ui/screens/treasury/funding/fund_credit_agent_screen.dart';
import 'package:ngoda/ui/screens/treasury/tokenisation/execute_token_adjustment_screen.dart';
import 'package:ngoda/ui/screens/treasury/tokenisation/incomplete_blockchain_transactions_screen.dart';

final List<GoRoute> treasuryRoutes = [
  GoRoute(
    path: '/treasury-funding',
    builder: (_, _) => const TreasuryFundingScreen(),
    routes: [
      GoRoute(
        path: 'agent-funding',
        pageBuilder: (_, state) {
          return slidePage(AgentFundingScreen(), state);
        },
      ),
      GoRoute(
        path: 'credit-agent-funding',
        pageBuilder: (_, state) {
          return slidePage(FundCreditAgentScreen(), state);
        },
      ),
    ],
  ),

  GoRoute(
    path: '/tokens',
    builder: (_, _) => const ExecuteTokenAdjustmentScreen(),
    routes: [
      GoRoute(
        path: 'balances',
        pageBuilder: (_, state) {
          return slidePage(TokenBalancesScreen(), state);
        },
        routes: [
          GoRoute(
            path: ':params',
            pageBuilder: (_, state) {
              final params = state.extra as GlDrilldownParams;

              return slidePage(GlAccountDrilldownScreen(params: params), state);
            },
          ),
        ],
      ),
      GoRoute(
        path: 'approve-adjustment',
        pageBuilder: (_, state) {
          return slidePage(ApproveTokenAdjustmentScreen(), state);
        },
      ),
      GoRoute(
        path: 'incomplete-blockchain-transactions',
        pageBuilder: (_, state) {
          return slidePage(IncompleteBlockchainTransactionsScreen(), state);
        },
      ),
    ],
  ),

  GoRoute(
    path: '/approve-credit-agent',
    pageBuilder: (_, state) {
      return slidePage(ApproveCreditAgentScreen(), state);
    },
  ),
];
