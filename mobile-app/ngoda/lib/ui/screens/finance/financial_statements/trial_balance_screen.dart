import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance_account.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance_total.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/financial_statement_date_range.dart';
import 'package:ngoda/ui/functions/get_entry_color.dart';
import 'package:ngoda/ui/screens/finance/providers/trial_balance_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class TrialBalanceScreen extends ConsumerStatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  ConsumerState<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends ConsumerState<TrialBalanceScreen> {
  late FinancialStatementParams params;

  @override
  void initState() {
    super.initState();

    params = FinancialStatementParams();
  }

  Future<void> _refresh() async {
    ref.invalidate(trialBalanceProvider(params));

    await ref.read(trialBalanceProvider(params).future);
  }

  Future<void> _selectDateRange() async {
    final updatedParams = await selectFinancialStatementDateRange(
      context: context,
      currentParams: params,
    );

    if (updatedParams == null || !mounted) {
      return;
    }

    setState(() {
      params = updatedParams;
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncTrialBalance = ref.watch(trialBalanceProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Trial Balance',
              onClose: () {
                ref.invalidate(trialBalanceProvider(params));

                context.pop();
              },
            ),
            _DateRangeCard(
              startDate: params.startDate,
              endDate: params.endDate,
              onTap: _selectDateRange,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncTrialBalance.when(
                  loading: () => const AppLoader(
                    message: 'Loading Trial Balance',
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

                    final trialBalance = response.result;

                    if (trialBalance == null ||
                        trialBalance.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TransactionBody(
                      key: ValueKey(
                        '${params.startDate}-'
                        '${params.endDate}-'
                        '${trialBalance.currencies.length}',
                      ),
                      trialBalance: trialBalance,
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

class _DateRangeCard extends StatelessWidget {
  const _DateRangeCard({
    required this.startDate,
    required this.endDate,
    required this.onTap,
  });

  final String startDate;
  final String endDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Container(
          margin: EdgeInsets.fromLTRB(
            spacing.padding,
            0,
            spacing.padding,
            spacing.sm,
          ),
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize.medium * 2,
                height: iconSize.medium * 2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.date_range_outlined,
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
                      'Reporting Period',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '$startDate  —  $endDate',
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

class _TransactionBody extends StatefulWidget {
  const _TransactionBody({
    super.key,
    required this.trialBalance,
    required this.params,
  });

  final TrialBalance trialBalance;
  final FinancialStatementParams params;

  @override
  State<_TransactionBody> createState() => _TransactionBodyState();
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.trialBalance.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _initializeTabs();
  }

  void _initializeTabs() {
    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.trialBalance.currencies.length !=
        widget.trialBalance.currencies.length) {
      _tabController.dispose();

      _initializeTabs();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        _CurrencyTabs(controller: _tabController, currencies: currencies),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final currency = currencies[_tabController.index];

            final currencyData = widget.trialBalance.currencies[currency];

            if (currencyData == null) {
              return const SizedBox.shrink();
            }

            return _TotalsBar(currency: currency, totals: currencyData.total);
          },
        ),
        Expanded(
          child: Container(
            margin: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(radius.borderRadius),
              ),
              // border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: TabBarView(
              controller: _tabController,
              children: currencies.map((currency) {
                final accounts =
                    widget.trialBalance.currencies[currency]?.accounts ?? [];

                return _TransactionList(
                  currency: currency,
                  transactions: accounts,
                  params: widget.params,
                );
              }).toList(),
            ),
          ),
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

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.currency, required this.totals});

  final String currency;
  final TrialBalanceTotal totals;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.all(spacing.sm),
      padding: EdgeInsets.all(spacing.xs),
      // decoration: BoxDecoration(
      //   color: colorScheme.surfaceContainer,
      //   borderRadius: BorderRadius.circular(radius.cardRadius),
      // ),
      child: Container(
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(radius.cardRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.09),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Totals',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TotalAmount(
                  value: totals.totalDebit,
                  currency: currency,
                  suffix: 'DR',
                ),
                SizedBox(height: spacing.xs),
                _TotalAmount(
                  value: totals.totalCredit,
                  currency: currency,
                  suffix: 'CR',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalAmount extends StatelessWidget {
  const _TotalAmount({
    required this.value,
    required this.currency,
    required this.suffix,
  });

  final double value;
  final String currency;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: NumberFormatService.formatAmount(value, currency: currency),
            style: AppTextStyles.mediumNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ' $suffix',
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.currency,
    required this.transactions,
    required this.params,
  });

  final String currency;
  final List<TrialBalanceAccount> transactions;
  final FinancialStatementParams params;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    if (transactions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: ScreenScalingService.scaleSize(context, 300),
            child: AppEmptyState(),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(spacing.sm),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        return _TransactionItem(
          trialBalanceAccount: transactions[index],
          currency: currency,
          params: params,
        );
      },
    );
  }
}

class _TransactionItem extends StatelessWidget {
  const _TransactionItem({
    required this.trialBalanceAccount,
    required this.currency,
    required this.params,
  });

  final TrialBalanceAccount trialBalanceAccount;
  final String currency;
  final FinancialStatementParams params;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final account = trialBalanceAccount;
    final color = getAccountColor(account.accountCode);

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        onTap: () {
          final drilldownParams = params.copyWith(
            currency: currency,
            gl: account.accountCode,
            page: 1,
            pageSize: 50,
          );

          context.push(
            '/financial-statements/trial-balance/entries',
            extra: drilldownParams,
          );
        },
        child: Container(
          margin: EdgeInsets.only(bottom: spacing.sm),
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: spacing.sm,
                height: spacing.sm,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.accountName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      account.accountCode,
                      style: AppTextStyles.tiny(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _AccountAmount(
                    value: account.debit,
                    currency: currency,
                    suffix: 'DR',
                  ),
                  SizedBox(height: spacing.xs),
                  _AccountAmount(
                    value: account.credit,
                    currency: currency,
                    suffix: 'CR',
                  ),
                ],
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
  }
}

class _AccountAmount extends StatelessWidget {
  const _AccountAmount({
    required this.value,
    required this.currency,
    required this.suffix,
  });

  final double value;
  final String currency;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: NumberFormatService.formatAmount(value, currency: currency),
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ' $suffix',
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
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
