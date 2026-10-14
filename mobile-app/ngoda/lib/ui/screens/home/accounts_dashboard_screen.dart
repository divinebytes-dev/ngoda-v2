import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class AccountsDashboardScreen extends ConsumerWidget {
  const AccountsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(accountsDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading accounts dashboard',
        fullScreen: true,
      ),
      error: (error, _) {
        if (isJwtExpired(error)) {
          return _SessionExpired(
            onLogout: () async {
              await ref.read(authProvider.notifier).logout('Session Expired');

              if (!context.mounted) {
                return;
              }

              context.go('/login');
            },
          );
        }

        return Scaffold(body: AppErrorState(message: error.toString()));
      },
      data: (response) {
        if (response.error != null) {
          if (isJwtExpired(response.error!)) {
            return _SessionExpired(
              onLogout: () async {
                await ref.read(authProvider.notifier).logout('Session Expired');

                if (!context.mounted) {
                  return;
                }

                context.go('/login');
              },
            );
          }

          return Scaffold(body: AppErrorState(message: response.error));
        }

        final summary = response.result!;

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: Column(
              children: [
                const _DashboardHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      context.spacing.md,
                      context.spacing.sm,
                      context.spacing.md,
                      context.spacing.lg,
                    ),
                    child: Column(
                      children: [
                        DynamicMetricCard(
                          title: 'Total Revenue',
                          total: summary.kpi.totalRevenueUsd,
                          values: {
                            for (final currency
                                in summary.kpi.sortedCurrencyList)
                              currency:
                                  summary.kpi.data[currency]!.totalRevenue,
                          },
                          color: Colors.green,
                        ),
                        SizedBox(height: context.spacing.md),
                        DynamicMetricCard(
                          title: 'Total Expenses',
                          total: summary.kpi.totalExpensesUsd,
                          values: {
                            for (final currency
                                in summary.kpi.sortedCurrencyList)
                              currency:
                                  summary.kpi.data[currency]!.totalExpenses,
                          },
                          color: context.colorScheme.error,
                        ),
                        SizedBox(height: context.spacing.md),
                        DynamicMetricCard(
                          title: 'Net Profit',
                          total: summary.kpi.totalNetProfitUsd,
                          values: {
                            for (final currency
                                in summary.kpi.sortedCurrencyList)
                              currency: summary.kpi.data[currency]!.netProfit,
                          },
                          color: Colors.purple,
                        ),
                        SizedBox(height: context.spacing.md),
                        _BalanceSheetCard(
                          assetsTotal: summary.balanceSheet.totalAssetsUsd,
                          liabilitiesTotal:
                              summary.balanceSheet.totalLiabilitiesUsd,
                          equityTotal: summary.balanceSheet.totalEquityUsd,
                          assets: {
                            for (final currency
                                in summary.balanceSheet.sortedCurrencyList)
                              currency:
                                  summary.balanceSheet.data[currency]!.assets,
                          },
                          liabilities: {
                            for (final currency
                                in summary.balanceSheet.sortedCurrencyList)
                              currency: summary
                                  .balanceSheet
                                  .data[currency]!
                                  .liabilities,
                          },
                          equity: {
                            for (final currency
                                in summary.balanceSheet.sortedCurrencyList)
                              currency:
                                  summary.balanceSheet.data[currency]!.equity,
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SessionExpired extends StatelessWidget {
  const _SessionExpired({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppErrorState(
        title: 'Session Expired',
        message: 'Please login again to continue.',
        buttonText: 'Logout',
        onAction: onLogout,
      ),
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;
    final mode = ref.watch(themeModeProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.sm,
      ),
      child: Column(
        children: [
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Welcome Back',
                  style: AppTextStyles.large(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: Icon(
                  mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: () {
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Accounts Overview',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BalanceSheetCard extends StatelessWidget {
  const _BalanceSheetCard({
    required this.assetsTotal,
    required this.liabilitiesTotal,
    required this.equityTotal,
    required this.assets,
    required this.liabilities,
    required this.equity,
  });

  final double assetsTotal;
  final double liabilitiesTotal;
  final double equityTotal;

  final Map<String, CurrencyBalance> assets;
  final Map<String, CurrencyBalance> liabilities;
  final Map<String, CurrencyBalance> equity;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          Text('Balance Sheet Snapshot', style: AppTextStyles.medium(context)),
          SizedBox(height: spacing.md),
          DynamicMetricCard(
            title: 'Assets',
            total: assetsTotal,
            values: assets,
            color: Colors.green,
          ),
          SizedBox(height: spacing.md),
          DynamicMetricCard(
            title: 'Liabilities',
            total: liabilitiesTotal,
            values: liabilities,
            color: colorScheme.error,
          ),
          SizedBox(height: spacing.md),
          DynamicMetricCard(
            title: 'Equity',
            total: equityTotal,
            values: equity,
            color: Colors.purple,
          ),
        ],
      ),
    );
  }
}

class DynamicMetricCard extends StatelessWidget {
  const DynamicMetricCard({
    super.key,
    required this.title,
    required this.total,
    required this.values,
    required this.color,
  });

  final String title;
  final double total;
  final Map<String, CurrencyBalance> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm),
          Text(
            NumberFormatService.formatAmount(total, currency: 'usd'),
            style: AppTextStyles.mediumNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          ...values.entries.map((entry) {
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key.toUpperCase(),
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    NumberFormatService.formatAmount(
                      entry.value.balance,
                      currency: entry.key,
                    ),
                    style: AppTextStyles.smallNumber(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
