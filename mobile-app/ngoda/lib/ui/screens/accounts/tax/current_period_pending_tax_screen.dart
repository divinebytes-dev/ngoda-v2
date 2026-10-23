import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/current_tax_params.dart';
import 'package:ngoda/data_models/tax/current_government_tax.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/providers/current_government_tax_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

// Retain the existing route's class name while replacing manual batch creation.
class CurrentPeriodPendingTaxScreen extends CurrentGovernmentTaxScreen {
  const CurrentPeriodPendingTaxScreen({super.key});
}

class CurrentGovernmentTaxScreen extends ConsumerStatefulWidget {
  const CurrentGovernmentTaxScreen({super.key});

  @override
  ConsumerState<CurrentGovernmentTaxScreen> createState() =>
      _CurrentGovernmentTaxScreenState();
}

class _CurrentGovernmentTaxScreenState
    extends ConsumerState<CurrentGovernmentTaxScreen> {
  static final CurrentTaxParams _initial = CurrentTaxParams();
  int _revision = 0;

  void _refresh() {
    ref.invalidate(currentGovernmentTaxProvider);
    setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final asyncTax = ref.watch(currentGovernmentTaxProvider(_initial));
    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Current Government Tax',
              onClose: () => context.pop(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Refresh current tax',
                  onPressed: asyncTax.isLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
            Expanded(
              child: asyncTax.when(
                skipLoadingOnRefresh: false,
                loading: () => const AppLoader(
                  message: 'Loading current government tax',
                  fullScreen: false,
                ),
                error: (error, _) =>
                    _LoadError(message: error.toString(), onRefresh: _refresh),
                data: (response) {
                  if (response.error != null || response.result == null) {
                    return _LoadError(
                      message: response.error ?? 'Current tax data unavailable',
                      onRefresh: _refresh,
                    );
                  }
                  final data = response.result!;
                  final currencies = data.currencyCodes;
                  if (currencies.isEmpty) {
                    return const AppEmptyState(
                      message: 'No active tax currencies available',
                    );
                  }
                  return DefaultTabController(
                    key: ValueKey('$_revision:${currencies.join(',')}'),
                    length: currencies.length,
                    child: Builder(
                      builder: (context) => Column(
                        children: [
                          CurrencyTabs(
                            controller: DefaultTabController.of(context),
                            currencies: currencies,
                          ),
                          SizedBox(height: spacing.sm),
                          Expanded(
                            child: TabBarView(
                              children: currencies
                                  .map(
                                    (currency) => _CurrencyTaxPage(
                                      key: ValueKey(currency),
                                      currency: currency,
                                      initial: data,
                                      onRefresh: _refresh,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
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

class _CurrencyTaxPage extends ConsumerStatefulWidget {
  const _CurrencyTaxPage({
    super.key,
    required this.currency,
    required this.initial,
    required this.onRefresh,
  });

  final String currency;
  final CurrentGovernmentTax initial;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_CurrencyTaxPage> createState() => _CurrencyTaxPageState();
}

class _CurrencyTaxPageState extends ConsumerState<_CurrencyTaxPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  int _pageSize = 50;

  @override
  bool get wantKeepAlive => true;

  void _goTo(int page) {
    setState(() => _page = page);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _changePageSize(int pageSize) {
    setState(() {
      _pageSize = pageSize;
      _page = 1;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Totals and every page use the same initial server cutoff.
    final params = CurrentTaxParams(
      currency: widget.currency,
      page: _page,
      pageSize: _pageSize,
      asOf: widget.initial.asOf,
    );
    final asyncTax = ref.watch(currentGovernmentTaxProvider(params));
    final spacing = context.spacing;
    CurrentTaxCurrencyTotal? total;
    for (final row in widget.initial.currencies) {
      if (row.currencyCode == widget.currency) {
        total = row;
        break;
      }
    }
    if (total == null) {
      return const AppEmptyState(message: 'No current tax data available');
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.sm),
          child: _TaxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FY ${widget.initial.fiscalYear} • Period ${widget.initial.period}',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.md),
                AppValueRow(
                  label: 'Total Tax',
                  value: NumberFormatService.formatAmount(
                    total.totalTaxAmount,
                    currency: widget.currency,
                  ),
                ),
                AppValueRow(
                  label: 'Transaction Total',
                  value: NumberFormatService.formatAmount(
                    total.totalGrossAmount,
                    currency: widget.currency,
                  ),
                ),
                AppValueRow(
                  label: 'Tax Records',
                  value: total.payableCount.toString(),
                  addBottomSpacing: false,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: asyncTax.when(
            skipLoadingOnRefresh: false,
            loading: () => const AppLoader(
              message: 'Loading tax records',
              fullScreen: false,
            ),
            error: (error, _) => _LoadError(
              message: error.toString(),
              onRefresh: widget.onRefresh,
            ),
            data: (response) {
              if (response.error != null || response.result == null) {
                return _LoadError(
                  message: response.error ?? 'Current tax data unavailable',
                  onRefresh: widget.onRefresh,
                );
              }
              final data = response.result!;
              final pagination = data.pagination;
              return Column(
                children: [
                  Expanded(
                    child: data.items.isEmpty
                        ? const AppEmptyState(
                            message: 'No tax recorded in the current period',
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              spacing.sm,
                              0,
                              spacing.sm,
                              spacing.md,
                            ),
                            itemCount: data.items.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: spacing.sm),
                            itemBuilder: (context, index) =>
                                _TaxItemCard(item: data.items[index]),
                          ),
                  ),
                  if (pagination.totalEntries > 0)
                    AppPagination(
                      page: pagination.page,
                      totalPages: pagination.totalPages,
                      totalEntries: pagination.totalEntries,
                      hasPrevious: pagination.hasPrevious,
                      hasNext: pagination.hasNext,
                      isLoading: asyncTax.isLoading,
                      pageSize: pagination.pageSize,
                      onPrevious: () => _goTo(pagination.page - 1),
                      onNext: () => _goTo(pagination.page + 1),
                      onPageSizeChanged: _changePageSize,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TaxItemCard extends StatelessWidget {
  const _TaxItemCard({required this.item});
  final CurrentTaxItem item;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final title = item.transactionType
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
    return _TaxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          // AppValueRow(label: 'Document Number', value: item.documentNumber),
          AppValueRow(
            label: 'Date',
            value: DateFormatService.formatDisplayDate(
              item.createdAt.toLocal(),
            ),
          ),
          AppValueRow(
            label: 'Transaction Amount',
            value: NumberFormatService.formatAmount(
              item.grossAmount,
              currency: item.currencyCode,
            ),
          ),
          AppValueRow(
            label: 'Tax Rate',
            value: '${item.taxRate.toStringAsFixed(2)}%',
          ),
          AppValueRow(
            label: 'Tax Amount',
            value: NumberFormatService.formatAmount(
              item.taxAmount,
              currency: item.currencyCode,
            ),
            addBottomSpacing: item.reference?.trim().isNotEmpty == true,
          ),
          if (item.reference?.trim().isNotEmpty == true)
            AppValueRow(
              label: 'Reference',
              value: item.reference!,
              addBottomSpacing: false,
            ),
        ],
      ),
    );
  }
}

class _TaxCard extends StatelessWidget {
  const _TaxCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(context.spacing.md),
    decoration: BoxDecoration(
      color: context.colorScheme.surface,
      borderRadius: BorderRadius.circular(context.radius.borderRadius),
      border: Border.all(
        color: context.colorScheme.outlineVariant.withValues(alpha: 0.09),
      ),
    ),
    child: child,
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRefresh});
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(context.spacing.md),
    child: Column(
      children: [
        AppErrorState(message: message),
        SizedBox(height: context.spacing.md),
        AppButton(text: 'Refresh', onPressed: onRefresh),
      ],
    ),
  );
}
