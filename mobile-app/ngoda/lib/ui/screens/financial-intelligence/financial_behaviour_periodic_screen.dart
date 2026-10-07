import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_identity.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_period.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/periodic_financial_behaviour.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/financial-intelligence/provider/periodic_financial_behaviour_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FinancialBehaviourPeriodicScreen extends ConsumerStatefulWidget {
  const FinancialBehaviourPeriodicScreen({super.key});

  @override
  ConsumerState<FinancialBehaviourPeriodicScreen> createState() =>
      _FinancialBehaviourPeriodicScreenState();
}

class _FinancialBehaviourPeriodicScreenState
    extends ConsumerState<FinancialBehaviourPeriodicScreen> {
  String _selection = 'ALL';
  int? _selectedPeriod;

  Future<void> _refresh() async {
    ref.invalidate(periodicFinancialBehaviourProvider);

    await ref.read(periodicFinancialBehaviourProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(periodicFinancialBehaviourProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Financial Behaviour',
              onClose: () {
                ref.invalidate(periodicFinancialBehaviourProvider);

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

                  final data = response.result;

                  if (data == null || data.completedPeriods.isEmpty) {
                    return const AppEmptyState();
                  }

                  final options = data.selectionList;

                  final selection = options.contains(_selection)
                      ? _selection
                      : 'ALL';

                  final selectedPeriod = _resolveSelectedPeriod(data);

                  final selectedPeriodData = data.getByPeriod(selectedPeriod);

                  if (selectedPeriodData == null) {
                    return const AppEmptyState();
                  }

                  final view = _FinancialPeriodView.from(
                    selectedPeriodData,
                    selection,
                  );

                  final trend = data.trend(selection);

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        ScreenScalingService.scaleSize(context, 16),
                        ScreenScalingService.scaleSize(context, 8),
                        ScreenScalingService.scaleSize(context, 16),
                        ScreenScalingService.scaleSize(context, 32),
                      ),
                      children: [
                        _FiscalYearHeader(
                          fiscalYear: data.fiscalYear,
                          selectedPeriod: selectedPeriod,
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 20),
                        ),

                        Text(
                          'View by currency',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 8),
                        ),

                        _CurrencySelector(
                          options: options,
                          selected: selection,
                          onSelected: (value) {
                            setState(() {
                              _selection = value;
                            });
                          },
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 8),
                        ),

                        _CurrencyExplanation(selection: selection),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 24),
                        ),

                        Text(
                          'Financial progress',
                          style: AppTextStyles.medium(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 4),
                        ),

                        Text(
                          'Tap a month on either trend chart to view that month\'s financial report.',
                          style: AppTextStyles.tiny(context).copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 20),
                        ),

                        _SelectedMonthHeader(
                          period: selectedPeriod,
                          isCurrentPeriod: selectedPeriodData.isCurrentPeriod,
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 12),
                        ),

                        _IdentityCard(identity: selectedPeriodData.identity),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 16),
                        ),

                        _MonthlyPositionCard(view: view),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 24),
                        ),

                        _TrendCard(
                          title: 'Where your money came from',
                          subtitle: 'Sources of available money by month',
                          currencyCode: view.currencyCode,
                          points: trend,
                          metrics: _moneyInTrendMetrics,
                          selectedPeriod: selectedPeriod,
                          onPeriodSelected: _selectPeriod,
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 12),
                        ),

                        _SectionCard(
                          title: '${_monthName(selectedPeriod)} money sources',
                          subtitle: 'Sources of available money',
                          child: _MoneyInBarChart(view: view),
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 24),
                        ),

                        _TrendCard(
                          title: 'How your money was distributed',
                          subtitle:
                              'Withdrawal, spending, investment, loan repayment and savings by month',
                          currencyCode: view.currencyCode,
                          points: trend,
                          metrics: _distributionTrendMetrics,
                          selectedPeriod: selectedPeriod,
                          onPeriodSelected: _selectPeriod,
                        ),

                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 12),
                        ),

                        _SectionCard(
                          title: '${_monthName(selectedPeriod)} distribution',
                          subtitle:
                              'Withdrawal, spending, investment, loan repayment and savings',
                          child: _DistributionChart(view: view),
                        ),
                      ],
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

  int _resolveSelectedPeriod(PeriodicFinancialBehaviour data) {
    if (_selectedPeriod != null &&
        data.completedPeriods.any((item) => item.period == _selectedPeriod)) {
      return _selectedPeriod!;
    }

    if (data.getByPeriod(data.currentPeriod) != null) {
      return data.currentPeriod;
    }

    return data.completedPeriods.last.period;
  }

  void _selectPeriod(int period) {
    if (_selectedPeriod == period) {
      return;
    }

    setState(() {
      _selectedPeriod = period;
    });
  }
}

