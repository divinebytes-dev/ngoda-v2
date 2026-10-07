import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/core/router/routes/accounts_routes.dart';
import 'package:ngoda/core/router/routes/admin_routes.dart';
import 'package:ngoda/core/router/routes/agent_routes.dart';
import 'package:ngoda/core/router/routes/auth_redirect.dart';
import 'package:ngoda/core/router/routes/auth_routes.dart';
import 'package:ngoda/core/router/routes/commission_routes.dart';
import 'package:ngoda/core/router/routes/common_routes.dart';
import 'package:ngoda/core/router/routes/compliance_routes.dart';
import 'package:ngoda/core/router/routes/customer_routes.dart';
import 'package:ngoda/core/router/routes/finance_routes.dart';
import 'package:ngoda/core/router/routes/financial_statement_routes.dart';
import 'package:ngoda/core/router/routes/gold_routes.dart';
import 'package:ngoda/core/router/routes/loan_routes.dart';
import 'package:ngoda/core/router/routes/merchant_routes.dart';
import 'package:ngoda/core/router/routes/rewards_routes.dart';
import 'package:ngoda/core/router/routes/transaction_routes.dart';
import 'package:ngoda/core/router/routes/treasury_routes.dart';
import 'package:ngoda/core/router/routes/vendor_routes.dart';
import 'package:ngoda/core/router/routes/wallet_routes.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final analytics = ref.read(analyticsServiceProvider);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    redirect: authRedirect,
    observers: [analytics.getAnalyticsObserver()],
    routes: [
      /*
       * Application entry and authentication.
       */
      ...authRoutes,

      /*
       * Shared application navigation.
       *
       * Dashboard and profile live here.
       */
      ...commonRoutes,

      /*
       * Shared user capabilities.
       *
       * These capabilities can be exposed from the
       * More navigation according to the user's role.
       */
      ...transactionRoutes,
      ...walletRoutes,
      ...goldRoutes,
      ...loanRoutes,
      ...financialStatementRoutes,
      ...rewardsRoutes,
      ...commissionRoutes,

      /*
       * User and operational roles.
       */
      ...customerRoutes,
      ...agentRoutes,
      ...merchantRoutes,
      ...vendorRoutes,

      /*
       * Finance and control roles.
       */
      ...financeRoutes,
      ...accountsRoutes,
      ...treasuryRoutes,
      ...complianceRoutes,

      /*
       * Administration.
       */
      ...adminRoutes,
    ],
  );
});
