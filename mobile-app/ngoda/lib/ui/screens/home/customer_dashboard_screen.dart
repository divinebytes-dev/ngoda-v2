import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/data_models/blockchain/blockchain_wallet_balance.dart';
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

        final gold = computeGoldMetrics(dashboard.loanSummary);

        final netPosition = computeUserNetPosition(
          dashboard,
          gold.availableUsd,
        );

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

        final blockchainBalances = dashboard.blockchainBalances
            .where((balance) => balance.currencyCode.toLowerCase() == 'gold')
            .toList(growable: false);

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
                  _DashboardHeader(
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                    themeMode: ref.watch(themeModeProvider),
                  ),

                  SizedBox(height: spacing.lg),

                  NetPositionCard(amount: netPosition),

                  if (quickLinks.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    DashboardQuickActions(quickLinks: quickLinks),
                  ],

                  SizedBox(height: spacing.lg),

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

                  if (blockchainBalances.isNotEmpty) ...[
                    SizedBox(height: spacing.sm),

                    _BlockchainBreakdownCard(balances: blockchainBalances),
                  ],

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

class _BlockchainBreakdownCard extends StatelessWidget {
  const _BlockchainBreakdownCard({required this.balances});

  final List<BlockchainWalletBalance> balances;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radius.lg),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    'Blockchain breakdown',
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${balances.length} ${balances.length == 1 ? 'network' : 'networks'}',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),

            SizedBox(height: spacing.xs),

            Text(
              'Your gold holdings across supported blockchains.',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),

            SizedBox(height: spacing.md),

            for (var index = 0; index < balances.length; index++) ...[
              if (index > 0) SizedBox(height: spacing.sm),

              _BlockchainBalanceTile(balance: balances[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockchainBalanceTile extends StatelessWidget {
  const _BlockchainBalanceTile({required this.balance});

  final BlockchainWalletBalance balance;

  String get blockchainName {
    final code = balance.blockchainCode.trim();

    if (code.isEmpty) {
      return 'Unknown blockchain';
    }

    return code[0].toUpperCase() + code.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radius.md),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(context.radius.md),
            ),
            child: Icon(
              Icons.hub_outlined,
              size: iconSize.medium,
              color: colorScheme.primary,
            ),
          ),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blockchainName,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  balance.blockchainCode.toUpperCase(),
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          SizedBox(width: spacing.sm),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${balance.balance.toStringAsFixed(6)} g',
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: spacing.xs),
              Text(
                '\$${balance.usdValue.toStringAsFixed(2)}',
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
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
// import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
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

//         /*
//          * Gold metrics continue to be derived
//          * from the existing loan summary.
//          *
//          * No dashboard/backend contract changes
//          * are introduced here.
//          */
//         final gold = computeGoldMetrics(dashboard.loanSummary);

//         /*
//          * Net position remains the primary
//          * financial summary shown on Home.
//          */
//         final netPosition = computeUserNetPosition(
//           dashboard,
//           gold.availableUsd,
//         );

//         /*
//          * NFC support remains local-device state.
//          */
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
//             child: RefreshIndicator(
//               onRefresh: () async {
//                 ref.invalidate(customerDashboardProvider);

//                 await ref.read(customerDashboardProvider.future);
//               },
//               child: ListView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 padding: EdgeInsets.fromLTRB(
//                   spacing.md,
//                   spacing.md,
//                   spacing.md,
//                   spacing.lg,
//                 ),
//                 children: [
//                   /*
//                    * Header
//                    */
//                   _DashboardHeader(
//                     onThemeChanged: () {
//                       ref.read(themeModeProvider.notifier).toggle();
//                     },
//                     themeMode: ref.watch(themeModeProvider),
//                   ),

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Primary financial position.
//                    *
//                    * This remains the dashboard
//                    * hero because it combines the
//                    * user's existing financial
//                    * position into one value.
//                    */
//                   // const _SectionLabel(
//                   //   title: 'Your position',
//                   //   description: 'A snapshot of where you stand today.',
//                   // ),

//                   // SizedBox(height: spacing.sm),
//                   NetPositionCard(amount: netPosition),

//                   /*
//                    * Existing transactional quick
//                    * actions remain immediately
//                    * accessible underneath the
//                    * primary position.
//                    */
//                   if (quickLinks.isNotEmpty) ...[
//                     SizedBox(height: spacing.md),

//                     DashboardQuickActions(quickLinks: quickLinks),
//                   ],

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Existing account information.
//                    *
//                    * Fiat, Gold and Loan are kept
//                    * together as the user's money
//                    * and financial position.
//                    */
//                   const _SectionLabel(
//                     title: 'Your money',
//                     description: 'Cash, gold and borrowing in one place.',
//                   ),

//                   SizedBox(height: spacing.sm),

//                   FiatCard(wallet: dashboard.wallet),

//                   SizedBox(height: spacing.sm),

//                   GoldCard(
//                     totalGrams: gold.total,
//                     totalUsd: gold.totalUsd,
//                     locked: gold.locked,
//                     lockedUsd: gold.lockedUsd,
//                     available: gold.available,
//                     availableUsd: gold.availableUsd,
//                   ),

//                   SizedBox(height: spacing.sm),

//                   LoanCard(
//                     principal: dashboard.loanSummary.principalOutstanding,
//                     interest: dashboard.loanSummary.interestOutstanding,
//                     ltv: dashboard.loanSummary.ltvPercent,
//                     requiredCollateral:
//                         dashboard.loanSummary.requiredCollateral,
//                     svaUtilisation:
//                         dashboard.loanSummary.svaAccess.utilisationPercent,
//                   ),
//                 ],
//               ),
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

// class _DashboardHeader extends StatelessWidget {
//   const _DashboardHeader({
//     required this.onThemeChanged,
//     required this.themeMode,
//   });

//   final VoidCallback onThemeChanged;
//   final ThemeMode themeMode;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.center,
//       children: [
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Welcome back',
//                 style: AppTextStyles.large(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),

//               SizedBox(height: spacing.xs),

//               Text(
//                 'Your financial position',
//                 style: AppTextStyles.small(
//                   context,
//                 ).copyWith(color: colorScheme.onSurfaceVariant),
//               ),
//             ],
//           ),
//         ),

//         IconButton(
//           tooltip: themeMode == ThemeMode.dark
//               ? 'Use light theme'
//               : 'Use dark theme',
//           onPressed: onThemeChanged,
//           icon: Icon(
//             themeMode == ThemeMode.dark
//                 ? Icons.light_mode_outlined
//                 : Icons.dark_mode_outlined,
//             color: colorScheme.primary,
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _SectionLabel extends StatelessWidget {
//   const _SectionLabel({required this.title, required this.description});

//   final String title;
//   final String description;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           title,
//           style: AppTextStyles.small(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),

//         SizedBox(height: spacing.xs),

//         Text(
//           description,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//       ],
//     );
//   }
// }
