import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/params/mini_statement_params.dart';
import 'package:ngoda/data_models/payment/mini_statement.dart';
import 'package:ngoda/data_models/wallet/currency_statement.dart';
import 'package:ngoda/data_models/wallet/wallet_transaction.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/mini_statement_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() {
    return _TransactionHistoryScreenState();
  }
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  late MiniStatementParams params;

  MiniStatement? _statement;

  late DateTimeRange _selectedDateRange;

  final Set<String> _loadingCurrencies = {};

  @override
  void initState() {
    super.initState();

    _selectedDateRange = _defaultDateRange();

    params = MiniStatementParams(
      startDate: _formatApiDate(_selectedDateRange.start),
      endDate: _formatApiDate(_selectedDateRange.end),
      page: 1,
      pageSize: 50,
    );
  }

  DateTimeRange _defaultDateRange() {
    final now = DateTime.now();

    return DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  String _formatApiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refresh() async {
    final refreshParams = params.copyWith(clearCurrency: true, page: 1);

    ref.invalidate(miniStatementProvider(refreshParams));

    final response = await ref.read(
      miniStatementProvider(refreshParams).future,
    );

    if (!mounted) {
      return;
    }

    if (response.error != null || response.result == null) {
      return;
    }

    setState(() {
      params = refreshParams;
      _statement = response.result;
    });
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();

    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _selectedDateRange,
      helpText: 'Select transaction period',
      confirmText: 'Apply',
      cancelText: 'Cancel',
    );

    if (!mounted || selectedRange == null) {
      return;
    }

    setState(() {
      _selectedDateRange = selectedRange;

      params = params.copyWith(
        clearCurrency: true,
        startDate: _formatApiDate(selectedRange.start),
        endDate: _formatApiDate(selectedRange.end),
        page: 1,
      );

      /*
       * A new date range represents a
       * different statement.
       *
       * Do not display pages cached from
       * the previous date range.
       */
      _statement = null;
      _loadingCurrencies.clear();
    });
  }

  Future<void> _resetDateRange() async {
    final defaultRange = _defaultDateRange();

    setState(() {
      _selectedDateRange = defaultRange;

      params = MiniStatementParams(
        startDate: _formatApiDate(defaultRange.start),
        endDate: _formatApiDate(defaultRange.end),
        page: 1,
        pageSize: params.pageSize,
      );

      _statement = null;
      _loadingCurrencies.clear();
    });
  }

  Future<void> _changePage({
    required String currency,
    required int page,
    required MiniStatement currentStatement,
  }) async {
    if (page < 1) {
      return;
    }

    final normalizedCurrency = currency.toLowerCase();

    if (_loadingCurrencies.contains(normalizedCurrency)) {
      return;
    }

    final pageParams = params.copyWith(
      currency: normalizedCurrency,
      page: page,
    );

    setState(() {
      _loadingCurrencies.add(normalizedCurrency);
    });

    try {
      final response = await ref.read(miniStatementProvider(pageParams).future);

      if (!mounted) {
        return;
      }

      if (response.error != null || response.result == null) {
        return;
      }

      final updatedCurrency = response.result!.getByCurrency(
        normalizedCurrency,
      );

      if (updatedCurrency == null) {
        return;
      }

      setState(() {
        _statement = currentStatement.replaceCurrency(
          currency: normalizedCurrency,
          statement: updatedCurrency,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCurrencies.remove(normalizedCurrency);
        });
      }
    }
  }

  void _closeScreen() {
    ref.invalidate(miniStatementProvider(params));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(miniStatementProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Transaction History', onClose: _closeScreen),

            _DateRangeSelector(
              selectedDateRange: _selectedDateRange,
              onSelect: _selectDateRange,
              onReset: _resetDateRange,
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncData.when(
                  loading: () {
                    /*
                     * Keep the currently
                     * displayed statement
                     * visible while another
                     * request is loading.
                     */
                    if (_statement != null) {
                      return _Body(
                        statement: _statement!,
                        loadingCurrencies: _loadingCurrencies,
                        onPageChanged: _changePage,
                      );
                    }

                    return const AppLoader(
                      message: 'Loading transaction history',
                      fullScreen: false,
                    );
                  },
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(
                      title: 'Error',
                      message: error.toString(),
                    ),
                  ),
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          title: 'Error',
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final result = response.result;

                    if (result == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    final displayedStatement = _statement ?? result;

                    if (displayedStatement.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _Body(
                      statement: displayedStatement,
                      loadingCurrencies: _loadingCurrencies,
                      onPageChanged: _changePage,
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
  const _DateRangeSelector({
    required this.selectedDateRange,
    required this.onSelect,
    required this.onReset,
  });

  final DateTimeRange selectedDateRange;

  final VoidCallback onSelect;
  final VoidCallback onReset;

  String _formatDisplayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.sm),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(spacing.md),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: spacing.xl,
                  height: spacing.xl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.date_range_outlined,
                    color: colorScheme.primary,
                  ),
                ),

                SizedBox(width: spacing.md),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transaction period',
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),

                      SizedBox(height: spacing.xs),

                      Text(
                        '${_formatDisplayDate(selectedDateRange.start)}'
                        ' — '
                        '${_formatDisplayDate(selectedDateRange.end)}',
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: onReset,
                  tooltip: 'Reset date range',
                  icon: const Icon(Icons.restart_alt_rounded),
                ),

                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.statement,
    required this.loadingCurrencies,
    required this.onPageChanged,
  });

  final MiniStatement statement;

  final Set<String> loadingCurrencies;

  final Future<void> Function({
    required String currency,
    required int page,
    required MiniStatement currentStatement,
  })
  onPageChanged;

  @override
  State<_Body> createState() {
    return _BodyState();
  }
}

