import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/currency/currency_balance.dart';

import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
import 'package:ngoda/data_models/treasury/treasury_wallet.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

class TreasuryDashboardScreen extends ConsumerWidget {
  const TreasuryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    // final colorScheme = context.colorScheme;

    final asyncData = ref.watch(treasuryDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading treasury dashboard',
        fullScreen: true,
      ),
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
            body: AppErrorState(
              message: 'Treasury dashboard data is unavailable.',
            ),
          );
        }

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(treasuryDashboardProvider);

                await ref.read(treasuryDashboardProvider.future);
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
                   * Primary Treasury position.
                   */
                  // const _SectionLabel(
                  //   title: 'Treasury position',
                  //   description: 'A snapshot of the treasury position today.',
                  // ),

                  // SizedBox(height: spacing.sm),
                  NetPositionCard(amount: dashboard.treasuryUsdValue),

                  SizedBox(height: spacing.lg),

                  /*
                   * Reserve and operational metrics.
                   */
                  const _SectionLabel(
                    title: 'Reserve overview',
                    description:
                        'Gold reserves, token supply and reserve health.',
                  ),

                  SizedBox(height: spacing.sm),
                  _MetricCard(
                    title: 'Gold Reserve',
                    value:
                        '${NumberFormatService.formatNumber(dashboard.goldReserve)} g',
                    color: Colors.amber,
                    icon: Icons.workspace_premium_outlined,
                  ),

                  SizedBox(height: spacing.sm),

                  _MetricCard(
                    title: 'Token Supply',
                    value: NumberFormatService.formatNumber(
                      dashboard.tokenSupply,
                    ),
                    color: Colors.purple,
                    icon: Icons.stacked_line_chart,
                  ),

                  SizedBox(height: spacing.sm),

                  _MetricCard(
                    title: 'Reserve Ratio',
                    value:
                        '${NumberFormatService.formatNumber(dashboard.reserveRatio)} %',
                    color: Colors.blue,
                    icon: Icons.shield_outlined,
                  ),

                  SizedBox(height: spacing.sm),

                  _MetricCard(
                    title: 'Relayer Gas',
                    value: NumberFormatService.formatNumber(
                      dashboard.gasBalance,
                      decimals: 8,
                    ),
                    color: Colors.orange,
                    icon: Icons.local_gas_station_outlined,
                  ),

                  SizedBox(height: spacing.lg),

                  /*
                   * Treasury wallet balances.
                   */
                  const _SectionLabel(
                    title: 'Treasury wallet',
                    description: 'Gold and fiat balances held by treasury.',
                  ),

                  SizedBox(height: spacing.sm),

                  _TreasuryWalletCard(dashboard: dashboard),
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
                'Treasury',
                style: AppTextStyles.large(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: spacing.xs),
              Text(
                'Treasury overview',
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  value,
                  style: AppTextStyles.mediumNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TreasuryWalletCard extends StatelessWidget {
  const _TreasuryWalletCard({required this.dashboard});

  final TreasuryDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final currencyEntries = dashboard.treasuryWallet.currencyEntries
        .where((entry) => entry.key.toLowerCase() != 'gold')
        .toList();

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          _WalletRow(
            label: 'GOLD',
            value: dashboard.treasuryWallet.getByCurrency('gold'),
            color: Colors.orange,
          ),

          for (final entry in currencyEntries)
            _WalletRow(
              label: entry.key.toUpperCase(),
              value: dashboard.treasuryWallet.getByCurrency(entry.key),
              color: colorScheme.primary,
            ),

          Divider(height: spacing.lg, color: colorScheme.outlineVariant),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  NumberFormatService.formatUsd(
                    dashboard.treasuryWallet.totalUsdValue,
                  ),
                  style: AppTextStyles.mediumNumber(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final CurrencyBalance? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const SizedBox.shrink();
    }

    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.only(top: spacing.xs),
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(spacing.sm),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.small(context))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormatService.formatAmount(
                  value!.balance,
                  currency: label.toLowerCase(),
                ),
                style: AppTextStyles.smallNumber(
                  context,
                ).copyWith(color: color, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: spacing.xs),
              Text(
                '≈ ${NumberFormatService.formatUsd(value!.usdValue)}',
                style: AppTextStyles.tinyNumber(
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
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/data_models/currency/currency_balance.dart';
// import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
// import 'package:ngoda/data_models/treasury/treasury_wallet.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/functions/is_jwt_expired.dart';
// import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
// import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/shared/theme_provider.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/net_position_card.dart';

// class TreasuryDashboardScreen extends ConsumerWidget {
//   const TreasuryDashboardScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final asyncData = ref.watch(treasuryDashboardProvider);

//     return asyncData.when(
//       loading: () => const AppLoader(
//         message: 'Loading treasury dashboard',
//         fullScreen: true,
//       ),
//       error: (error, _) => _buildError(context, ref, error),
//       data: (response) {
//         final error = response.error;
//         if (error != null) {
//           return _buildError(context, ref, error);
//         }

//         final summary = response.result;
//         if (summary == null) {
//           return _buildError(
//             context,
//             ref,
//             'No treasury dashboard data is available. Please try again.',
//           );
//         }

//         final spacing = context.spacing;
//         final scheme = Theme.of(context).colorScheme;

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: Column(
//               children: [
//                 Padding(
//                   padding: EdgeInsets.symmetric(
//                     horizontal: spacing.md,
//                     vertical: spacing.sm,
//                   ),
//                   child: Column(
//                     children: [
//                       SizedBox(height: spacing.lg),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: Text(
//                               'Dashboard',
//                               style: AppTextStyles.large(
//                                 context,
//                               ).copyWith(fontWeight: FontWeight.w700),
//                             ),
//                           ),
//                           Consumer(
//                             builder: (context, ref, _) {
//                               final mode = ref.watch(themeModeProvider);
//                               final isDark =
//                                   mode == ThemeMode.dark ||
//                                   (mode == ThemeMode.system &&
//                                       Theme.of(context).brightness ==
//                                           Brightness.dark);

//                               return IconButton(
//                                 tooltip: isDark
//                                     ? 'Switch to light theme'
//                                     : 'Switch to dark theme',
//                                 iconSize: context.iconSize.large,
//                                 icon: Icon(
//                                   isDark ? Icons.light_mode : Icons.dark_mode,
//                                 ),
//                                 onPressed: () {
//                                   ref.read(themeModeProvider.notifier).toggle();
//                                 },
//                               );
//                             },
//                           ),
//                         ],
//                       ),
//                       SizedBox(height: spacing.xs),
//                       Text(
//                         'Treasury Overview',
//                         style: AppTextStyles.small(
//                           context,
//                         ).copyWith(color: scheme.onSurfaceVariant),
//                       ),
//                       SizedBox(height: spacing.lg),
//                       NetPositionCard(amount: summary.treasuryUsdValue),
//                       SizedBox(height: spacing.lg),
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
//                       children: [
//                         _MetricCard(
//                           title: 'Gold Reserve',
//                           value:
//                               '${NumberFormatService.formatNumber(summary.goldReserve)} g',
//                           color: scheme.primary,
//                           icon: Icons.workspace_premium,
//                         ),
//                         SizedBox(height: spacing.md),
//                         _MetricCard(
//                           title: 'Token Supply',
//                           value: NumberFormatService.formatNumber(
//                             summary.tokenSupply,
//                           ),
//                           color: scheme.secondary,
//                           icon: Icons.stacked_line_chart,
//                         ),
//                         SizedBox(height: spacing.md),
//                         _MetricCard(
//                           title: 'Reserve Ratio',
//                           value:
//                               '${NumberFormatService.formatNumber(summary.reserveRatio)} %',
//                           color: scheme.tertiary,
//                           icon: Icons.shield_outlined,
//                         ),
//                         SizedBox(height: spacing.md),
//                         _MetricCard(
//                           title: 'Relayer Gas',
//                           value: NumberFormatService.formatNumber(
//                             summary.gasBalance,
//                             decimals: 8,
//                           ),
//                           color: scheme.primary,
//                           icon: Icons.heat_pump,
//                         ),
//                         SizedBox(height: spacing.md),
//                         _walletCard(context, summary),
//                         SizedBox(height: spacing.lg),
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

//   Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
//     final sessionExpired = isJwtExpired(error);

//     return Scaffold(
//       body: SafeArea(
//         child: AppErrorState(
//           title: sessionExpired ? 'Session Expired' : 'Error',
//           message: sessionExpired
//               ? 'Please log in again to continue.'
//               : error.toString(),
//           buttonText: sessionExpired ? 'Logout' : 'Retry',
//           onAction: () async {
//             if (sessionExpired) {
//               await ref.read(authProvider.notifier).logout('Session Expired');
//               if (!context.mounted) return;
//               context.go('/login');
//             } else {
//               ref.invalidate(treasuryDashboardProvider);
//             }
//           },
//         ),
//       ),
//     );
//   }

//   Widget _walletCard(BuildContext context, TreasuryDashboard summary) {
//     final spacing = context.spacing;
//     final theme = Theme.of(context);
//     final scheme = theme.colorScheme;
//     final wallet = summary.treasuryWallet;

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(spacing.md),
//       decoration: BoxDecoration(
//         color: theme.cardColor,
//         borderRadius: BorderRadius.circular(context.radius.lg),
//         border: Border.all(color: scheme.outlineVariant),
//       ),
//       child: Column(
//         children: [
//           _walletRow(context, 'GOLD', wallet.getByCurrency('gold')),
//           for (final entry in wallet.currencyEntries)
//             if (entry.key.toLowerCase() != 'gold')
//               _walletRow(context, entry.key.toUpperCase(), entry.value),
//           Divider(height: spacing.lg),
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 flex: 4,
//                 child: Text(
//                   'Total',
//                   textAlign: TextAlign.left,
//                   style: AppTextStyles.small(context),
//                 ),
//               ),
//               SizedBox(width: spacing.sm),
//               Expanded(
//                 flex: 6,
//                 child: Text(
//                   NumberFormatService.formatUsd(wallet.totalUsdValue),
//                   textAlign: TextAlign.right,
//                   style: AppTextStyles.mediumNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w800),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _walletRow(
//     BuildContext context,
//     String label,
//     CurrencyBalance? value,
//   ) {
//     if (value == null) return const SizedBox.shrink();

//     final spacing = context.spacing;
//     final theme = Theme.of(context);

//     return Container(
//       margin: EdgeInsets.only(top: spacing.xs),
//       padding: EdgeInsets.all(spacing.sm),
//       decoration: BoxDecoration(
//         color: theme.scaffoldBackgroundColor,
//         borderRadius: BorderRadius.circular(context.radius.md),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Expanded(
//             flex: 4,
//             child: Text(
//               label,
//               textAlign: TextAlign.left,
//               style: AppTextStyles.small(context),
//             ),
//           ),
//           SizedBox(width: spacing.sm),
//           Expanded(
//             flex: 6,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 Text(
//                   NumberFormatService.formatAmount(
//                     value.balance,
//                     currency: label.toLowerCase(),
//                   ),
//                   textAlign: TextAlign.right,
//                   style: AppTextStyles.smallNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w600),
//                 ),
//                 SizedBox(height: spacing.xs),
//                 Text(
//                   '≈ ${NumberFormatService.formatUsd(value.usdValue)}',
//                   textAlign: TextAlign.right,
//                   style: AppTextStyles.tinyNumber(
//                     context,
//                   ).copyWith(color: theme.colorScheme.onSurfaceVariant),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _MetricCard extends StatelessWidget {
//   final String title;
//   final String value;
//   final Color color;
//   final IconData icon;

//   const _MetricCard({
//     required this.title,
//     required this.value,
//     required this.color,
//     required this.icon,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final theme = Theme.of(context);

//     return Container(
//       padding: EdgeInsets.all(spacing.md),
//       decoration: BoxDecoration(
//         color: theme.cardColor,
//         borderRadius: BorderRadius.circular(context.radius.lg),
//         border: Border.all(color: color.withValues(alpha: 0.2)),
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: EdgeInsets.all(spacing.sm),
//             decoration: BoxDecoration(
//               color: color.withValues(alpha: 0.15),
//               shape: BoxShape.circle,
//             ),
//             child: Icon(icon, color: color, size: context.iconSize.large),
//           ),
//           SizedBox(width: spacing.sm),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   title,
//                   style: AppTextStyles.small(
//                     context,
//                   ).copyWith(color: theme.colorScheme.onSurfaceVariant),
//                 ),
//                 SizedBox(height: spacing.xs),
//                 Text(
//                   value,
//                   style: AppTextStyles.mediumNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w800),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
