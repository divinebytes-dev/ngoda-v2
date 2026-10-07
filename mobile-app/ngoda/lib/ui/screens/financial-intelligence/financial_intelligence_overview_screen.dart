import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ngoda/data_models/financial-intelligence/financial_behaviour.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_identity.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_overview_data.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_by_currency.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/financial-intelligence/provider/financial_behaviour_overview_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FinancialIntelligenceOverviewScreen extends ConsumerStatefulWidget {
  const FinancialIntelligenceOverviewScreen({super.key});

  @override
  ConsumerState<FinancialIntelligenceOverviewScreen> createState() =>
      _FinancialIntelligenceOverviewScreenState();
}

class _FinancialIntelligenceOverviewScreenState
    extends ConsumerState<FinancialIntelligenceOverviewScreen> {
  String _selection = 'ALL';

  Future<void> _refresh() async {
    ref.invalidate(financialBehaviourOverviewProvider);

    await ref.read(financialBehaviourOverviewProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(financialBehaviourOverviewProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Financial Behaviour',
              onClose: () {
                ref.invalidate(financialBehaviourOverviewProvider);

                context.pop();
              },
            ),
            Expanded(
              child: result.when(
                loading: () => const AppLoader(
                  message: 'Loading financial behaviour',
                  fullScreen: true,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.hasError) {
                    return AppErrorState(message: response.error);
                  }

                  final overview = response.result;

                  if (overview == null) {
                    return const AppEmptyState();
                  }

                  final summary = overview.summary;

                  if (summary.sortedCurrencyList.isEmpty &&
                      summary.moneyCurrencyList.isEmpty) {
                    return const AppEmptyState();
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: _OverviewBody(
                      data: overview,
                      selection: _selection,
                      onSelectionChanged: (value) {
                        setState(() {
                          _selection = value;
                        });
                      },
                      onViewMonthlyActivity: () {
                        context.push('/financial-intelligence/periodic');
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.data,
    required this.selection,
    required this.onSelectionChanged,
    required this.onViewMonthlyActivity,
  });

  final FinancialBehaviourOverviewData data;
  final String selection;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onViewMonthlyActivity;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final colors = Theme.of(context).colorScheme;

    final selectedCurrency = selection == 'ALL'
        ? null
        : summary.getByCurrency(selection);

    final selectedMoney = selection == 'ALL'
        ? null
        : summary.getMoneyByCurrency(selection);

    final view = _FinancialView.from(summary, selectedCurrency, selectedMoney);

    final currencies =
        summary.moneyCurrencyList
            .where(
              (currency) =>
                  currency.trim().isNotEmpty &&
                  currency.toLowerCase() != 'gold',
            )
            .map((currency) => currency.toUpperCase())
            .toSet()
            .toList()
          ..sort();

    final options = <String>['ALL', ...currencies];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        ScreenScalingService.scaleSize(context, 16),
        ScreenScalingService.scaleSize(context, 8),
        ScreenScalingService.scaleSize(context, 16),
        ScreenScalingService.scaleSize(context, 32),
      ),
      children: [
        _PeriodHeader(
          fiscalYear: summary.fiscalYear,
          currentPeriod: summary.currentPeriod,
        ),
        SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

        _IdentityCard(identity: data.identity),

        SizedBox(height: ScreenScalingService.scaleSize(context, 24)),

        Text(
          'View by currency',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

        _CurrencySelector(
          options: options,
          selected: selection,
          onSelected: onSelectionChanged,
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: ScreenScalingService.scaleSize(context, 15),
              color: colors.onSurfaceVariant,
            ),
            SizedBox(width: ScreenScalingService.scaleSize(context, 6)),
            Expanded(
              child: Text(
                selection == 'ALL'
                    ? 'All currencies shown in USD equivalent'
                    : '${selection.toUpperCase()} shown in its native currency',
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 20)),

        _FinancialPositionCard(view: view),

        SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

        _SectionCard(
          title: 'Where your money came from',
          subtitle: 'Money available during the selected financial period',
          child: _ActivityBarChart(view: view),
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

        _SectionCard(
          title: 'How your money was distributed',
          subtitle:
              'Withdrawal, spending, investment, loan repayment and savings',
          child: _ActivityMixChart(view: view),
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

        _GoldCard(summary: summary),

        SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: onViewMonthlyActivity,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              'View monthly activity',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.fiscalYear, required this.currentPeriod});

  final int fiscalYear;
  final int currentPeriod;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final period = _financialYearPeriodLabel(currentPeriod);

    return Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: ScreenScalingService.scaleSize(context, 16),
          color: colors.onSurfaceVariant,
        ),
        SizedBox(width: ScreenScalingService.scaleSize(context, 7)),
        Expanded(
          child: Text(
            period.isEmpty ? 'FY $fiscalYear' : 'FY $fiscalYear  •  $period',
            style: AppTextStyles.small(context).copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String _financialYearPeriodLabel(int currentPeriod) {
  if (currentPeriod <= 0) {
    return '';
  }

  final safePeriod = currentPeriod.clamp(1, 12).toInt();

  final startMonth = DateFormat('MMM').format(DateTime(2000, 1));

  final endMonth = DateFormat('MMM').format(DateTime(2000, safePeriod));

  if (safePeriod == 1) {
    return startMonth;
  }

  return '$startMonth – $endMonth';
}

class _FinancialView {
  const _FinancialView({
    required this.currencyCode,
    required this.moneyIn,
    required this.distribution,
    required this.availableMoney,
    required this.savings,
    required this.investment,
    required this.borrowing,
    required this.repayment,
    required this.outstandingLoan,
  });

  final String currencyCode;

  final List<_ChartDatum> moneyIn;
  final List<_ChartDatum> distribution;

  final double availableMoney;

  /// Closing savings position.
  final double savings;

  /// Investment purchases during the selected FY/period.
  final double investment;

  /// Loan disbursements during the selected FY/period.
  ///
  /// This is deliberately separate from repayment and outstanding balance.
  final double borrowing;

  /// Loan repayments during the selected FY/period.
  final double repayment;

  /// Closing loan balance.
  final double outstandingLoan;

  factory _FinancialView.from(
    FinancialBehaviour summary,
    FinancialCurrencySummary? currency,
    FinancialMoneyByCurrency? moneyByCurrency,
  ) {
    if (currency == null) {
      return _FinancialView(
        currencyCode: 'USD',
        moneyIn: _chartData(summary.moneyInChartUsd),
        distribution: _chartData(summary.distributionChartUsd),
        availableMoney: summary.moneyIn.totalUsd,
        savings: summary.totalClosingSavingsUsd,
        investment: summary.totalInvestmentPurchaseUsd,
        borrowing: summary.totalBorrowingUsd,
        repayment: summary.totalRepaymentUsd,
        outstandingLoan: summary.totalClosingLoanUsd,
      );
    }

    final money = moneyByCurrency;

    return _FinancialView(
      currencyCode: currency.currencyCode.toUpperCase(),
      moneyIn: _chartData(
        money?.moneyIn.nativeChart ?? const <String, double>{},
      ),
      distribution: _chartData(
        money?.distribution.nativeChart ?? const <String, double>{},
      ),
      availableMoney: money?.moneyIn.total ?? 0,
      savings: currency.savings.closing,
      investment: currency.investment.purchased,
      borrowing: currency.loan.disbursed,
      repayment: currency.loan.repaid,
      outstandingLoan: currency.loan.closingBalance,
    );
  }

  String money(double value) {
    return NumberFormat.simpleCurrency(
      name: currencyCode,
      decimalDigits: 2,
    ).format(value);
  }

  static List<_ChartDatum> _chartData(Map<String, double> source) {
    return source.entries
        .map(
          (entry) =>
              _ChartDatum(label: _chartLabel(entry.key), value: entry.value),
        )
        .toList(growable: false);
  }

  static String _chartLabel(String key) {
    return switch (key) {
      'savings_brought_forward' => 'Savings B/F',
      'cash_in' => 'Cash In',
      'transfer_in' => 'Transfer In',
      'loan_disbursement' => 'Loan Disbursement',
      'investment_proceeds' => 'Investment Proceeds',
      'withdrawal' => 'Withdrawal',
      'spending' => 'Spending',
      'investment' => 'Investment',
      'repayment' => 'Repayment',
      'savings' => 'Savings',
      _ => key,
    };
  }
}

class _ChartDatum {
  const _ChartDatum({required this.label, required this.value});

  final String label;
  final double value;
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.identity});

  final FinancialBehaviourIdentity identity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final identityColor = _FinancialColors.identity(identity.type);

    final icon = switch (identity.type) {
      FinancialBehaviourType.saver => Icons.savings_outlined,
      FinancialBehaviourType.investor => Icons.trending_up,
      FinancialBehaviourType.shopper => Icons.shopping_bag_outlined,
      FinancialBehaviourType.borrower => Icons.account_balance_outlined,
      FinancialBehaviourType.balanced => Icons.balance_outlined,
      FinancialBehaviourType.neutral => Icons.insights_outlined,
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: ScreenScalingService.scaleSize(context, 50),
            height: ScreenScalingService.scaleSize(context, 50),
            decoration: BoxDecoration(
              color: identityColor.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: ScreenScalingService.scaleSize(context, 25),
              color: identityColor,
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your behaviour',
                  style: AppTextStyles.tiny(context).copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
                Text(
                  identity.title,
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: ScreenScalingService.scaleSize(context, 5)),
                Text(
                  identity.description,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options
            .map(
              (currency) => Padding(
                padding: EdgeInsets.only(
                  right: ScreenScalingService.scaleSize(context, 8),
                ),
                child: _CurrencyTab(
                  currency: currency.toUpperCase(),
                  selected: currency.toUpperCase() == selected.toUpperCase(),
                  onTap: () {
                    onSelected(currency.toUpperCase());
                  },
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _CurrencyTab extends StatelessWidget {
  const _CurrencyTab({
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 15),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: ScreenScalingService.scaleSize(context, 16),
            vertical: ScreenScalingService.scaleSize(context, 8),
          ),
          decoration: BoxDecoration(
            color: selected
                ? primaryColor.withValues(alpha: 0.12)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(
              ScreenScalingService.scaleSize(context, 15),
            ),
            border: Border.all(
              color: selected
                  ? primaryColor.withValues(alpha: 0.09)
                  : theme.dividerColor.withValues(alpha: 0.09),
            ),
          ),
          child: Text(
            currency,
            style: AppTextStyles.small(context).copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? primaryColor : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
// class _CurrencyTab extends StatelessWidget {
//   const _CurrencyTab({
//     required this.currency,
//     required this.selected,
//     required this.onTap,
//   });

//   final String currency;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final primary = theme.colorScheme.primary;

//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 18),
//         ),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 180),
//           padding: EdgeInsets.symmetric(
//             horizontal: ScreenScalingService.scaleSize(context, 16),
//             vertical: ScreenScalingService.scaleSize(context, 8),
//           ),
//           decoration: BoxDecoration(
//             color: selected
//                 ? primary.withValues(alpha: 0.12)
//                 : theme.colorScheme.surface,
//             borderRadius: BorderRadius.circular(
//               ScreenScalingService.scaleSize(context, 18),
//             ),
//             border: Border.all(
//               color: selected
//                   ? primary
//                   : theme.colorScheme.outlineVariant.withValues(alpha: 0.09),
//             ),
//           ),
//           child: Text(
//             currency,
//             style: AppTextStyles.small(context).copyWith(
//               fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
//               color: selected ? primary : theme.colorScheme.onSurface,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

class _FinancialPositionCard extends StatelessWidget {
  const _FinancialPositionCard({required this.view});

  final _FinancialView view;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your financial position',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
          Text(
            'Balances and financial activity are shown separately',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

          Row(
            children: [
              Expanded(
                child: _PositionMetric(
                  icon: Icons.savings_outlined,
                  label: 'Savings',
                  value: view.money(view.savings),
                  caption: 'Closing balance',
                ),
              ),
              SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
              Expanded(
                child: _PositionMetric(
                  icon: Icons.trending_up,
                  label: 'Investment',
                  value: view.money(view.investment),
                  caption: 'Purchased FYTD',
                ),
              ),
            ],
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

          Row(
            children: [
              Expanded(
                child: _PositionMetric(
                  icon: Icons.call_received_outlined,
                  label: 'Borrowed',
                  value: view.money(view.borrowing),
                  caption: 'Disbursed FYTD',
                  color: Color.fromARGB(255, 25, 118, 210),
                ),
              ),
              SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
              Expanded(
                child: _PositionMetric(
                  icon: Icons.call_made_outlined,
                  label: 'Repaid',
                  value: view.money(view.repayment),
                  caption: 'Repaid FYTD',
                  color: Color.fromARGB(255, 25, 118, 210),
                ),
              ),
            ],
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

          _OutstandingLoanCard(value: view.money(view.outstandingLoan)),
        ],
      ),
    );
  }
}

class _PositionMetric extends StatelessWidget {
  const _PositionMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colors.primary;

    return Container(
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 12)),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: ScreenScalingService.scaleSize(context, 17),
                color: effectiveColor,
              ),
              SizedBox(width: ScreenScalingService.scaleSize(context, 6)),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.tiny(context).copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 2)),
          Text(
            caption,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OutstandingLoanCard extends StatelessWidget {
  const _OutstandingLoanCard({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 12)),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 14),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_outlined,
            size: ScreenScalingService.scaleSize(context, 20),
            color: colors.onSurfaceVariant,
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Outstanding loan',
                  style: AppTextStyles.tiny(context).copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Closing loan balance',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
          Text(
            subtitle,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 20)),
          child,
        ],
      ),
    );
  }
}

class _ActivityBarChart extends StatelessWidget {
  const _ActivityBarChart({required this.view});

  final _FinancialView view;

  @override
  Widget build(BuildContext context) {
    final values = view.moneyIn;
    final colors = Theme.of(context).colorScheme;

    final maximum = values.fold<double>(
      0,
      (current, item) => math.max(current, item.value),
    );

    final total = view.availableMoney;

    if (maximum <= 0) {
      return const _EmptyChart();
    }

    return Column(
      children: [
        SizedBox(
          height: ScreenScalingService.scaleSize(context, 240),
          child: BarChart(
            BarChartData(
              maxY: maximum * 1.18,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (_, _, rod, _) {
                    return BarTooltipItem(
                      view.money(rod.toY),
                      AppTextStyles.tinyNumber(context).copyWith(
                        color: colors.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();

                      if (index < 0 || index >= values.length) {
                        return const SizedBox.shrink();
                      }

                      final label = values[index].label;

                      final shortLabel = label.length <= 3
                          ? label
                          : label.substring(0, 3);

                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          shortLabel,
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colors.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i].value,
                        width: ScreenScalingService.scaleSize(context, 22),
                        color: _FinancialColors.activity(values[i].label),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: ScreenScalingService.scaleSize(context, 12)),
        for (final item in values)
          _ActivityLegendRow(
            label: item.label,
            amount: view.money(item.value),
            percentage: total > 0 ? item.value / total * 100 : 0,
            color: _FinancialColors.activity(item.label),
          ),
      ],
    );
  }
}

class _ActivityLegendRow extends StatelessWidget {
  const _ActivityLegendRow({
    required this.label,
    required this.amount,
    required this.percentage,
    required this.color,
  });

  final String label;
  final String amount;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ScreenScalingService.scaleSize(context, 5),
      ),
      child: Row(
        children: [
          Container(
            width: ScreenScalingService.scaleSize(context, 10),
            height: ScreenScalingService.scaleSize(context, 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
          Expanded(child: Text(label, style: AppTextStyles.tiny(context))),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 65),
            child: Text(
              '${percentage.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(context).copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 100),
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityMixChart extends StatelessWidget {
  const _ActivityMixChart({required this.view});

  final _FinancialView view;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final values = view.distribution;

    final pieValues = values
        .where((item) => item.value > 0)
        .toList(growable: false);

    final availableMoney = view.availableMoney;

    if (pieValues.isEmpty || availableMoney <= 0) {
      return const _EmptyChart();
    }

    return Column(
      children: [
        SizedBox(
          height: ScreenScalingService.scaleSize(context, 220),
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: ScreenScalingService.scaleSize(
                    context,
                    58,
                  ),
                  sectionsSpace: 2,
                  sections: [
                    for (final item in pieValues)
                      PieChartSectionData(
                        value: item.value,
                        color: _FinancialColors.activity(item.label),
                        radius: ScreenScalingService.scaleSize(context, 34),
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      view.money(availableMoney),
                      style: AppTextStyles.mediumNumber(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'available money',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final item in values)
          _DistributionLegendRow(
            item: item,
            availableMoney: availableMoney,
            view: view,
          ),
      ],
    );
  }
}

class _DistributionLegendRow extends StatelessWidget {
  const _DistributionLegendRow({
    required this.item,
    required this.availableMoney,
    required this.view,
  });

  final _ChartDatum item;
  final double availableMoney;
  final _FinancialView view;

  @override
  Widget build(BuildContext context) {
    final percentage = availableMoney > 0
        ? item.value / availableMoney * 100
        : 0.0;

    final color = _FinancialColors.activity(item.label);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ScreenScalingService.scaleSize(context, 5),
      ),
      child: Row(
        children: [
          Container(
            width: ScreenScalingService.scaleSize(context, 10),
            height: ScreenScalingService.scaleSize(context, 10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
          Expanded(child: Text(item.label, style: AppTextStyles.tiny(context))),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 65),
            child: Text(
              '${percentage.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 100),
            child: Text(
              view.money(item.value),
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldCard extends StatelessWidget {
  const _GoldCard({required this.summary});

  final FinancialBehaviour summary;

  @override
  Widget build(BuildContext context) {
    final gold = summary.gold;

    return _SectionCard(
      title: 'Gold',
      subtitle: 'Gold quantity is kept separate from currency values',
      child: Column(
        children: [
          _GoldRow(
            label: 'Opening',
            value: NumberFormatService.formatNumber(
              gold.openingQuantity,
              decimals: 6,
            ),
          ),
          _GoldRow(
            label: 'Purchased',
            value: NumberFormatService.formatNumber(
              gold.purchased,
              decimals: 6,
            ),
          ),
          _GoldRow(
            label: 'Sold',
            value: NumberFormatService.formatNumber(gold.sold, decimals: 6),
          ),
          _GoldRow(
            label: 'Transferred in',
            value: NumberFormatService.formatNumber(
              gold.transferredIn,
              decimals: 6,
            ),
          ),
          _GoldRow(
            label: 'Transferred out',
            value: NumberFormatService.formatNumber(
              gold.transferredOut,
              decimals: 6,
            ),
          ),
          Divider(height: ScreenScalingService.scaleSize(context, 24)),
          _GoldRow(
            label: 'Closing quantity',
            value: NumberFormatService.formatNumber(
              gold.closingQuantity,
              decimals: 6,
            ),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _GoldRow extends StatelessWidget {
  const _GoldRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ScreenScalingService.scaleSize(context, 5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.tiny(context).copyWith(
                color: emphasized ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: emphasized
                ? AppTextStyles.smallNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700)
                : AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: ScreenScalingService.scaleSize(context, 150),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: ScreenScalingService.scaleSize(context, 28),
              color: colors.onSurfaceVariant,
            ),
            SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
            Text(
              'No activity to display yet',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialColors {
  const _FinancialColors._();

  // Money sources
  static const cashIn = Color(0xFF2E7D32);

  static const transferIn = Color(0xFF00897B);

  static const loanDisbursement = Color(0xFF1976D2);

  static const investmentProceeds = Color(0xFFD4A017);

  static const broughtForward = Color(0xFF7B1FA2);

  // Money distribution
  static const withdrawal = Color(0xFF00897B);

  static const spending = Color(0xFFD32F2F);

  static const investment = Color(0xFFD4A017);

  static const repayment = Color(0xFF1976D2);

  static const savings = Color(0xFF7B1FA2);

  static const neutral = Color(0xFF607D8B);

  static Color activity(String label) {
    switch (label.toLowerCase()) {
      case 'savings b/f':
        return broughtForward;

      case 'cash in':
        return cashIn;

      case 'transfer in':
        return transferIn;

      case 'loan disbursement':
        return loanDisbursement;

      case 'investment proceeds':
        return investmentProceeds;

      case 'withdrawal':
        return withdrawal;

      case 'spending':
        return spending;

      case 'investment':
        return investment;

      case 'repayment':
        return repayment;

      case 'savings':
        return savings;

      default:
        return neutral;
    }
  }

  static Color identity(FinancialBehaviourType type) {
    switch (type) {
      case FinancialBehaviourType.saver:
        return savings;

      case FinancialBehaviourType.investor:
        return investment;

      case FinancialBehaviourType.shopper:
        return spending;

      case FinancialBehaviourType.borrower:
        return repayment;

      case FinancialBehaviourType.balanced:
      case FinancialBehaviourType.neutral:
        return neutral;
    }
  }
}

// import 'dart:math' as math;

// import 'package:fl_chart/fl_chart.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:intl/intl.dart';
// import 'package:ngoda/data_models/financial-intelligence/financial_behaviour.dart';
// import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_identity.dart';
// import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_overview_data.dart';
// import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
// import 'package:ngoda/data_models/financial-intelligence/financial_money_by_currency.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/services/screen_scaling_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/screens/financial-intelligence/provider/financial_behaviour_overview_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_empty_state.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class FinancialIntelligenceOverviewScreen extends ConsumerStatefulWidget {
//   const FinancialIntelligenceOverviewScreen({super.key});

//   @override
//   ConsumerState<FinancialIntelligenceOverviewScreen> createState() =>
//       _FinancialIntelligenceOverviewScreenState();
// }

// class _FinancialIntelligenceOverviewScreenState
//     extends ConsumerState<FinancialIntelligenceOverviewScreen> {
//   String _selection = 'ALL';

//   @override
//   Widget build(BuildContext context) {
//     final result = ref.watch(financialBehaviourOverviewProvider);

//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             ViewHeader(
//               title: 'Financial Behaviour',
//               onClose: () {
//                 ref.invalidate(financialBehaviourOverviewProvider);
//                 context.pop();
//               },
//             ),
//             Expanded(
//               child: RefreshIndicator(
//                 onRefresh: () async {
//                   ref.invalidate(financialBehaviourOverviewProvider);
//                   await ref.read(financialBehaviourOverviewProvider.future);
//                 },
//                 child: result.when(
//                   loading: () => const AppLoader(
//                     message: 'Loading financial behaviour',
//                     fullScreen: true,
//                   ),
//                   error: (error, _) => AppErrorState(message: error.toString()),
//                   data: (data) {
//                     if (data.hasError) {
//                       return AppErrorState(message: data.error);
//                     }

//                     final overview = data.result;

//                     if (overview == null ||
//                         overview.summary.sortedCurrencyList.isEmpty) {
//                       return const AppEmptyState();
//                     }

//                     return _OverviewBody(
//                       data: overview,
//                       selection: _selection,
//                       onSelectionChanged: (value) {
//                         setState(() => _selection = value);
//                       },
//                       onViewMonthlyActivity: () {
//                         context.push('profile/financial-intelligence/periodic');
//                       },
//                     );
//                   },
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _OverviewBody extends StatelessWidget {
//   final FinancialBehaviourOverviewData data;
//   final String selection;
//   final ValueChanged<String> onSelectionChanged;
//   final VoidCallback? onViewMonthlyActivity;

//   const _OverviewBody({
//     required this.data,
//     required this.selection,
//     required this.onSelectionChanged,
//     required this.onViewMonthlyActivity,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final summary = data.summary;

//     final selectedCurrency = selection == 'ALL'
//         ? null
//         : summary.getByCurrency(selection);

//     final selectedMoney = selection == 'ALL'
//         ? null
//         : summary.getMoneyByCurrency(selection);

//     final view = _FinancialView.from(summary, selectedCurrency, selectedMoney);

//     final options = <String>[
//       'ALL',
//       ...summary.moneyCurrencyDisplay
//           .where((currency) => currency.toLowerCase() != 'gold')
//           .map((currency) => currency.toUpperCase()),
//     ];

//     return RefreshIndicator(
//       onRefresh: () async {
//         await ProviderScope.containerOf(
//           context,
//         ).refresh(financialBehaviourOverviewProvider.future);
//       },
//       child: ListView(
//         padding: EdgeInsets.fromLTRB(
//           ScreenScalingService.scaleSize(context, 16),
//           ScreenScalingService.scaleSize(context, 8),
//           ScreenScalingService.scaleSize(context, 16),
//           ScreenScalingService.scaleSize(context, 32),
//         ),
//         children: [
//           Text(
//             'FY ${summary.fiscalYear}  •  '
//             '${_financialYearPeriodLabel(summary.currentPeriod)}',
//             style: AppTextStyles.small(context).copyWith(
//               color: Theme.of(context).colorScheme.onSurfaceVariant,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _IdentityCard(identity: data.identity),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           Text(
//             'View by currency',
//             style: AppTextStyles.small(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
//           _CurrencySelector(
//             options: options,
//             selected: selection,
//             onSelected: onSelectionChanged,
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
//           Text(
//             selection == 'ALL'
//                 ? 'All currencies shown in USD equivalent'
//                 : '$selection shown in its native currency',
//             style: AppTextStyles.tiny(
//               context,
//             ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _PositionSummary(view: view),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _SectionCard(
//             title: 'Where your money came from',
//             subtitle: 'Sources of available money',
//             child: _ActivityBarChart(view: view),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _SectionCard(
//             title: 'How your money was distributed',
//             subtitle: 'Withdrawal, spending, investment, repayment and savings',
//             child: _ActivityMixChart(view: view),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _GoldCard(summary: summary),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 12)),
//           FilledButton.tonalIcon(
//             onPressed: onViewMonthlyActivity,
//             icon: const Icon(Icons.calendar_month_outlined),
//             label: Text(
//               'View monthly activity',
//               style: AppTextStyles.small(
//                 context,
//               ).copyWith(fontWeight: FontWeight.w600),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// String _financialYearPeriodLabel(int currentPeriod) {
//   if (currentPeriod <= 0) {
//     return '';
//   }

//   final safePeriod = currentPeriod.clamp(1, 12).toInt();

//   final startMonth = DateFormat('MMM').format(DateTime(2000, 1));

//   final endMonth = DateFormat('MMM').format(DateTime(2000, safePeriod));

//   if (safePeriod == 1) {
//     return startMonth;
//   }

//   return '$startMonth – $endMonth';
// }

// class _FinancialView {
//   final String currencyCode;
//   final List<_ChartDatum> moneyIn;
//   final List<_ChartDatum> distribution;
//   final double availableMoney;
//   final double savings;
//   final double investment;
//   final double loan;

//   const _FinancialView({
//     required this.currencyCode,
//     required this.moneyIn,
//     required this.distribution,
//     required this.availableMoney,
//     required this.savings,
//     required this.investment,
//     required this.loan,
//   });

//   factory _FinancialView.from(
//     FinancialBehaviour summary,
//     FinancialCurrencySummary? currency,
//     FinancialMoneyByCurrency? moneyByCurrency,
//   ) {
//     if (currency == null) {
//       return _FinancialView(
//         currencyCode: 'USD',
//         moneyIn: _chartData(summary.moneyInChartUsd),
//         distribution: _chartData(summary.distributionChartUsd),
//         availableMoney: summary.moneyIn.totalUsd,
//         savings: summary.totalClosingSavingsUsd,
//         investment: summary.totalInvestmentPurchaseUsd,
//         loan: summary.totalClosingLoanUsd,
//       );
//     }

//     final money = moneyByCurrency;

//     return _FinancialView(
//       currencyCode: currency.currencyCode.toUpperCase(),
//       moneyIn: _chartData(
//         money?.moneyIn.nativeChart ?? const <String, double>{},
//       ),
//       distribution: _chartData(
//         money?.distribution.nativeChart ?? const <String, double>{},
//       ),
//       availableMoney: money?.moneyIn.total ?? 0,
//       savings: currency.savings.closing,
//       investment: currency.investment.purchased,
//       loan: currency.loan.closingBalance,
//     );
//   }

//   String money(double value) => NumberFormat.simpleCurrency(
//     name: currencyCode,
//     decimalDigits: 2,
//   ).format(value);

//   static List<_ChartDatum> _chartData(Map<String, double> source) {
//     return source.entries
//         .map(
//           (entry) =>
//               _ChartDatum(label: _chartLabel(entry.key), value: entry.value),
//         )
//         .toList(growable: false);
//   }

//   static String _chartLabel(String key) => switch (key) {
//     'savings_brought_forward' => 'Savings B/F',
//     'cash_in' => 'Cash In',
//     'transfer_in' => 'Transfer In',
//     'loan_disbursement' => 'Loan Disbursement',
//     'investment_proceeds' => 'Investment Proceeds',
//     'withdrawal' => 'Withdrawal',
//     'spending' => 'Spending',
//     'investment' => 'Investment',
//     'repayment' => 'Repayment',
//     'savings' => 'Savings',
//     _ => key,
//   };
// }

// class _ChartDatum {
//   final String label;
//   final double value;

//   const _ChartDatum({required this.label, required this.value});
// }

// class _IdentityCard extends StatelessWidget {
//   final FinancialBehaviourIdentity identity;

//   const _IdentityCard({required this.identity});

//   @override
//   Widget build(BuildContext context) {
//     final identityColor = _FinancialColors.identity(identity.type);

//     final icon = switch (identity.type) {
//       FinancialBehaviourType.saver => Icons.savings_outlined,
//       FinancialBehaviourType.investor => Icons.trending_up,
//       FinancialBehaviourType.shopper => Icons.shopping_bag_outlined,
//       FinancialBehaviourType.borrower => Icons.account_balance_outlined,
//       FinancialBehaviourType.balanced => Icons.balance_outlined,
//       FinancialBehaviourType.neutral => Icons.insights_outlined,
//     };

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 16),
//         ),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: ScreenScalingService.scaleSize(context, 48),
//             height: ScreenScalingService.scaleSize(context, 48),
//             decoration: BoxDecoration(
//               color: identityColor.withValues(alpha: 0.14),
//               shape: BoxShape.circle,
//             ),
//             child: Icon(
//               icon,
//               size: ScreenScalingService.scaleSize(context, 24),
//               color: identityColor,
//             ),
//           ),
//           SizedBox(width: ScreenScalingService.scaleSize(context, 14)),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Your behaviour',
//                   style: AppTextStyles.tiny(context).copyWith(
//                     color: Theme.of(context).colorScheme.onSurfaceVariant,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
//                 Text(
//                   identity.title,
//                   style: AppTextStyles.medium(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w700),
//                 ),
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 4)),
//                 Text(
//                   identity.description,
//                   style: AppTextStyles.tiny(context).copyWith(
//                     color: Theme.of(context).colorScheme.onSurfaceVariant,
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

// class _CurrencySelector extends StatelessWidget {
//   final List<String> options;
//   final String selected;
//   final ValueChanged<String> onSelected;

//   const _CurrencySelector({
//     required this.options,
//     required this.selected,
//     required this.onSelected,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         children: options
//             .map(
//               (currency) => Padding(
//                 padding: EdgeInsets.only(
//                   right: ScreenScalingService.scaleSize(context, 8),
//                 ),
//                 child: _CurrencyTab(
//                   currency: currency.toUpperCase(),
//                   selected: currency.toUpperCase() == selected.toUpperCase(),
//                   onTap: () => onSelected(currency.toUpperCase()),
//                 ),
//               ),
//             )
//             .toList(growable: false),
//       ),
//     );
//   }
// }

// class _CurrencyTab extends StatelessWidget {
//   final String currency;
//   final bool selected;
//   final VoidCallback onTap;

//   const _CurrencyTab({
//     required this.currency,
//     required this.selected,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final primaryColor = theme.colorScheme.primary;

//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 15),
//         ),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 180),
//           padding: EdgeInsets.symmetric(
//             horizontal: ScreenScalingService.scaleSize(context, 16),
//             vertical: ScreenScalingService.scaleSize(context, 8),
//           ),
//           decoration: BoxDecoration(
//             color: selected
//                 ? primaryColor.withValues(alpha: 0.12)
//                 : theme.colorScheme.surface,
//             borderRadius: BorderRadius.circular(
//               ScreenScalingService.scaleSize(context, 15),
//             ),
//             border: Border.all(
//               color: selected
//                   ? primaryColor
//                   : theme.dividerColor.withValues(alpha: 0.4),
//             ),
//           ),
//           child: Text(
//             currency,
//             style: AppTextStyles.small(context).copyWith(
//               fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
//               color: selected
//                   ? primaryColor
//                   : theme.textTheme.bodyMedium?.color,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _PositionSummary extends StatelessWidget {
//   final _FinancialView view;

//   const _PositionSummary({required this.view});

//   @override
//   Widget build(BuildContext context) => Row(
//     children: [
//       Expanded(
//         child: _MetricCard(
//           label: 'Savings',
//           value: view.money(view.savings),
//           caption: 'closing',
//         ),
//       ),
//       SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
//       Expanded(
//         child: _MetricCard(
//           label: 'Investment',
//           value: view.money(view.investment),
//           caption: 'purchased FYTD',
//         ),
//       ),
//       SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
//       Expanded(
//         child: _MetricCard(
//           label: 'Loan',
//           value: view.money(view.loan),
//           caption: 'outstanding',
//         ),
//       ),
//     ],
//   );
// }

// class _MetricCard extends StatelessWidget {
//   final String label;
//   final String value;
//   final String caption;

//   const _MetricCard({
//     required this.label,
//     required this.value,
//     required this.caption,
//   });

//   @override
//   Widget build(BuildContext context) => Container(
//     padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 12)),
//     decoration: BoxDecoration(
//       color: Theme.of(context).cardColor,
//       borderRadius: BorderRadius.circular(
//         ScreenScalingService.scaleSize(context, 14),
//       ),
//     ),
//     child: Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: AppTextStyles.tiny(context).copyWith(
//             color: Theme.of(context).colorScheme.onSurfaceVariant,
//             fontWeight: FontWeight.w600,
//           ),
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 6)),
//         FittedBox(
//           fit: BoxFit.scaleDown,
//           alignment: Alignment.centerLeft,
//           child: Text(
//             value,
//             style: AppTextStyles.smallNumber(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700),
//           ),
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 2)),
//         Text(
//           caption,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
//         ),
//       ],
//     ),
//   );
// }

// class _SectionCard extends StatelessWidget {
//   final String title;
//   final String subtitle;
//   final Widget child;

//   const _SectionCard({
//     required this.title,
//     required this.subtitle,
//     required this.child,
//   });

//   @override
//   Widget build(BuildContext context) => Container(
//     width: double.infinity,
//     padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
//     decoration: BoxDecoration(
//       color: Theme.of(context).cardColor,
//       borderRadius: BorderRadius.circular(
//         ScreenScalingService.scaleSize(context, 16),
//       ),
//     ),
//     child: Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           title,
//           style: AppTextStyles.medium(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
//         Text(
//           subtitle,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 20)),
//         child,
//       ],
//     ),
//   );
// }

// class _ActivityBarChart extends StatelessWidget {
//   final _FinancialView view;

//   const _ActivityBarChart({required this.view});

//   @override
//   Widget build(BuildContext context) {
//     final values = view.moneyIn;

//     final maximum = values.fold<double>(
//       0,
//       (m, item) => math.max(m, item.value),
//     );

//     final total = view.availableMoney;

//     final colors = Theme.of(context).colorScheme;

//     if (maximum <= 0) {
//       return const _EmptyChart();
//     }

//     return Column(
//       children: [
//         SizedBox(
//           height: ScreenScalingService.scaleSize(context, 240),
//           child: BarChart(
//             BarChartData(
//               maxY: maximum * 1.18,
//               alignment: BarChartAlignment.spaceAround,
//               gridData: const FlGridData(show: false),
//               borderData: FlBorderData(show: false),
//               barTouchData: BarTouchData(
//                 touchTooltipData: BarTouchTooltipData(
//                   getTooltipItem: (_, _, rod, _) {
//                     return BarTooltipItem(
//                       view.money(rod.toY),
//                       AppTextStyles.tinyNumber(context).copyWith(
//                         color: colors.onInverseSurface,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     );
//                   },
//                 ),
//               ),
//               titlesData: FlTitlesData(
//                 leftTitles: const AxisTitles(
//                   sideTitles: SideTitles(showTitles: false),
//                 ),
//                 topTitles: const AxisTitles(
//                   sideTitles: SideTitles(showTitles: false),
//                 ),
//                 rightTitles: const AxisTitles(
//                   sideTitles: SideTitles(showTitles: false),
//                 ),
//                 bottomTitles: AxisTitles(
//                   sideTitles: SideTitles(
//                     showTitles: true,
//                     getTitlesWidget: (value, meta) {
//                       final index = value.toInt();

//                       if (index < 0 || index >= values.length) {
//                         return const SizedBox.shrink();
//                       }

//                       return SideTitleWidget(
//                         meta: meta,
//                         child: Text(
//                           values[index].label.substring(0, 3),
//                           style: AppTextStyles.tiny(
//                             context,
//                           ).copyWith(color: colors.onSurfaceVariant),
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ),
//               barGroups: [
//                 for (var i = 0; i < values.length; i++)
//                   BarChartGroupData(
//                     x: i,
//                     barRods: [
//                       BarChartRodData(
//                         toY: values[i].value,
//                         width: ScreenScalingService.scaleSize(context, 22),
//                         color: _FinancialColors.activity(values[i].label),
//                         borderRadius: const BorderRadius.vertical(
//                           top: Radius.circular(6),
//                         ),
//                       ),
//                     ],
//                   ),
//               ],
//             ),
//           ),
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 12)),
//         for (final item in values)
//           _ActivityLegendRow(
//             label: item.label,
//             amount: view.money(item.value),
//             percentage: total > 0 ? item.value / total * 100 : 0,
//             color: _FinancialColors.activity(item.label),
//           ),
//       ],
//     );
//   }
// }

// class _ActivityLegendRow extends StatelessWidget {
//   final String label;
//   final String amount;
//   final double percentage;
//   final Color color;

//   const _ActivityLegendRow({
//     required this.label,
//     required this.amount,
//     required this.percentage,
//     required this.color,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     return Padding(
//       padding: EdgeInsets.symmetric(
//         vertical: ScreenScalingService.scaleSize(context, 5),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: ScreenScalingService.scaleSize(context, 10),
//             height: ScreenScalingService.scaleSize(context, 10),
//             decoration: BoxDecoration(
//               color: color,
//               borderRadius: BorderRadius.circular(3),
//             ),
//           ),
//           SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
//           Expanded(
//             child: Text(
//               label,
//               style: AppTextStyles.tiny(
//                 context,
//               ).copyWith(color: colors.onSurface),
//             ),
//           ),
//           SizedBox(
//             width: ScreenScalingService.scaleSize(context, 70),
//             child: Text(
//               '${percentage.toStringAsFixed(2)}%',
//               textAlign: TextAlign.right,
//               style: AppTextStyles.tinyNumber(context).copyWith(
//                 color: colors.onSurfaceVariant,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//           SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
//           SizedBox(
//             width: ScreenScalingService.scaleSize(context, 100),
//             child: Text(
//               amount,
//               textAlign: TextAlign.right,
//               style: AppTextStyles.tinyNumber(
//                 context,
//               ).copyWith(color: colors.onSurface, fontWeight: FontWeight.w600),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ActivityMixChart extends StatelessWidget {
//   final _FinancialView view;

//   const _ActivityMixChart({required this.view});

//   @override
//   Widget build(BuildContext context) {
//     final scheme = Theme.of(context).colorScheme;

//     final values = view.distribution;

//     final pieValues = values.where((item) => item.value > 0).toList();

//     final availableMoney = view.availableMoney;

//     if (pieValues.isEmpty || availableMoney <= 0) {
//       return const _EmptyChart();
//     }

//     return Column(
//       children: [
//         SizedBox(
//           height: 220,
//           child: Stack(
//             alignment: Alignment.center,
//             children: [
//               PieChart(
//                 PieChartData(
//                   centerSpaceRadius: 58,
//                   sectionsSpace: 2,
//                   sections: [
//                     for (var i = 0; i < pieValues.length; i++)
//                       PieChartSectionData(
//                         value: pieValues[i].value,
//                         color: _FinancialColors.activity(pieValues[i].label),
//                         radius: 34,
//                         showTitle: false,
//                       ),
//                   ],
//                 ),
//               ),
//               Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Text(
//                     view.money(availableMoney),
//                     style: AppTextStyles.mediumNumber(
//                       context,
//                     ).copyWith(fontWeight: FontWeight.w700),
//                   ),
//                   Text(
//                     'available money',
//                     style: AppTextStyles.tiny(
//                       context,
//                     ).copyWith(color: scheme.onSurfaceVariant),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//         for (var i = 0; i < values.length; i++)
//           Padding(
//             padding: EdgeInsets.symmetric(
//               vertical: ScreenScalingService.scaleSize(context, 4),
//             ),
//             child: Row(
//               children: [
//                 Container(
//                   width: 10,
//                   height: 10,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     color: _FinancialColors.activity(values[i].label),
//                   ),
//                 ),
//                 SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
//                 Expanded(
//                   child: Text(
//                     values[i].label,
//                     style: AppTextStyles.tiny(context),
//                   ),
//                 ),
//                 Text(
//                   '${(values[i].value / availableMoney * 100).toStringAsFixed(2)}%',
//                   style: AppTextStyles.tinyNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w600),
//                 ),
//                 SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
//                 Text(
//                   view.money(values[i].value),
//                   style: AppTextStyles.tinyNumber(
//                     context,
//                   ).copyWith(fontWeight: FontWeight.w600),
//                 ),
//               ],
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _GoldCard extends StatelessWidget {
//   final FinancialBehaviour summary;

//   const _GoldCard({required this.summary});

//   @override
//   Widget build(BuildContext context) {
//     final gold = summary.gold;

//     return _SectionCard(
//       title: 'Gold',
//       subtitle: 'Quantity is kept separate from currency values',
//       child: Column(
//         children: [
//           _GoldRow(
//             label: 'Opening',
//             value: NumberFormatService.formatNumber(
//               gold.openingQuantity,
//               decimals: 6,
//             ),
//           ),
//           _GoldRow(
//             label: 'Purchased',
//             value: NumberFormatService.formatNumber(
//               gold.purchased,
//               decimals: 6,
//             ),
//           ),
//           _GoldRow(
//             label: 'Sold',
//             value: NumberFormatService.formatNumber(gold.sold, decimals: 6),
//           ),
//           _GoldRow(
//             label: 'Transferred in',
//             value: NumberFormatService.formatNumber(
//               gold.transferredIn,
//               decimals: 6,
//             ),
//           ),
//           _GoldRow(
//             label: 'Transferred out',
//             value: NumberFormatService.formatNumber(
//               gold.transferredOut,
//               decimals: 6,
//             ),
//           ),
//           Divider(height: ScreenScalingService.scaleSize(context, 24)),
//           _GoldRow(
//             label: 'Closing quantity',
//             value: NumberFormatService.formatNumber(
//               gold.closingQuantity,
//               decimals: 6,
//             ),
//             emphasized: true,
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _GoldRow extends StatelessWidget {
//   final String label;
//   final String value;
//   final bool emphasized;

//   const _GoldRow({
//     required this.label,
//     required this.value,
//     this.emphasized = false,
//   });

//   @override
//   Widget build(BuildContext context) => Padding(
//     padding: EdgeInsets.symmetric(
//       vertical: ScreenScalingService.scaleSize(context, 5),
//     ),
//     child: Row(
//       children: [
//         Expanded(
//           child: Text(
//             label,
//             style: AppTextStyles.tiny(context).copyWith(
//               color: Theme.of(context).colorScheme.onSurfaceVariant,
//               fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
//             ),
//           ),
//         ),
//         Text(
//           value,
//           style: emphasized
//               ? AppTextStyles.smallNumber(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700)
//               : AppTextStyles.tinyNumber(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w600),
//         ),
//       ],
//     ),
//   );
// }

// class _EmptyChart extends StatelessWidget {
//   const _EmptyChart();

//   @override
//   Widget build(BuildContext context) => SizedBox(
//     height: ScreenScalingService.scaleSize(context, 160),
//     child: Center(
//       child: Text(
//         'No activity to display yet',
//         style: AppTextStyles.tiny(
//           context,
//         ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
//       ),
//     ),
//   );
// }

// class _FinancialColors {
//   const _FinancialColors._();

//   // Money sources
//   static const cashIn = Color(0xFF2E7D32);

//   static const transferIn = Color(0xFF00897B);

//   static const loanDisbursement = Color(0xFF1976D2);

//   static const investmentProceeds = Color(0xFFD4A017);

//   static const broughtForward = Color(0xFF7B1FA2);

//   // Money distribution
//   static const withdrawal = Color(0xFF00897B);

//   static const spending = Color(0xFFD32F2F);

//   static const investment = Color(0xFFD4A017);

//   static const repayment = Color(0xFF1976D2);

//   static const savings = Color(0xFF7B1FA2);

//   static const neutral = Color(0xFF607D8B);

//   static Color activity(String label) {
//     switch (label.toLowerCase()) {
//       case 'savings b/f':
//         return broughtForward;

//       case 'cash in':
//         return cashIn;

//       case 'transfer in':
//         return transferIn;

//       case 'loan disbursement':
//         return loanDisbursement;

//       case 'investment proceeds':
//         return investmentProceeds;

//       case 'withdrawal':
//         return withdrawal;

//       case 'spending':
//         return spending;

//       case 'investment':
//         return investment;

//       case 'repayment':
//         return repayment;

//       case 'savings':
//         return savings;

//       default:
//         return neutral;
//     }
//   }

//   static Color identity(FinancialBehaviourType type) {
//     switch (type) {
//       case FinancialBehaviourType.saver:
//         return savings;

//       case FinancialBehaviourType.investor:
//         return investment;

//       case FinancialBehaviourType.shopper:
//         return spending;

//       case FinancialBehaviourType.borrower:
//         return repayment;

//       case FinancialBehaviourType.balanced:
//       case FinancialBehaviourType.neutral:
//         return neutral;
//     }
//   }
// }