class _BodyState extends State<_Body> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.statement.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _Body oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCurrencies = oldWidget.statement.sortedCurrencyList;

    if (!_sameCurrencies(oldCurrencies, currencies)) {
      final previousIndex = _tabController.index;

      _tabController.dispose();

      final newIndex = currencies.isEmpty
          ? 0
          : previousIndex.clamp(0, currencies.length - 1);

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

  String _currentCurrency() {
    if (currencies.isEmpty) {
      return '';
    }

    final index = _tabController.index.clamp(0, currencies.length - 1);

    return currencies[index];
  }

  bool _isLoading(String currency) {
    return widget.loadingCurrencies.contains(currency.toLowerCase());
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CurrencyTabs(controller: _tabController, currencies: currencies),

        AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            final currency = _currentCurrency();

            final data = widget.statement.getByCurrency(currency);

            return _TotalsCard(currency: currency, statement: data);
          },
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final data = widget.statement.getByCurrency(currency);

              if (data == null) {
                return const _RefreshableState(child: AppEmptyState());
              }

              return _CurrencyTransactionList(
                currency: currency,
                statement: data,
                isLoading: _isLoading(currency),
                onPageChanged: (page) {
                  return widget.onPageChanged(
                    currency: currency,
                    page: page,
                    currentStatement: widget.statement,
                  );
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.currency, required this.statement});

  final String currency;

  final CurrencyStatement? statement;

  @override
  Widget build(BuildContext context) {
    final data = statement;

    if (data == null) {
      return const SizedBox.shrink();
    }

    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.sm,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(spacing.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available balance',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),

            SizedBox(height: spacing.xs),

            Text(
              NumberFormatService.formatAmount(
                data.balance,
                currency: currency,
              ),
              style: AppTextStyles.mediumNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),

            SizedBox(height: spacing.md),

            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),

            SizedBox(height: spacing.md),

            Row(
              children: [
                Expanded(
                  child: _TotalMetric(
                    label: 'Total debit',
                    value: data.totalDebit,
                    currency: currency,
                    color: colorScheme.error,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),

                SizedBox(width: spacing.md),

                Expanded(
                  child: _TotalMetric(
                    label: 'Total credit',
                    value: data.totalCredit,
                    currency: currency,
                    color: AppColors.success,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalMetric extends StatelessWidget {
  const _TotalMetric({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final String currency;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(spacing.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: color, fontWeight: FontWeight.w600),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  NumberFormatService.formatAmount(value, currency: currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyTransactionList extends StatelessWidget {
  const _CurrencyTransactionList({
    required this.currency,
    required this.statement,
    required this.isLoading,
    required this.onPageChanged,
  });

  final String currency;

  final CurrencyStatement statement;

  final bool isLoading;

  final Future<void> Function(int page) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final transactions = statement.transactions;

    final pagination = statement.pagination;

    return Column(
      children: [
        Expanded(
          child: transactions.isEmpty
              ? const _RefreshableState(child: AppEmptyState())
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    spacing.md,
                    0,
                    spacing.md,
                    spacing.md,
                  ),
                  itemCount: transactions.length,
                  separatorBuilder: (_, _) => SizedBox(height: spacing.sm),
                  itemBuilder: (context, index) {
                    return TransactionTile(
                      currency: currency,
                      tx: transactions[index],
                    );
                  },
                ),
        ),

        AppPagination(
          page: pagination.page,
          totalPages: pagination.totalPages,
          totalEntries: pagination.totalEntries,
          hasPrevious: pagination.hasPrevious,
          hasNext: pagination.hasNext,
          isLoading: isLoading,
          entryLabel: pagination.totalEntries == 1
              ? 'transaction'
              : 'transactions',
          onPrevious: () {
            onPageChanged(pagination.page - 1);
          },
          onNext: () {
            onPageChanged(pagination.page + 1);
          },
        ),
      ],
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.currency, required this.tx});

  final String currency;
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final isDebit = tx.debit > 0;
    final isCredit = !isDebit && tx.credit > 0;

    final amount = isDebit
        ? tx.debit
        : isCredit
        ? tx.credit
        : 0.0;

    final color = isDebit
        ? colorScheme.error
        : isCredit
        ? AppColors.success
        : colorScheme.onSurfaceVariant;

    final prefix = isDebit
        ? '-'
        : isCredit
        ? '+'
        : '';

    final icon = isDebit
        ? Icons.arrow_upward_rounded
        : isCredit
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, //colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: spacing.xl,
                height: spacing.xl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 19),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatTxType(tx.transactionType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      DateFormatService.formatDateTime(tx.createdAt),
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
                    '$prefix${NumberFormatService.formatAmount(amount, currency: currency)}',
                    style: AppTextStyles.smallNumber(
                      context,
                    ).copyWith(color: color, fontWeight: FontWeight.w700),
                  ),

                  SizedBox(height: spacing.xs),

                  Text(
                    'Balance ${NumberFormatService.formatAmount(tx.runningBalance, currency: currency)}',
                    style: AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
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
