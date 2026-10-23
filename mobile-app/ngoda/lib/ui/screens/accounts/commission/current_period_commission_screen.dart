import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/current_commission_params.dart';
import 'package:ngoda/data_models/commission/current_period_agent_commissions.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/providers/current_period_agent_commissions_provider.dart';
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
class CurrentPeriodCommissionScreen
    extends CurrentPeriodAgentCommissionsScreen {
  const CurrentPeriodCommissionScreen({super.key});
}

class CurrentPeriodAgentCommissionsScreen extends ConsumerStatefulWidget {
  const CurrentPeriodAgentCommissionsScreen({super.key});

  @override
  ConsumerState<CurrentPeriodAgentCommissionsScreen> createState() =>
      _CurrentPeriodAgentCommissionsScreenState();
}

class _CurrentPeriodAgentCommissionsScreenState
    extends ConsumerState<CurrentPeriodAgentCommissionsScreen> {
  static final CurrentCommissionParams _initial = CurrentCommissionParams();
  int _revision = 0;

  void _refresh() {
    ref.invalidate(currentPeriodAgentCommissionsProvider);
    setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final asyncCommissions = ref.watch(
      currentPeriodAgentCommissionsProvider(_initial),
    );
    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Current Agent Commission',
              onClose: () => context.pop(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Refresh current commission',
                  onPressed: asyncCommissions.isLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
            Expanded(
              child: asyncCommissions.when(
                skipLoadingOnRefresh: false,
                loading: () => const AppLoader(
                  message: 'Loading current agent commission',
                  fullScreen: false,
                ),
                error: (error, _) =>
                    _LoadError(message: error.toString(), onRefresh: _refresh),
                data: (response) {
                  if (response.error != null || response.result == null) {
                    return _LoadError(
                      message:
                          response.error ??
                          'Current commission data unavailable',
                      onRefresh: _refresh,
                    );
                  }
                  final data = response.result!;
                  final currencies = data.currencyCodes;
                  if (currencies.isEmpty) {
                    return const AppEmptyState(
                      message: 'No active commission currencies available',
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
                                    (currency) => _CurrencyCommissionPage(
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

class _CurrencyCommissionPage extends ConsumerStatefulWidget {
  const _CurrencyCommissionPage({
    super.key,
    required this.currency,
    required this.initial,
    required this.onRefresh,
  });

  final String currency;
  final CurrentPeriodAgentCommissions initial;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_CurrencyCommissionPage> createState() =>
      _CurrencyCommissionPageState();
}

class _CurrencyCommissionPageState
    extends ConsumerState<_CurrencyCommissionPage>
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
    final params = CurrentCommissionParams(
      currency: widget.currency,
      page: _page,
      pageSize: _pageSize,
      asOf: widget.initial.asOf,
    );
    final asyncCommissions = ref.watch(
      currentPeriodAgentCommissionsProvider(params),
    );
    final spacing = context.spacing;
    CurrentCommissionCurrencyTotal? total;
    for (final row in widget.initial.currencies) {
      if (row.currencyCode == widget.currency) {
        total = row;
        break;
      }
    }
    if (total == null) {
      return const AppEmptyState(
        message: 'No current commission data available',
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.sm),
          child: _CommissionCard(
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
                  label: 'Total Commission',
                  value: NumberFormatService.formatAmount(
                    total.totalCommissionAmount,
                    currency: widget.currency,
                  ),
                ),
                AppValueRow(
                  label: 'Already Paid',
                  value: NumberFormatService.formatAmount(
                    total.paidCommissionAmount,
                    currency: widget.currency,
                  ),
                ),
                AppValueRow(
                  label: 'Pending Commission',
                  value: NumberFormatService.formatAmount(
                    total.pendingCommissionAmount,
                    currency: widget.currency,
                  ),
                ),
                AppValueRow(
                  label: 'Pending Agents',
                  value: total.pendingAgents.toString(),
                ),
                AppValueRow(
                  label: 'Agents',
                  value: total.totalAgents.toString(),
                  addBottomSpacing: false,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: asyncCommissions.when(
            skipLoadingOnRefresh: false,
            loading: () => const AppLoader(
              message: 'Loading pending commission records',
              fullScreen: false,
            ),
            error: (error, _) => _LoadError(
              message: error.toString(),
              onRefresh: widget.onRefresh,
            ),
            data: (response) {
              if (response.error != null || response.result == null) {
                return _LoadError(
                  message:
                      response.error ?? 'Current commission data unavailable',
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
                            message:
                                'No pending commission in the current period',
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
                                _PendingCommissionItemCard(
                                  item: data.items[index],
                                ),
                          ),
                  ),
                  if (pagination.totalEntries > 0)
                    AppPagination(
                      page: pagination.page,
                      totalPages: pagination.totalPages,
                      totalEntries: pagination.totalEntries,
                      hasPrevious: pagination.hasPrevious,
                      hasNext: pagination.hasNext,
                      isLoading: asyncCommissions.isLoading,
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

class _PendingCommissionItemCard extends StatelessWidget {
  const _PendingCommissionItemCard({required this.item});
  final PendingCommissionItem item;

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
    return _CommissionCard(
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
          AppValueRow(label: 'Agent', value: item.agentDisplayName),
          AppValueRow(label: 'Document Number', value: item.documentNumber),
          AppValueRow(
            label: 'Date',
            value: DateFormatService.formatDisplayDate(
              item.createdAt.toLocal(),
            ),
          ),
          AppValueRow(
            label: 'Transaction Amount',
            value: NumberFormatService.formatAmount(
              item.amount,
              currency: item.currencyCode,
            ),
          ),
          AppValueRow(
            label: 'Fee Amount',
            value: NumberFormatService.formatAmount(
              item.feeAmount,
              currency: item.currencyCode,
            ),
          ),
          AppValueRow(
            label: 'Commission Rate',
            value: '${item.commissionRate.toStringAsFixed(2)}%',
          ),
          AppValueRow(
            label: 'Commission Amount',
            value: NumberFormatService.formatAmount(
              item.commissionAmount,
              currency: item.currencyCode,
            ),
            addBottomSpacing: true,
          ),
          if (item.reference?.trim().isNotEmpty == true)
            AppValueRow(label: 'Reference', value: item.reference!),
          AppValueRow(
            label: 'Status',
            value: 'Pending',
            addBottomSpacing: false,
          ),
        ],
      ),
    );
  }
}

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.child});
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
