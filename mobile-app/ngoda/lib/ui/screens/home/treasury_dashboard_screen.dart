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
    final asyncData = ref.watch(treasuryDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading treasury dashboard',
        fullScreen: true,
      ),
      error: (error, _) => _buildErrorState(context, ref, error),
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
                  _DashboardHeader(
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                    themeMode: ref.watch(themeModeProvider),
                  ),

                  SizedBox(height: spacing.lg),

                  NetPositionCard(amount: dashboard.treasuryUsdValue),

                  SizedBox(height: spacing.lg),

                  const _SectionLabel(
                    title: 'Reserve overview',
                    description:
                        'Consolidated gold reserves, token supply and reserve coverage.',
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
                        '${NumberFormatService.formatNumber(dashboard.reserveCoveragePercent)}%',
                    color: dashboard.isHealthyReserve
                        ? Colors.green
                        : Colors.orange,
                    icon: Icons.shield_outlined,
                  ),

                  SizedBox(height: spacing.lg),

                  const _SectionLabel(
                    title: 'Blockchain balances',
                    description:
                        'Token supply, Treasury holdings and native gas balances by blockchain.',
                  ),

                  SizedBox(height: spacing.sm),

                  _BlockchainBalancesTable(dashboard: dashboard),

                  SizedBox(height: spacing.lg),

                  const _SectionLabel(
                    title: 'Treasury wallet',
                    description:
                        'Consolidated gold and fiat balances held by Treasury.',
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

    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            Theme.of(context).brightness == Brightness.dark);

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
          tooltip: isDark ? 'Use light theme' : 'Use dark theme',
          onPressed: onThemeChanged,
          iconSize: context.iconSize.large,
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
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
        borderRadius: BorderRadius.circular(context.radius.md),
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
            child: Icon(icon, color: color, size: context.iconSize.large),
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

class _BlockchainBalancesTable extends StatelessWidget {
  const _BlockchainBalancesTable({required this.dashboard});

  final TreasuryDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final blockchains = [...dashboard.blockchainBalances]
      ..sort(
        (first, second) =>
            first.blockchainCode.compareTo(second.blockchainCode),
      );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radius.md),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.09)),
      ),
      child: blockchains.isEmpty
          ? Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: context.iconSize.xl,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'No blockchain balances available.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(spacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: context.iconSize.medium,
                        color: colorScheme.primary,
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: Text(
                          '${blockchains.length} supported blockchain${blockchains.length == 1 ? '' : 's'}',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        Icons.swipe_outlined,
                        size: context.iconSize.medium,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 44,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 60,
                    horizontalMargin: spacing.md,
                    columnSpacing: spacing.lg,
                    headingRowColor: WidgetStatePropertyAll(
                      colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                    ),
                    columns: [
                      DataColumn(label: _tableHeading(context, 'Blockchain')),
                      DataColumn(
                        numeric: true,
                        label: _tableHeading(context, 'Token Supply'),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _tableHeading(context, 'Treasury Balance'),
                      ),
                      DataColumn(
                        numeric: true,
                        label: _tableHeading(context, 'Gas Balance'),
                      ),
                    ],
                    rows: [
                      for (final blockchain in blockchains)
                        DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatBlockchainName(
                                      blockchain.blockchainCode,
                                    ),
                                    style: AppTextStyles.small(
                                      context,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'Chain ${blockchain.chainId}',
                                    style: AppTextStyles.tiny(context).copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(
                                NumberFormatService.formatNumber(
                                  blockchain.tokenSupply,
                                ),
                                style: AppTextStyles.smallNumber(context),
                              ),
                            ),
                            DataCell(
                              Text(
                                NumberFormatService.formatNumber(
                                  blockchain.balance,
                                ),
                                style: AppTextStyles.smallNumber(context)
                                    .copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.primary,
                                    ),
                              ),
                            ),
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    NumberFormatService.formatNumber(
                                      blockchain.gasBalance,
                                      decimals: 8,
                                    ),
                                    style: AppTextStyles.smallNumber(context),
                                  ),
                                  Text(
                                    blockchain.nativeCurrencyCode,
                                    style: AppTextStyles.tiny(context).copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tableHeading(BuildContext context, String title) {
    return Text(
      title,
      style: AppTextStyles.small(context).copyWith(fontWeight: FontWeight.w700),
    );
  }

  String _formatBlockchainName(String code) {
    final trimmed = code.trim();

    if (trimmed.isEmpty) {
      return 'Unknown';
    }

    return trimmed[0].toUpperCase() + trimmed.substring(1);
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
        borderRadius: BorderRadius.circular(context.radius.md),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.09)),
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
              value: entry.value,
              color: colorScheme.primary,
            ),

          Divider(
            height: spacing.sm,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),

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
        borderRadius: BorderRadius.circular(context.radius.sm),
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
// import 'package:ngoda/ui/extensions/theme_extension.dart';
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
//     final spacing = context.spacing;
//     // final colorScheme = context.colorScheme;