class _FiscalYearHeader extends StatelessWidget {
  const _FiscalYearHeader({
    required this.fiscalYear,
    required this.selectedPeriod,
  });

  final int fiscalYear;
  final int selectedPeriod;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
            'FY $fiscalYear  •  ${_monthName(selectedPeriod)}',
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

class _CurrencyExplanation extends StatelessWidget {
  const _CurrencyExplanation({required this.selection});

  final String selection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
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
                : '${_currencyDisplay(selection)} shown in its native currency',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _FinancialPeriodView {
  const _FinancialPeriodView({
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

  /// Closing savings position for this period.
  final double savings;

  /// Investment purchases during this period.
  final double investment;

  /// New borrowing / loan disbursement during this period.
  ///
  /// This is deliberately independent from repayment.
  final double borrowing;

  /// Loan repayments during this period.
  ///
  /// A user can have repayment without borrowing in the same period.
  final double repayment;

  /// Closing loan balance for this period.
  final double outstandingLoan;

  factory _FinancialPeriodView.from(
    FinancialBehaviourPeriod period,
    String selection,
  ) {
    if (selection.toUpperCase() == 'ALL') {
      return _FinancialPeriodView(
        currencyCode: 'USD',
        moneyIn: _chartData(period.moneyIn.usdChart),
        distribution: _chartData(period.distribution.usdChart),
        availableMoney: period.moneyIn.totalUsd,
        savings: period.all.closingSavingsUsd,
        investment: period.all.investmentUsd,
        borrowing: period.all.borrowingUsd,
        repayment: period.all.repaymentUsd,
        outstandingLoan: period.all.closingLoanBalanceUsd,
      );
    }

    final FinancialCurrencySummary? currency = period.getCurrency(selection);

    final money = period.getMoneyByCurrency(selection);

    return _FinancialPeriodView(
      currencyCode: selection.toUpperCase(),
      moneyIn: _chartData(
        money?.moneyIn.nativeChart ?? const <String, double>{},
      ),
      distribution: _chartData(
        money?.distribution.nativeChart ?? const <String, double>{},
      ),
      availableMoney: money?.moneyIn.total ?? 0,
      savings: currency?.savings.closing ?? 0,
      investment: currency?.investment.purchased ?? 0,
      borrowing: currency?.loan.disbursed ?? 0,
      repayment: currency?.loan.repaid ?? 0,
      outstandingLoan: currency?.loan.closingBalance ?? 0,
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

class _TrendMetric {
  const _TrendMetric({
    required this.key,
    required this.label,
    required this.color,
    required this.moneyIn,
  });

  final String key;
  final String label;
  final Color color;
  final bool moneyIn;

  double value(FinancialPeriodTrendPoint point) {
    final values = moneyIn ? point.moneyIn : point.distribution;

    return values[key] ?? 0;
  }
}

const _moneyInTrendMetrics = <_TrendMetric>[
  _TrendMetric(
    key: 'savings_brought_forward',
    label: 'Savings B/F',
    color: _FinancialColors.broughtForward,
    moneyIn: true,
  ),
  _TrendMetric(
    key: 'cash_in',
    label: 'Cash In',
    color: _FinancialColors.cashIn,
    moneyIn: true,
  ),
  _TrendMetric(
    key: 'transfer_in',
    label: 'Transfer In',
    color: _FinancialColors.transferIn,
    moneyIn: true,
  ),
  _TrendMetric(
    key: 'loan_disbursement',
    label: 'Loan Disbursement',
    color: _FinancialColors.loanDisbursement,
    moneyIn: true,
  ),
  _TrendMetric(
    key: 'investment_proceeds',
    label: 'Investment Proceeds',
    color: _FinancialColors.investmentProceeds,
    moneyIn: true,
  ),
];

const _distributionTrendMetrics = <_TrendMetric>[
  _TrendMetric(
    key: 'withdrawal',
    label: 'Withdrawal',
    color: _FinancialColors.withdrawal,
    moneyIn: false,
  ),
  _TrendMetric(
    key: 'spending',
    label: 'Spending',
    color: _FinancialColors.spending,
    moneyIn: false,
  ),
  _TrendMetric(
    key: 'investment',
    label: 'Investment',
    color: _FinancialColors.investment,
    moneyIn: false,
  ),
  _TrendMetric(
    key: 'repayment',
    label: 'Repayment',
    color: _FinancialColors.repayment,
    moneyIn: false,
  ),
  _TrendMetric(
    key: 'savings',
    label: 'Savings',
    color: _FinancialColors.savings,
    moneyIn: false,
  ),
];

class _SelectedMonthHeader extends StatelessWidget {
  const _SelectedMonthHeader({
    required this.period,
    required this.isCurrentPeriod,
  });

  final int period;
  final bool isCurrentPeriod;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            '${_monthName(period)} report',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (isCurrentPeriod)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenScalingService.scaleSize(context, 10),
              vertical: ScreenScalingService.scaleSize(context, 5),
            ),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(
                ScreenScalingService.scaleSize(context, 12),
              ),
            ),
            child: Text(
              'Current',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colors.primary, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
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
            width: ScreenScalingService.scaleSize(context, 48),
            height: ScreenScalingService.scaleSize(context, 48),
            decoration: BoxDecoration(
              color: identityColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: ScreenScalingService.scaleSize(context, 24),
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
                SizedBox(height: ScreenScalingService.scaleSize(context, 4)),
                Text(
                  _periodIdentityDescription(identity.type),
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

class _MonthlyPositionCard extends StatelessWidget {
  const _MonthlyPositionCard({required this.view});

  final _FinancialPeriodView view;

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
            'This month',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
          Text(
            'Borrowing, repayment and outstanding loan are shown separately.',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
          Row(
            children: [
              Expanded(
                child: _PositionMetric(
                  label: 'Savings',
                  value: view.money(view.savings),
                  caption: 'Closing balance',
                  icon: Icons.savings_outlined,
                  color: _FinancialColors.savings,
                ),
              ),
              SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
              Expanded(
                child: _PositionMetric(
                  label: 'Investment',
                  value: view.money(view.investment),
                  caption: 'Purchased',
                  icon: Icons.trending_up,
                  color: _FinancialColors.investment,
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
          Row(
            children: [
              Expanded(
                child: _PositionMetric(
                  label: 'Borrowed',
                  value: view.money(view.borrowing),
                  caption: 'Loan disbursed',
                  icon: Icons.call_received_outlined,
                  color: _FinancialColors.loanDisbursement,
                ),
              ),
              SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
              Expanded(
                child: _PositionMetric(
                  label: 'Repaid',
                  value: view.money(view.repayment),
                  caption: 'Loan repayment',
                  icon: Icons.call_made_outlined,
                  color: _FinancialColors.repayment,
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
          _OutstandingLoanRow(value: view.money(view.outstandingLoan)),
        ],
      ),
    );
  }
}

class _PositionMetric extends StatelessWidget {
  const _PositionMetric({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                color: color,
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

class _OutstandingLoanRow extends StatelessWidget {
  const _OutstandingLoanRow({required this.value});

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

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.currencyCode,
    required this.points,
    required this.metrics,
    required this.selectedPeriod,
    required this.onPeriodSelected,
  });

  final String title;
  final String subtitle;
  final String currencyCode;
  final List<FinancialPeriodTrendPoint> points;
  final List<_TrendMetric> metrics;
  final int selectedPeriod;
  final ValueChanged<int> onPeriodSelected;

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
            style: AppTextStyles.small(
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
          SizedBox(height: ScreenScalingService.scaleSize(context, 14)),
          Wrap(
            spacing: ScreenScalingService.scaleSize(context, 14),
            runSpacing: ScreenScalingService.scaleSize(context, 8),
            children: [
              for (final metric in metrics)
                _LegendItem(label: metric.label, color: metric.color),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
          _PeriodLineChart(
            currencyCode: currencyCode,
            points: points,
            metrics: metrics,
            selectedPeriod: selectedPeriod,
            onPeriodSelected: onPeriodSelected,
          ),
        ],
      ),
    );
  }
}

class _PeriodLineChart extends StatelessWidget {
  const _PeriodLineChart({
    required this.currencyCode,
    required this.points,
    required this.metrics,
    required this.selectedPeriod,
    required this.onPeriodSelected,
  });

  final String currencyCode;

  final List<FinancialPeriodTrendPoint> points;

  final List<_TrendMetric> metrics;

  final int selectedPeriod;

  final ValueChanged<int> onPeriodSelected;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChart();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = constraints.maxWidth;

        final periodWidth = ScreenScalingService.scaleSize(context, 72);

        final chartWidth = math.max(minimumWidth, points.length * periodWidth);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            height: ScreenScalingService.scaleSize(context, 280),
            child: Padding(
              padding: EdgeInsets.only(
                right: ScreenScalingService.scaleSize(context, 12),
              ),
              child: LineChart(_lineChartData(context)),
            ),
          ),
        );
      },
    );
  }

  LineChartData _lineChartData(BuildContext context) {
    final theme = Theme.of(context);

    final maximum = _maximumValue();

    final maxY = maximum <= 0 ? 1.0 : maximum * 1.15;

    return LineChartData(
      minX: 0,
      maxX: math.max(0, points.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: _horizontalInterval(maxY),
        getDrawingHorizontalLine: (_) => FlLine(
          color: theme.dividerColor.withValues(alpha: 0.20),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: ScreenScalingService.scaleSize(context, 34),
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();

              if (index < 0 || index >= points.length) {
                return const SizedBox.shrink();
              }

              final period = points[index].period;

              final isSelected = period == selectedPeriod;

              return SideTitleWidget(
                meta: meta,
                child: Text(
                  _monthLabel(period),
                  style: AppTextStyles.tiny(context).copyWith(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        touchCallback: (event, response) {
          if (!event.isInterestedForInteractions ||
              response == null ||
              response.lineBarSpots == null ||
              response.lineBarSpots!.isEmpty) {
            return;
          }

          final index = response.lineBarSpots!.first.spotIndex;

          if (index < 0 || index >= points.length) {
            return;
          }

          onPeriodSelected(points[index].period);
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final metric = metrics[spot.barIndex];

              return LineTooltipItem(
                '${metric.label}\n'
                '${_money(currencyCode, spot.y)}',
                AppTextStyles.tinyNumber(context).copyWith(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        for (final metric in metrics)
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), metric.value(points[i])),
            ],
            color: metric.color,
            barWidth: 2.5,
            isCurved: true,
            curveSmoothness: 0.22,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) {
                final index = spot.x.round();

                final isSelected =
                    index >= 0 &&
                    index < points.length &&
                    points[index].period == selectedPeriod;

                return FlDotCirclePainter(
                  radius: isSelected ? 5 : 3,
                  color: metric.color,
                  strokeWidth: isSelected ? 2 : 0,
                  strokeColor: isSelected
                      ? theme.colorScheme.surface
                      : metric.color,
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    );
  }

  double _maximumValue() {
    var maximum = 0.0;

    for (final point in points) {
      for (final metric in metrics) {
        maximum = math.max(maximum, metric.value(point));
      }
    }

    return maximum;
  }

  static double _horizontalInterval(double maximum) {
    if (maximum <= 5) {
      return 1;
    }

    return maximum / 4;
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
            style: AppTextStyles.small(
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

class _MoneyInBarChart extends StatelessWidget {
  const _MoneyInBarChart({required this.view});

  final _FinancialPeriodView view;

  @override
  Widget build(BuildContext context) {
    final values = view.moneyIn;

    final maximum = values.fold<double>(
      0,
      (current, item) => math.max(current, item.value),
    );

    final total = view.availableMoney;

    final colors = Theme.of(context).colorScheme;

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
                  getTooltipItem: (_, _, rod, _) => BarTooltipItem(
                    view.money(rod.toY),
                    AppTextStyles.tinyNumber(context).copyWith(
                      color: colors.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
          _ValueLegendRow(
            label: item.label,
            amount: view.money(item.value),
            percentage: total > 0 ? item.value / total * 100 : 0,
            color: _FinancialColors.activity(item.label),
          ),
      ],
    );
  }
}

class _DistributionChart extends StatelessWidget {
  const _DistributionChart({required this.view});

  final _FinancialPeriodView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                      style: AppTextStyles.smallNumber(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'available money',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final item in values)
          _ValueLegendRow(
            label: item.label,
            amount: view.money(item.value),
            percentage: availableMoney > 0
                ? item.value / availableMoney * 100
                : 0,
            color: _FinancialColors.activity(item.label),
            circular: true,
          ),
      ],
    );
  }
}

class _ValueLegendRow extends StatelessWidget {
  const _ValueLegendRow({
    required this.label,
    required this.amount,
    required this.percentage,
    required this.color,
    this.circular = false,
  });

  final String label;
  final String amount;
  final double percentage;
  final Color color;
  final bool circular;

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
              shape: circular ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circular ? null : BorderRadius.circular(3),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colors.onSurface),
            ),
          ),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 70),
            child: Text(
              '${percentage.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(context).copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
          SizedBox(
            width: ScreenScalingService.scaleSize(context, 100),
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: colors.onSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ScreenScalingService.scaleSize(context, 9),
          height: ScreenScalingService.scaleSize(context, 9),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: ScreenScalingService.scaleSize(context, 6)),
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
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
        children: [
          for (final option in options)
            Padding(
              padding: EdgeInsets.only(
                right: ScreenScalingService.scaleSize(context, 8),
              ),
              child: _CurrencyTab(
                currency: _currencyDisplay(option),
                selected: option.toUpperCase() == selected.toUpperCase(),
                onTap: () {
                  onSelected(option);
                },
              ),
            ),
        ],
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

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: ScreenScalingService.scaleSize(context, 160),
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

  /*
   * Keep the established chart palette.
   *
   * These colours intentionally make the
   * financial activities easy to distinguish
   * across bar, doughnut and trend charts.
   */

  static const cashIn = Color(0xFF2E7D32);

  static const transferIn = Color(0xFF00897B);

  static const loanDisbursement = Color(0xFF1976D2);

  static const investmentProceeds = Color(0xFFD4A017);

  static const broughtForward = Color(0xFF7B1FA2);

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
        /*
         * Borrower represents new borrowing /
         * loan disbursement.
         *
         * It must not be derived from or
         * represented as loan repayment.
         */
        return loanDisbursement;

      case FinancialBehaviourType.balanced:
      case FinancialBehaviourType.neutral:
        return neutral;
    }
  }
}

String _monthLabel(int period) {
  if (period < 1 || period > 12) {
    return 'P$period';
  }

  return DateFormat.MMM().format(DateTime(2000, period, 1));
}

String _monthName(int period) {
  if (period < 1 || period > 12) {
    return 'Period $period';
  }

  return DateFormat.MMMM().format(DateTime(2000, period, 1));
}

String _currencyDisplay(String currency) {
  if (currency.toUpperCase() == 'ZIG') {
    return 'ZiG';
  }

  return currency.toUpperCase();
}

String _money(String currencyCode, double value) {
  return NumberFormat.simpleCurrency(
    name: currencyCode,
    decimalDigits: 2,
  ).format(value);
}

String _periodIdentityDescription(FinancialBehaviourType type) {
  return switch (type) {
    FinancialBehaviourType.saver =>
      'Saving was your strongest financial behaviour in this month.',

    FinancialBehaviourType.investor =>
      'Investing was your strongest financial behaviour in this month.',

    FinancialBehaviourType.shopper =>
      'Spending was your strongest financial behaviour in this month.',

    FinancialBehaviourType.borrower =>
      'Borrowing was your strongest financial behaviour in this month.',

    FinancialBehaviourType.balanced =>
      'Your strongest financial behaviours were closely balanced this month.',

    FinancialBehaviourType.neutral =>
      'There was not enough activity to identify a clear behaviour this month.',
  };
}
