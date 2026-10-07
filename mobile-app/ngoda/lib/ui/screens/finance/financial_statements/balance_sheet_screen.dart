import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_account.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_totals.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/financial_statement_date_range.dart';
import 'package:ngoda/ui/screens/finance/providers/balance_sheet_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  ConsumerState<BalanceSheetScreen> createState() {
    return _BalanceSheetScreenState();
  }
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  late FinancialStatementParams params;

  @override
  void initState() {
    super.initState();

    params = FinancialStatementParams();
  }

  Future<void> _refresh() async {
    ref.invalidate(balanceSheetProvider(params));

    await ref.read(balanceSheetProvider(params).future);
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
    ref.invalidate(balanceSheetProvider(params));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncBalanceSheet = ref.watch(balanceSheetProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Balance Sheet', onClose: _closeScreen),
            _DateRangeSelector(params: params, onTap: _selectDateRange),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncBalanceSheet.when(
                  loading: () {
                    return const AppLoader(
                      message: 'Loading Balance Sheet',
                      fullScreen: true,
                    );
                  },
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

                    final balanceSheet = response.result;

                    if (balanceSheet == null ||
                        balanceSheet.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TransactionBody(
                      balanceSheet: balanceSheet,
                      params: params,
                    );
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
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(color: colorScheme.outlineVariant),
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
  const _TotalsCard({required this.currency, required this.totals});

  final String currency;
  final BalanceSheetTotals totals;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Metric(
            title: 'Assets',
            value: totals.assets,
            currency: currency,
            color: Colors.green,
          ),
          SizedBox(height: spacing.sm),
          _Metric(
            title: 'Liabilities',
            value: totals.liabilities,
            currency: currency,
            color: Colors.red,
          ),
          SizedBox(height: spacing.sm),
          _Metric(
            title: 'Equity',
            value: totals.equity,
            currency: currency,
            color: Colors.purple,
          ),
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
          ).copyWith(fontWeight: FontWeight.w600),
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

class _TransactionBody extends StatefulWidget {
  const _TransactionBody({required this.balanceSheet, required this.params});

  final BalanceSheet balanceSheet;
  final FinancialStatementParams params;

  @override
  State<_TransactionBody> createState() {
    return _TransactionBodyState();
  }
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.balanceSheet.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCurrencies = oldWidget.balanceSheet.sortedCurrencyList;

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
              final data = widget.balanceSheet.currencies[currency]!;

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(spacing.sm),
                    child: _TotalsCard(currency: currency, totals: data.totals),
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
                          title: 'Assets',
                          color: Colors.green,
                          currency: currency,
                          items: data.assets,
                          params: widget.params,
                        ),
                        SizedBox(height: spacing.sm),
                        _SectionCard(
                          title: 'Liabilities',
                          color: Colors.red,
                          currency: currency,
                          items: data.liabilities,
                          params: widget.params,
                        ),
                        SizedBox(height: spacing.sm),
                        _SectionCard(
                          title: 'Equity',
                          color: Colors.purple,
                          currency: currency,
                          items: data.equity,
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
  final List<BalanceSheetAccount> items;
  final FinancialStatementParams params;

  void _openDrilldown(BuildContext context, BalanceSheetAccount item) {
    final drilldownParams = params.copyWith(
      gl: item.accountCode,
      currency: currency,
      page: 1,
      pageSize: 50,
    );

    context.push(
      '/financial-statements/balance-sheet/entries',
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
                              item.balance,
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
      margin: EdgeInsets.symmetric(horizontal: spacing.padding),
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: currencies.length > 4,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(radius.borderRadius),
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
