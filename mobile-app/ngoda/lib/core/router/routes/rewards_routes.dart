import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/params/loyalty_ledger_params.dart';
import 'package:ngoda/ui/screens/financial-intelligence/financial_badge_screen.dart';
import 'package:ngoda/ui/screens/financial-intelligence/financial_behaviour_periodic_screen.dart';
import 'package:ngoda/ui/screens/financial-intelligence/financial_intelligence_overview_screen.dart';
import 'package:ngoda/ui/screens/gamification/loyalty_badges_screen.dart';
import 'package:ngoda/ui/screens/gamification/loyalty_dashboard_screen.dart';
import 'package:ngoda/ui/screens/gamification/loyalty_ledger_screen.dart';
import 'package:ngoda/ui/screens/referral/share_ngoda_referral_screen.dart';

final List<GoRoute> rewardsRoutes = [
  GoRoute(
    path: '/rewards',
    pageBuilder: (_, state) {
      return slidePage(LoyaltyDashboardScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'points-history',
        pageBuilder: (_, state) {
          final params = state.extra as LoyaltyLedgerParams;

          return slidePage(LoyaltyLedgerScreen(params: params), state);
        },
      ),
      GoRoute(
        path: 'badges',
        pageBuilder: (_, state) {
          return slidePage(LoyaltyBadgesScreen(), state);
        },
      ),
    ],
  ),
  GoRoute(
    path: '/financial-intelligence',
    pageBuilder: (_, state) {
      return slidePage(FinancialIntelligenceOverviewScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'periodic',
        pageBuilder: (_, state) {
          return slidePage(FinancialBehaviourPeriodicScreen(), state);
        },
      ),
      GoRoute(
        path: 'badges',
        pageBuilder: (_, state) {
          return slidePage(FinancialBadgeScreen(), state);
        },
      ),
    ],
  ),

  GoRoute(
    path: '/share-referral-link',
    pageBuilder: (_, state) {
      return slidePage(ShareNgodaReferralScreen(), state);
    },
  ),
];
