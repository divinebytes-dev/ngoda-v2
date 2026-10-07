import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/finance/finance_currency_transactions.dart';
import 'package:ngoda/data_models/finance/finance_transaction.dart';
import 'package:ngoda/data_models/finance/finance_transaction_summary.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_financial_credit.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/finance/providers/recent_transactions_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class RecentTransactionScreen extends ConsumerStatefulWidget {
  const RecentTransactionScreen({super.key});

  @override
  ConsumerState<RecentTransactionScreen> createState() {
    return _RecentTransactionScreenState();
  }
}

class _RecentTransactionScreenState
    extends ConsumerState<RecentTransactionScreen> {
  late FinancialStatementParams params;
  late DateTimeRange _selectedDateRange;

  FinanceTransactionSummary? _summary;

  final Set<String> _loadingCurrencies = {};

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _selectedDateRange = DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, now.month, now.day),
    );

    params = FinancialStatementParams(
      startDate: _formatApiDate(_selectedDateRange.start),
      endDate: _formatApiDate(_selectedDateRange.end),
      page: 1,
      pageSize: 50,
    );
  }

  String _formatApiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refresh() async {
    final refreshParams = FinancialStatementParams(
      startDate: params.startDate,
      endDate: params.endDate,
      page: 1,
      pageSize: params.pageSize,
    );

    ref.invalidate(recentTransactionsProvider(refreshParams));

    final response = await ref.read(
      recentTransactionsProvider(refreshParams).future,
    );

    if (!mounted) {
      return;
    }

    if (response.error != null || response.result == null) {
      return;
    }

    setState(() {
      params = refreshParams;
      _summary = response.result;
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

      params = FinancialStatementParams(
        startDate: _formatApiDate(selectedRange.start),
        endDate: _formatApiDate(selectedRange.end),
        page: 1,
        pageSize: params.pageSize,
      );

      _summary = null;
      _loadingCurrencies.clear();
    });
  }

  void _resetDateRange() {
    final now = DateTime.now();

    final defaultRange = DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, now.month, now.day),
    );

    setState(() {
      _selectedDateRange = defaultRange;

      params = FinancialStatementParams(
        startDate: _formatApiDate(defaultRange.start),
        endDate: _formatApiDate(defaultRange.end),
        page: 1,
        pageSize: params.pageSize,
      );

      _summary = null;
      _loadingCurrencies.clear();
    });
  }

  Future<void> _changePage({
    required String currency,
    required int page,
    required FinanceTransactionSummary currentSummary,
  }) async {
    if (page < 1) {
      return;
    }

    final normalizedCurrency = currency.toLowerCase();

    if (_loadingCurrencies.contains(normalizedCurrency)) {
      return;
    }

    final pageParams = FinancialStatementParams(
      startDate: params.startDate,
      endDate: params.endDate,
      currency: normalizedCurrency,
      page: page,
      pageSize: params.pageSize,
    );

    setState(() {
      _loadingCurrencies.add(normalizedCurrency);
    });

    try {
      final response = await ref.read(
        recentTransactionsProvider(pageParams).future,
      );

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
        _summary = currentSummary.replaceCurrency(
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
    ref.invalidate(recentTransactionsProvider(params));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTransactions = ref.watch(recentTransactionsProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Recent Transactions', onClose: _closeScreen),
            _DateRangeSelector(
              selectedDateRange: _selectedDateRange,
              onSelect: _selectDateRange,
              onReset: _resetDateRange,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncTransactions.when(
                  loading: () {
                    if (_summary != null) {
                      return _TransactionBody(
                        summary: _summary!,
                        loadingCurrencies: _loadingCurrencies,
                        onPageChanged: _changePage,
                      );
                    }

                    return const AppLoader(
                      message: 'Loading recent transactions',
                      fullScreen: false,
                    );
                  },
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(
                        title: 'Recent Transactions',
                        message: error.toString(),
                      ),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          title: 'Recent Transactions',
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final result = response.result;

                    if (result == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    final displayedSummary = _summary ?? result;

                    if (displayedSummary.currencies.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TransactionBody(
                      summary: displayedSummary,
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
  final DateTimeRange selectedDateRange;
  final VoidCallback onSelect;
  final VoidCallback onReset;

  const _DateRangeSelector({
    required this.selectedDateRange,
    required this.onSelect,
    required this.onReset,
  });

  String _formatDisplayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

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
        onTap: onSelect,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.date_range_outlined, size: iconSize.small),
              SizedBox(width: spacing.sm),
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
                      '${_formatDisplayDate(selectedDateRange.start)} — '
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
                tooltip: 'Reset period',
                padding: EdgeInsets.zero,
                icon: Icon(Icons.refresh, size: iconSize.small),
              ),
              Icon(
                Icons.chevron_right,
                size: iconSize.small,
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
  final FinanceTransactionSummary summary;
  final Set<String> loadingCurrencies;

  final Future<void> Function({
    required String currency,
    required int page,
    required FinanceTransactionSummary currentSummary,
  })
  onPageChanged;

  const _TransactionBody({
    required this.summary,
    required this.loadingCurrencies,
    required this.onPageChanged,
  });

  @override
  State<_TransactionBody> createState() {
    return _TransactionBodyState();
  }
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies {
    return widget.summary.sortedCurrencyList;
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCurrencies = oldWidget.summary.sortedCurrencyList;

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
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    if (currencies.isEmpty) {
      return const _RefreshableState(child: AppEmptyState());
    }

    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(horizontal: spacing.padding),
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: currencies.length > 4,
            tabAlignment: currencies.length > 4
                ? TabAlignment.start
                : TabAlignment.fill,
            indicator: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            labelStyle: AppTextStyles.tiny(context),
            dividerColor: Colors.transparent,
            labelColor: colorScheme.onPrimary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: currencies.map((currency) {
              return Tab(text: currency.toUpperCase());
            }).toList(),
          ),
        ),
        SizedBox(height: spacing.sm),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final currencyStatement = widget.summary.getByCurrency(currency);

              if (currencyStatement == null) {
                return const _RefreshableState(child: AppEmptyState());
              }

              return _TransactionList(
                currency: currency,
                statement: currencyStatement,
                isLoading: _isLoading(currency),
                onPageChanged: (page) {
                  return widget.onPageChanged(
                    currency: currency,
                    page: page,
                    currentSummary: widget.summary,
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

class _TransactionList extends StatelessWidget {
  final String currency;
  final FinanceCurrencyTransactions statement;
  final bool isLoading;
  final Future<void> Function(int page) onPageChanged;

  const _TransactionList({
    required this.currency,
    required this.statement,
    required this.isLoading,
    required this.onPageChanged,
  });

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
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    spacing.padding,
                    spacing.sm,
                    spacing.padding,
                    spacing.sm,
                  ),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];

                    return _TransactionItem(
                      tx: transaction,
                      currency: currency,
                    );
                  },
                ),
        ),
        _PaginationControls(
          page: pagination.page,
          totalPages: pagination.totalPages,
          totalEntries: pagination.totalEntries,
          hasPrevious: pagination.hasPrevious,
          hasNext: pagination.hasNext,
          isLoading: isLoading,
          onPageChanged: onPageChanged,
        ),
      ],
    );
  }
}

class _PaginationControls extends StatelessWidget {
  final int page;
  final int totalPages;
  final int totalEntries;
  final bool hasPrevious;
  final bool hasNext;
  final bool isLoading;
  final Future<void> Function(int page) onPageChanged;

  const _PaginationControls({
    required this.page,
    required this.totalPages,
    required this.totalEntries,
    required this.hasPrevious,
    required this.hasNext,
    required this.isLoading,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    if (totalEntries == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.padding,
        spacing.sm,
        spacing.padding,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: hasPrevious && !isLoading
                ? () {
                    onPageChanged(page - 1);
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    'Page $page of $totalPages',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                SizedBox(height: spacing.xs),
                Text(
                  '$totalEntries transactions',
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: hasNext && !isLoading
                ? () {
                    onPageChanged(page + 1);
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final FinanceTransaction tx;
  final String currency;

  const _TransactionItem({required this.tx, required this.currency});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final isCredit = isCreditTx(tx.transactionType);

    final entryColor = isCredit ? const Color(0xFF16A34A) : colorScheme.error;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        onTap: () {
          context.push(
            '/recent-transactions/'
            '${tx.documentNumber}',
          );
        },
        child: Container(
          margin: EdgeInsets.only(bottom: spacing.sm),
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colorScheme.surface,
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
                decoration: BoxDecoration(
                  color: entryColor,
                  shape: BoxShape.circle,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatTxType(tx.transactionType),
                            style: AppTextStyles.small(
                              context,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),

                        SizedBox(width: spacing.sm),

                        Text(
                          DateFormatService.formatDateTime(tx.createdAt),
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      tx.description,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),

                    SizedBox(height: spacing.sm),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${isCredit ? '+' : '-'}'
                        '${NumberFormatService.formatAmount(tx.grossAmount, currency: currency)}',
                        style: AppTextStyles.smallNumber(context).copyWith(
                          color: entryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right_rounded,
                size: context.iconSize.large,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  final Widget child;

  const _RefreshableState({required this.child});

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
