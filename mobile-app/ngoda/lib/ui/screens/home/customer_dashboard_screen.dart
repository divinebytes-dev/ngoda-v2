import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/compute_net_position.dart';
import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
import 'package:ngoda/ui/functions/gold_helper.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
import 'package:ngoda/ui/widgets/fiat_card.dart';
import 'package:ngoda/ui/widgets/gold_card.dart';
import 'package:ngoda/ui/widgets/loan_card.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

class CustomerDashboardScreen extends ConsumerWidget {
  const CustomerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final asyncData = ref.watch(customerDashboardProvider);

    return asyncData.when(
      loading: () =>
          const AppLoader(message: 'Loading dashboard', fullScreen: true),
      error: (error, _) {
        return _buildErrorState(context, ref, error);
      },
      data: (response) {
        if (response.error != null) {
          return _buildErrorState(context, ref, response.error!);
        }

        final dashboard = response.result;

        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(message: 'Dashboard data is unavailable.'),
          );
        }

        /*
         * Gold metrics continue to be derived
         * from the existing loan summary.
         *
         * No dashboard/backend contract changes
         * are introduced here.
         */
        final gold = computeGoldMetrics(dashboard.loanSummary);

        /*
         * Net position remains the primary
         * financial summary shown on Home.
         */
        final netPosition = computeUserNetPosition(
          dashboard,
          gold.availableUsd,
        );

        /*
         * NFC support remains local-device state.
         */
        final nfcSupported =
            ref
                .read(hiveServiceProvider)
                .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
                .result ??
            false;

        final quickLinks = getUserHomeScreenQuickLinks(
          context: context,
          role: UserRole.customer,
          iconSize: iconSize.medium,
          primary: colorScheme.primary,
          nfcSupported: nfcSupported,
        );

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(customerDashboardProvider);

