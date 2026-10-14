import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_account.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_totals.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/profit_and_loss.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/financial_statement_date_range.dart';
import 'package:ngoda/ui/screens/finance/providers/profit_and_loss_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ProfitAndLossScreen extends ConsumerStatefulWidget {
  const ProfitAndLossScreen({super.key});

  @override
  ConsumerState<ProfitAndLossScreen> createState() =>
      _ProfitAndLossScreenState();
}

class _ProfitAndLossScreenState extends ConsumerState<ProfitAndLossScreen> {
  late FinancialStatementParams params;

  @override
  void initState() {
    super.initState();

    params = FinancialStatementParams();
  }

  Future<void> _refresh() async {
    ref.invalidate(profitAndLossProvider(params));

    await ref.read(profitAndLossProvider(params).future);
  }

  Future<void> _selectDateRange() async {
    final updatedParams = await selectFinancialStatementDateRange(
      context: context,
      currentParams: params,
    );

    if (!mounted || updatedParams == null) {
      return;
    }

    setState(() {
      params = updatedParams;
    });
  }

  void _closeScreen() {
    ref.invalidate(profitAndLossProvider(params));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPnL = ref.watch(profitAndLossProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Profit and Loss', onClose: _closeScreen),
            _DateRangeSelector(params: params, onTap: _selectDateRange),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncPnL.when(
                  loading: () => const AppLoader(
                    message: 'Loading Profit and Loss',
                    fullScreen: true,
                  ),
                  error: (error, _) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: response.error!),
                      );
                    }

                    final pnl = response.result;

                    if (pnl == null || pnl.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TransactionBody(pnl: pnl, params: params);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  const _DateRangeSelector({required this.params, required this.onTap});

  final FinancialStatementParams params;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.padding,
        0,
        spacing.padding,
        spacing.sm,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.date_range_outlined,
                size: iconSize.medium,
                color: colorScheme.primary,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reporting period',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '${params.startDate} — ${params.endDate}',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: iconSize.medium,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.currency,
    required this.totals,
    required this.margin,
  });

  final String currency;
  final PnLTotals totals;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final isProfit = totals.netIncome >= 0;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text('Net Income', style: AppTextStyles.small(context)),
          ),
          Center(
            child: Text(
              NumberFormatService.formatAmount(
                totals.netIncome,
                currency: currency,
              ),
              style: AppTextStyles.largeNumber(context).copyWith(
                fontWeight: FontWeight.w700,
                color: isProfit ? Colors.green : Colors.red,
              ),
            ),
          ),
          SizedBox(height: spacing.xs),
          const Divider(),
          SizedBox(height: spacing.xs),
          _Metric(
            title: 'Revenue',
            value: totals.totalRevenue,
            currency: currency,
            color: Colors.green,
          ),
          SizedBox(height: spacing.sm),
          _Metric(
            title: 'Expense',
            value: totals.totalExpense,
            currency: currency,
            color: Colors.red,
          ),
          SizedBox(height: spacing.md),
          _MetricPercent(title: 'Profit Margin', value: margin),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.currency,
    required this.color,
  });

  final String title;
  final double value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: AppTextStyles.mediumNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _MetricPercent extends StatelessWidget {
  const _MetricPercent({required this.title, required this.value});

  final String title;
  final double value;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(title, style: AppTextStyles.tiny(context)),
        SizedBox(width: spacing.sm),
        Text(
          '${value.toStringAsFixed(2)}%',
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w800, color: colorScheme.primary),
        ),
      ],
    );
  }
}

class _TransactionBody extends StatefulWidget {
  const _TransactionBody({required this.pnl, required this.params});

  final ProfitAndLoss pnl;
  final FinancialStatementParams params;

  @override
  State<_TransactionBody> createState() => _TransactionBodyState();
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.pnl.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCurrencies = oldWidget.pnl.sortedCurrencyList;

    if (!_sameCurrencies(oldCurrencies, currencies)) {
      final oldIndex = _tabController.index;

      _tabController.dispose();

      final newIndex = currencies.isEmpty
          ? 0
          : oldIndex.clamp(0, currencies.length - 1);

      _tabController = TabController(
        length: currencies.length,
        initialIndex: newIndex,
        vsync: this,
      );
    }
  }

  bool _sameCurrencies(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        _CurrencyTabs(controller: _tabController, currencies: currencies),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final data = widget.pnl.currencies[currency]!;

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(spacing.sm),
                    child: _TotalsCard(
                      currency: currency,
                      totals: data.totals,
                      margin: data.profitMargin,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        spacing.sm,
                        0,
                        spacing.sm,
                        spacing.sm,
                      ),
                      children: [
                        _SectionCard(
                          title: 'Revenue',
                          color: Colors.green,
                          currency: currency,
                          items: data.revenue,
                          params: widget.params,
                        ),
                        SizedBox(height: spacing.sm),
                        _SectionCard(
                          title: 'Expenses',
                          color: Colors.red,
                          currency: currency,
                          items: data.expense,
                          params: widget.params,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.color,
    required this.currency,
    required this.items,
    required this.params,
  });

  final String title;
  final Color color;
  final String currency;
  final List<PnLAccount> items;
  final FinancialStatementParams params;

  void _openDrilldown(BuildContext context, PnLAccount item) {
    final drilldownParams = params.copyWith(
      gl: item.accountCode,
      currency: currency,
      page: 1,
      pageSize: 50,
    );

    context.push(
      '/financial-statements/profit-loss/entries',
      extra: drilldownParams,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(spacing.sm),
            child: Row(
              children: [
                Container(
                  width: spacing.sm,
                  height: spacing.sm,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Text(
                  title,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.all(spacing.sm),
              child: const Text('No data'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) {
                return SizedBox(height: spacing.sm);
              },
              itemBuilder: (context, index) {
                final item = items[index];

                return Material(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(radius.cardRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      _openDrilldown(context, item);
                    },
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: spacing.md),
                      padding: EdgeInsets.all(spacing.md),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius.cardRadius),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.06,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.accountName,
                                  style: AppTextStyles.tiny(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),

                                SizedBox(height: spacing.xs),

                                Text(
                                  item.accountCode,
                                  style: AppTextStyles.tiny(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(width: spacing.sm),

                          Text(
                            NumberFormatService.formatAmount(
                              item.amount,
                              currency: currency,
                            ),
                            style: AppTextStyles.smallNumber(context).copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),

                          SizedBox(width: spacing.xs),

                          Icon(
                            Icons.chevron_right,
                            size: iconSize.medium,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  const _RefreshableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class _CurrencyTabs extends StatelessWidget {
  const _CurrencyTabs({required this.controller, required this.currencies});

  final TabController controller;
  final List<String> currencies;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.sm),
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: currencies.length > 4,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(radius.cardRadius),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        tabs: currencies.map((currency) {
          return Tab(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              child: Text(
                currency.toUpperCase(),
                style: AppTextStyles.small(context),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
