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
import 'package:ngoda/ui/widgets/app_pagination.dart';
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
  int _requestGeneration = 0;

  final Set<String> _loadingCurrencies = {};
  final Map<String, int> _currencyPageSizes = {};

  @override
  void initState() {
    super.initState();

    _selectedDateRange = _defaultDateRange();

    params = FinancialStatementParams(
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

  int _pageSizeForCurrency(String currency) {
    return _currencyPageSizes[currency.toLowerCase()] ?? params.pageSize;
  }

  Future<void> _refresh() async {
    final generation = ++_requestGeneration;
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

    if (!mounted || generation != _requestGeneration) return;

    if (response.error != null || response.result == null) {
      return;
    }

    setState(() {
      params = refreshParams;
      _summary = response.result;
      _currencyPageSizes.clear();
      _loadingCurrencies.clear();
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

    if (!mounted || selectedRange == null) return;

    setState(() {
      _requestGeneration++;
      _selectedDateRange = selectedRange;

      params = FinancialStatementParams(
        startDate: _formatApiDate(selectedRange.start),
        endDate: _formatApiDate(selectedRange.end),
        page: 1,
        pageSize: params.pageSize,
      );

      _summary = null;
      _loadingCurrencies.clear();
      _currencyPageSizes.clear();
    });
  }

  void _resetDateRange() {
    final defaultRange = _defaultDateRange();

    setState(() {
      _requestGeneration++;
      _selectedDateRange = defaultRange;

      params = FinancialStatementParams(
        startDate: _formatApiDate(defaultRange.start),
        endDate: _formatApiDate(defaultRange.end),
        page: 1,
        pageSize: params.pageSize,
      );

      _summary = null;
      _loadingCurrencies.clear();
      _currencyPageSizes.clear();
    });
  }

  Future<void> _changePage({
    required String currency,
    required int page,
    required FinanceTransactionSummary currentSummary,
  }) async {
    if (page < 1) return;

    final normalizedCurrency = currency.toLowerCase();

    final pageParams = FinancialStatementParams(
      startDate: params.startDate,
      endDate: params.endDate,
      currency: normalizedCurrency,
      page: page,
      pageSize: _pageSizeForCurrency(normalizedCurrency),
    );

    await _loadCurrencyPage(
      currency: normalizedCurrency,
      pageParams: pageParams,
      currentSummary: currentSummary,
    );
  }

  Future<void> _changePageSize({
    required String currency,
    required int pageSize,
    required FinanceTransactionSummary currentSummary,
  }) async {
    if (pageSize < 1) return;

    final normalizedCurrency = currency.toLowerCase();

    final pageParams = FinancialStatementParams(
      startDate: params.startDate,
      endDate: params.endDate,
      currency: normalizedCurrency,
      page: 1,
      pageSize: pageSize,
    );

    await _loadCurrencyPage(
      currency: normalizedCurrency,
      pageParams: pageParams,
      currentSummary: currentSummary,
      updatedPageSize: pageSize,
    );
  }

  void _showPageError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCurrencyPage({
    required String currency,
    required FinancialStatementParams pageParams,
    required FinanceTransactionSummary currentSummary,
    int? updatedPageSize,
  }) async {
    if (_loadingCurrencies.contains(currency)) return;

    final generation = _requestGeneration;

    setState(() {
      _summary ??= currentSummary;
      _loadingCurrencies.add(currency);
    });

    try {
      final provider = recentTransactionsProvider(pageParams);
      ref.invalidate(provider);
      final response = await ref.read(provider.future);

      if (!mounted || generation != _requestGeneration) return;

      if (response.error != null) {
        _showPageError(response.error.toString());
        return;
      }

      final result = response.result;
      if (result == null) {
        _showPageError('No transaction response was returned.');
        return;
      }

      final updatedCurrency = result.getByCurrency(currency);
      if (updatedCurrency == null) {
        _showPageError(
          'No transaction page was returned for ${currency.toUpperCase()}.',
        );
        return;
      }

      final pagination = updatedCurrency.pagination;
      if (pagination.page != pageParams.page ||
          pagination.pageSize != pageParams.pageSize) {
        _showPageError(
          'Requested page ${pageParams.page} (${pageParams.pageSize} per page), '
          'but received page ${pagination.page} (${pagination.pageSize} per page).',
        );
        return;
      }

      setState(() {
        _summary = (_summary ?? currentSummary).replaceCurrency(
          currency: currency,
          statement: updatedCurrency,
        );
        _currencyPageSizes[currency] = pagination.pageSize;
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        _showPageError(error.toString());
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loadingCurrencies.remove(currency);
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
                        onPageSizeChanged: _changePageSize,
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
                      onPageSizeChanged: _changePageSize,
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
  const _TransactionBody({
    required this.summary,
    required this.loadingCurrencies,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  final FinanceTransactionSummary summary;
  final Set<String> loadingCurrencies;

  final Future<void> Function({
    required String currency,
    required int page,
    required FinanceTransactionSummary currentSummary,
  })
  onPageChanged;

  final Future<void> Function({
    required String currency,
    required int pageSize,
    required FinanceTransactionSummary currentSummary,
  })
  onPageSizeChanged;

  @override
  State<_TransactionBody> createState() {
    return _TransactionBodyState();
  }
}

class _TransactionBodyState extends State<_TransactionBody>
    with TickerProviderStateMixin {
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
                key: ValueKey(currency),
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
                onPageSizeChanged: (pageSize) {
                  return widget.onPageSizeChanged(
                    currency: currency,
                    pageSize: pageSize,
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
  const _TransactionList({
    super.key,
    required this.currency,
    required this.statement,
    required this.isLoading,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  final String currency;
  final FinanceCurrencyTransactions statement;
  final bool isLoading;

  final Future<void> Function(int page) onPageChanged;
  final Future<void> Function(int pageSize) onPageSizeChanged;

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
                    return _TransactionItem(
                      tx: transactions[index],
                      currency: currency,
                    );
                  },
                ),
        ),

        if (pagination.totalEntries > 0)
          AppPagination(
            page: pagination.page,
            totalPages: pagination.totalPages,
            totalEntries: pagination.totalEntries,
            hasPrevious: pagination.page > 1,
            hasNext: pagination.page < pagination.totalPages,
            isLoading: isLoading,
            pageSize: pagination.pageSize,
            onPrevious: () {
              onPageChanged(pagination.page - 1);
            },
            onNext: () {
              onPageChanged(pagination.page + 1);
            },
            onPageSizeChanged: (pageSize) {
              onPageSizeChanged(pageSize);
            },
          ),
      ],
    );
  }
}

class _TransactionItem extends StatelessWidget {
  const _TransactionItem({required this.tx, required this.currency});

  final FinanceTransaction tx;
  final String currency;

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
          context.push('/recent-transactions/${tx.documentNumber}');
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