                await ref.read(customerDashboardProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.md,
                  spacing.md,
                  spacing.lg,
                ),
                children: [
                  /*
                   * Header
                   */
                  _DashboardHeader(
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                    themeMode: ref.watch(themeModeProvider),
                  ),

                  SizedBox(height: spacing.lg),

                  /*
                   * Primary financial position.
                   *
                   * This remains the dashboard
                   * hero because it combines the
                   * user's existing financial
                   * position into one value.
                   */
                  // const _SectionLabel(
                  //   title: 'Your position',
                  //   description: 'A snapshot of where you stand today.',
                  // ),

                  // SizedBox(height: spacing.sm),
                  NetPositionCard(amount: netPosition),

                  /*
                   * Existing transactional quick
                   * actions remain immediately
                   * accessible underneath the
                   * primary position.
                   */
                  if (quickLinks.isNotEmpty) ...[
                    SizedBox(height: spacing.md),

                    DashboardQuickActions(quickLinks: quickLinks),
                  ],

                  SizedBox(height: spacing.lg),

                  /*
                   * Existing account information.
                   *
                   * Fiat, Gold and Loan are kept
                   * together as the user's money
                   * and financial position.
                   */
                  const _SectionLabel(
                    title: 'Your money',
                    description: 'Cash, gold and borrowing in one place.',
                  ),

                  SizedBox(height: spacing.sm),

                  FiatCard(wallet: dashboard.wallet),

                  SizedBox(height: spacing.sm),

                  GoldCard(
                    totalGrams: gold.total,
                    totalUsd: gold.totalUsd,
                    locked: gold.locked,
                    lockedUsd: gold.lockedUsd,
                    available: gold.available,
                    availableUsd: gold.availableUsd,
                  ),

                  SizedBox(height: spacing.sm),

                  LoanCard(
                    principal: dashboard.loanSummary.principalOutstanding,
                    interest: dashboard.loanSummary.interestOutstanding,
                    ltv: dashboard.loanSummary.ltvPercent,
                    requiredCollateral:
                        dashboard.loanSummary.requiredCollateral,
                    svaUtilisation:
                        dashboard.loanSummary.svaAccess.utilisationPercent,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
    if (!isJwtExpired(error)) {
      return Scaffold(body: AppErrorState(message: error.toString()));
    }

    return Scaffold(
      body: AppErrorState(
        title: 'Session Expired',
        message: 'Please login again to continue.',
        buttonText: 'Logout',
        onAction: () async {
          await ref.read(authProvider.notifier).logout('Session Expired');

          if (!context.mounted) {
            return;
          }

          context.go('/login');
        },
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.onThemeChanged,
    required this.themeMode,
  });

  final VoidCallback onThemeChanged;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                style: AppTextStyles.large(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              SizedBox(height: spacing.xs),

              Text(
                'Your financial position',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        IconButton(
          tooltip: themeMode == ThemeMode.dark
              ? 'Use light theme'
              : 'Use dark theme',
          onPressed: onThemeChanged,
          icon: Icon(
            themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.xs),

        Text(
          description,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// class _QuickActions extends StatelessWidget {
//   const _QuickActions({required this.quickLinks});

//   final List<Widget> quickLinks;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Quick actions',
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),

//         SizedBox(height: spacing.sm),

//         SingleChildScrollView(
//           scrollDirection: Axis.horizontal,
//           child: Row(
//             children: [
//               for (var index = 0; index < quickLinks.length; index++) ...[
//                 quickLinks[index],

//                 if (index < quickLinks.length - 1) SizedBox(width: spacing.sm),
//               ],
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';

// import 'package:ngoda/core/providers/hive_service_provider.dart';
// import 'package:ngoda/services/hive_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/compute_net_position.dart';
// import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
// import 'package:ngoda/ui/functions/gold_helper.dart';
// import 'package:ngoda/ui/functions/is_jwt_expired.dart';
// import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
// import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/shared/theme_provider.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/fiat_card.dart';
// import 'package:ngoda/ui/widgets/gold_card.dart';
// import 'package:ngoda/ui/widgets/loan_card.dart';
// import 'package:ngoda/ui/widgets/net_position_card.dart';

// class CustomerDashboardScreen extends ConsumerWidget {
//   const CustomerDashboardScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     final asyncData = ref.watch(customerDashboardProvider);

//     return asyncData.when(
//       loading: () =>
//           const AppLoader(message: 'Loading dashboard', fullScreen: true),
//       error: (error, _) {
//         return _buildErrorState(context, ref, error);
//       },
//       data: (response) {
//         if (response.error != null) {
//           return _buildErrorState(context, ref, response.error!);
//         }

//         final dashboard = response.result;

//         if (dashboard == null) {
//           return const Scaffold(
//             body: AppErrorState(message: 'Dashboard data is unavailable.'),
//           );
//         }

//         final gold = computeGoldMetrics(dashboard.loanSummary);

//         final netPosition = computeUserNetPosition(
//           dashboard,
//           gold.availableUsd,
//         );

//         final nfcSupported =
//             ref
//                 .read(hiveServiceProvider)
//                 .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
//                 .result ??
//             false;

//         final quickLinks = getUserHomeScreenQuickLinks(
//           context: context,
//           role: UserRole.customer,
//           iconSize: iconSize.medium,
//           primary: colorScheme.primary,
//           nfcSupported: nfcSupported,
//         );

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: Column(
//               children: [
//                 Padding(
//                   padding: EdgeInsets.fromLTRB(
//                     spacing.md,
//                     spacing.md,
//                     spacing.md,
//                     spacing.sm,
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.stretch,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Expanded(
//                             child: Text(
//                               'Welcome back',
//                               style: AppTextStyles.large(
//                                 context,
//                               ).copyWith(fontWeight: FontWeight.w700),
//                             ),
//                           ),
//                           IconButton(
//                             tooltip: 'Change theme',
//                             onPressed: () {
//                               ref.read(themeModeProvider.notifier).toggle();
//                             },
//                             icon: Icon(
//                               ref.watch(themeModeProvider) == ThemeMode.dark
//                                   ? Icons.light_mode_outlined
//                                   : Icons.dark_mode_outlined,
//                               color: colorScheme.primary,
//                             ),
//                           ),
//                         ],
//                       ),
//                       SizedBox(height: spacing.xs),
//                       Text(
//                         'Overview of your wealth',
//                         style: AppTextStyles.small(
//                           context,
//                         ).copyWith(color: colorScheme.onSurfaceVariant),
//                       ),
//                       SizedBox(height: spacing.sm),
//                       NetPositionCard(amount: netPosition),
//                       if (quickLinks.isNotEmpty) ...[
//                         SizedBox(height: spacing.md),
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: Row(
//                             children: [
//                               for (
//                                 var index = 0;
//                                 index < quickLinks.length;
//                                 index++
//                               ) ...[
//                                 quickLinks[index],
//                                 if (index < quickLinks.length - 1)
//                                   SizedBox(width: spacing.sm),
//                               ],
//                             ],
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ),
//                 Expanded(
//                   child: SingleChildScrollView(
//                     padding: EdgeInsets.fromLTRB(
//                       spacing.md,
//                       spacing.sm,
//                       spacing.md,
//                       spacing.lg,
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.stretch,
//                       children: [
//                         FiatCard(wallet: dashboard.wallet),
//                         SizedBox(height: spacing.sm),
//                         GoldCard(
//                           totalGrams: gold.total,
//                           totalUsd: gold.totalUsd,
//                           locked: gold.locked,
//                           lockedUsd: gold.lockedUsd,
//                           available: gold.available,
//                           availableUsd: gold.availableUsd,
//                         ),
//                         SizedBox(height: spacing.sm),
//                         LoanCard(
//                           principal: dashboard.loanSummary.principalOutstanding,
//                           interest: dashboard.loanSummary.interestOutstanding,
//                           ltv: dashboard.loanSummary.ltvPercent,
//                           requiredCollateral:
//                               dashboard.loanSummary.requiredCollateral,
//                           svaUtilisation: dashboard
//                               .loanSummary
//                               .svaAccess
//                               .utilisationPercent,
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
//     if (!isJwtExpired(error)) {
//       return Scaffold(body: AppErrorState(message: error.toString()));
//     }

//     return Scaffold(
//       body: AppErrorState(
//         title: 'Session Expired',
//         message: 'Please login again to continue.',
//         buttonText: 'Logout',
//         onAction: () async {
//           await ref.read(authProvider.notifier).logout('Session Expired');

//           if (!context.mounted) {
//             return;
//           }

//           context.go('/login');
//         },
//       ),
//     );
//   }
// }