//     final asyncData = ref.watch(treasuryDashboardProvider);

//     return asyncData.when(
//       loading: () => const AppLoader(
//         message: 'Loading treasury dashboard',
//         fullScreen: true,
//       ),
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
//             body: AppErrorState(
//               message: 'Treasury dashboard data is unavailable.',
//             ),
//           );
//         }

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: RefreshIndicator(
//               onRefresh: () async {
//                 ref.invalidate(treasuryDashboardProvider);

//                 await ref.read(treasuryDashboardProvider.future);
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
//                    * Primary Treasury position.
//                    */
//                   // const _SectionLabel(
//                   //   title: 'Treasury position',
//                   //   description: 'A snapshot of the treasury position today.',
//                   // ),

//                   // SizedBox(height: spacing.sm),
//                   NetPositionCard(amount: dashboard.treasuryUsdValue),

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Reserve and operational metrics.
//                    */
//                   const _SectionLabel(
//                     title: 'Reserve overview',
//                     description:
//                         'Gold reserves, token supply and reserve health.',
//                   ),

//                   SizedBox(height: spacing.sm),
//                   _MetricCard(
//                     title: 'Gold Reserve',
//                     value:
//                         '${NumberFormatService.formatNumber(dashboard.goldReserve)} g',
//                     color: Colors.amber,
//                     icon: Icons.workspace_premium_outlined,
//                   ),

//                   SizedBox(height: spacing.sm),

//                   _MetricCard(
//                     title: 'Token Supply',
//                     value: NumberFormatService.formatNumber(
//                       dashboard.tokenSupply,
//                     ),
//                     color: Colors.purple,
//                     icon: Icons.stacked_line_chart,
//                   ),

//                   SizedBox(height: spacing.sm),

//                   _MetricCard(
//                     title: 'Reserve Ratio',
//                     value:
//                         '${NumberFormatService.formatNumber(dashboard.reserveRatio)} %',
//                     color: Colors.blue,
//                     icon: Icons.shield_outlined,
//                   ),

//                   SizedBox(height: spacing.sm),

//                   _MetricCard(
//                     title: 'Relayer Gas',
//                     value: NumberFormatService.formatNumber(
//                       dashboard.gasBalance,
//                       decimals: 8,
//                     ),
//                     color: Colors.orange,
//                     icon: Icons.local_gas_station_outlined,
//                   ),

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Treasury wallet balances.
//                    */
//                   const _SectionLabel(
//                     title: 'Treasury wallet',
//                     description: 'Gold and fiat balances held by treasury.',
//                   ),

//                   SizedBox(height: spacing.sm),

//                   _TreasuryWalletCard(dashboard: dashboard),
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
//                 'Treasury',
//                 style: AppTextStyles.large(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//               SizedBox(height: spacing.xs),
//               Text(
//                 'Treasury overview',
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

// class _MetricCard extends StatelessWidget {
//   const _MetricCard({
//     required this.title,
//     required this.value,
//     required this.color,
//     required this.icon,
//   });

//   final String title;
//   final String value;
//   final Color color;
//   final IconData icon;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Container(
//       padding: EdgeInsets.all(spacing.md),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.06),
//         borderRadius: BorderRadius.circular(spacing.md),
//         border: Border.all(color: color.withValues(alpha: 0.20)),
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: EdgeInsets.all(spacing.sm),
//             decoration: BoxDecoration(
//               color: color.withValues(alpha: 0.15),
//               shape: BoxShape.circle,
//             ),
//             child: Icon(icon, color: color),
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
//                   ).copyWith(color: colorScheme.onSurfaceVariant),
//                 ),
//                 SizedBox(height: spacing.xs),
//                 Text(
//                   value,
//                   style: AppTextStyles.mediumNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w800, color: color),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _TreasuryWalletCard extends StatelessWidget {
//   const _TreasuryWalletCard({required this.dashboard});

//   final TreasuryDashboard dashboard;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     final currencyEntries = dashboard.treasuryWallet.currencyEntries
//         .where((entry) => entry.key.toLowerCase() != 'gold')
//         .toList();

//     return Container(
//       padding: EdgeInsets.all(spacing.sm),
//       decoration: BoxDecoration(
//         color: colorScheme.surface,
//         borderRadius: BorderRadius.circular(spacing.md),
//         border: Border.all(
//           color: colorScheme.outlineVariant.withValues(alpha: 0.5),
//         ),
//       ),
//       child: Column(
//         children: [
//           _WalletRow(
//             label: 'GOLD',
//             value: dashboard.treasuryWallet.getByCurrency('gold'),
//             color: Colors.orange,
//           ),

//           for (final entry in currencyEntries)
//             _WalletRow(
//               label: entry.key.toUpperCase(),
//               value: dashboard.treasuryWallet.getByCurrency(entry.key),
//               color: colorScheme.primary,
//             ),

//           Divider(height: spacing.lg, color: colorScheme.outlineVariant),

//           Padding(
//             padding: EdgeInsets.symmetric(horizontal: spacing.xs),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   'Total',
//                   style: AppTextStyles.small(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w700),
//                 ),
//                 Text(
//                   NumberFormatService.formatUsd(
//                     dashboard.treasuryWallet.totalUsdValue,
//                   ),
//                   style: AppTextStyles.mediumNumber(context).copyWith(
//                     fontWeight: FontWeight.w800,
//                     color: colorScheme.primary,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _WalletRow extends StatelessWidget {
//   const _WalletRow({
//     required this.label,
//     required this.value,
//     required this.color,
//   });

//   final String label;
//   final CurrencyBalance? value;
//   final Color color;

//   @override
//   Widget build(BuildContext context) {
//     if (value == null) {
//       return const SizedBox.shrink();
//     }

//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Container(
//       margin: EdgeInsets.only(top: spacing.xs),
//       padding: EdgeInsets.symmetric(
//         horizontal: spacing.sm,
//         vertical: spacing.sm,
//       ),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
//         borderRadius: BorderRadius.circular(spacing.sm),
//       ),
//       child: Row(
//         children: [
//           Expanded(child: Text(label, style: AppTextStyles.small(context))),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.end,
//             children: [
//               Text(
//                 NumberFormatService.formatAmount(
//                   value!.balance,
//                   currency: label.toLowerCase(),
//                 ),
//                 style: AppTextStyles.smallNumber(
//                   context,
//                 ).copyWith(color: color, fontWeight: FontWeight.w600),
//               ),
//               SizedBox(height: spacing.xs),
//               Text(
//                 '≈ ${NumberFormatService.formatUsd(value!.usdValue)}',
//                 style: AppTextStyles.tinyNumber(
//                   context,
//                 ).copyWith(color: colorScheme.onSurfaceVariant),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
