import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/data_models/finance/finance_bucket.dart';
import 'package:ngoda/services/calculation_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

class FinanceDashboardScreen extends ConsumerWidget {
  const FinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final asyncData = ref.watch(financeDashboardProvider);

    Future<void> refresh() async {
      ref.invalidate(financeDashboardProvider);

      await ref.read(financeDashboardProvider.future);
    }

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading finance dashboard',
        fullScreen: true,
      ),
      error: (error, _) {
        if (isJwtExpired(error)) {
          return _SessionExpiredState(
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
      data: (data) {
        if (data.error != null) {
          if (isJwtExpired(data.error!)) {
            return _SessionExpiredState(
              onLogout: () async {
                await ref.read(authProvider.notifier).logout('Session Expired');

                if (!context.mounted) {
                  return;
                }

                context.go('/login');
              },
            );
          }

          return Scaffold(body: AppErrorState(message: data.error!));
        }

        final dashboard = data.result;

        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(
              message: 'Finance dashboard data is unavailable.',
            ),
          );
        }

        final summary = dashboard.summary;

        final summaryResult = CalculationService.calculateFinanceSummary(
          summary,
        );

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      spacing.padding,
                      spacing.md,
                      spacing.padding,
                      spacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _DashboardHeader(),

                          SizedBox(height: spacing.md),

                          NetPositionCard(amount: summaryResult.netPosition),
                        ],
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      spacing.padding,
                      spacing.sm,
                      spacing.padding,
                      spacing.lg,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        FinanceSectionCard(
                          title: 'Cash',
                          color: Colors.green,
                          children: [
                            _SectionBlock(
                              title: 'Bank',
                              bucket: summary.bank,
                              // color: Colors.white,
                            ),
                            _SectionBlock(
                              title: 'Treasury',
                              bucket: summary.treasury,
                              // color: Colors.white,
                            ),
                            _SectionTotal(
                              label: 'Total',
                              amount:
                                  summary.bank.totalUsd +
                                  summary.treasury.totalUsd,
                              color: Colors.green,
                            ),
                          ],
                        ),

                        SizedBox(height: spacing.md),

                        FinanceSectionCard(
                          title: 'Credit Agent',
                          color: Colors.purple,
                          children: [
                            _SectionBlock(
                              title: 'Float',
                              bucket: summary.creditAgentFloat,
                              // color: Colors.purple,
                            ),
                            _SectionBlock(
                              title: 'Cash',
                              bucket: summary.creditAgentCash,
                              // color: Colors.purple,
                            ),
                            _SectionTotal(
                              label: 'Net',
                              amount:
                                  summary.creditAgentCash.totalUsd +
                                  summary.creditAgentFloat.totalUsd,
                              color: Colors.purple,
                            ),
                          ],
                        ),

                        SizedBox(height: spacing.md),

                        FinanceSectionCard(
                          title: 'Credit Agent Float',
                          color: Colors.orange,
                          children: [
                            _SectionBlock(
                              title: 'Assets',
                              bucket: summary.agentAsset,
                              // color: Colors.orange,
                            ),
                            _SectionBlock(
                              title: 'Float',
                              bucket: summary.agentFloat,
                              // color: Colors.orange,
                            ),
                            _SectionTotal(
                              label: 'Net',
                              amount:
                                  summary.agentAsset.totalUsd -
                                  summary.agentFloat.totalUsd,
                              color: Colors.orange,
                            ),
                          ],
                        ),

                        SizedBox(height: spacing.md),

                        FinanceSectionCard(
                          title: 'User Deposit',
                          color: Colors.red,
                          children: [
                            _SectionBlock(
                              title: 'Users',
                              bucket: summary.customer,
                              // color: Colors.red,
                            ),
                            _SectionTotal(
                              label: 'Total',
                              amount: summary.customer.totalUsd,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;
    final mode = ref.watch(themeModeProvider);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dashboard',
              style: AppTextStyles.large(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
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
          'Overview of your financial position',
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.bucket, this.color});

  final String title;
  final FinanceBucket bucket;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final currencyList = bucket.sortedCurrencyList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.small(context)),

        SizedBox(height: spacing.xs),

        ...currencyList.map((currency) {
          final currencyAmount = bucket.getByCurrency(currency);

          return _CurrencyRow(
            currency: currency,
            value: currencyAmount,
            color: color,
          );
        }),

        SizedBox(height: spacing.xs),

        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Sub-total: ${NumberFormatService.formatAmount(bucket.totalUsd, currency: 'usd')}',
            style: AppTextStyles.smallNumber(context).copyWith(color: color),
          ),
        ),

        SizedBox(height: spacing.md),
      ],
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.currency, required this.value, this.color});

  final String currency;
  final CurrencyBalance? value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final balance = value;

    if (balance == null) {
      return const SizedBox.shrink();
    }

    final currencyCode = currency.toLowerCase();

    final isUsd = currencyCode == 'usd';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                currency.toUpperCase(),
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                NumberFormatService.formatAmount(
                  balance.balance,
                  currency: currencyCode,
                ),
                style: color != null
                    ? AppTextStyles.smallNumber(context).copyWith(color: color)
                    : AppTextStyles.smallNumber(context),
              ),
            ],
          ),

          if (!isUsd)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '≈ ${NumberFormatService.formatAmount(balance.usdValue, currency: 'usd')}',
                style: AppTextStyles.tinyNumber(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTotal extends StatelessWidget {
  const _SectionTotal({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        SizedBox(height: spacing.xs),
        const Divider(),
        SizedBox(height: spacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$label: ${NumberFormatService.formatAmount(amount, currency: 'usd')}',
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }
}

class FinanceSectionCard extends StatelessWidget {
  const FinanceSectionCard({
    super.key,
    required this.title,
    required this.color,
    required this.children,
  });

  final String title;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.09)),
        color: color.withValues(alpha: 0.005),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.medium(context).copyWith(color: color),
          ),

          SizedBox(height: spacing.md),

          ...children,
        ],
      ),
    );
  }
}

class _SessionExpiredState extends StatelessWidget {
  const _SessionExpiredState({required this.onLogout});

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
