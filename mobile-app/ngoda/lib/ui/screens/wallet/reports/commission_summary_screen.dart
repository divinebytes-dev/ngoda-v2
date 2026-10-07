import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/agent/commission_stats.dart';
import 'package:ngoda/data_models/agent/commission_summary.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/commission_summary_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CommissionSummaryScreen extends ConsumerStatefulWidget {
  const CommissionSummaryScreen({super.key});

  @override
  ConsumerState<CommissionSummaryScreen> createState() =>
      _CommissionSummaryScreenState();
}

class _CommissionSummaryScreenState
    extends ConsumerState<CommissionSummaryScreen> {
  Future<void> _refresh() async {
    ref.invalidate(commissionSummaryProvider);

    await ref.read(commissionSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(commissionSummaryProvider);
    final role = getCurrentUser().role;
    final isMerchant = role == 'merchant';

    return Scaffold(
      bottomNavigationBar: isMerchant ? const BottomNav(currentIndex: 3) : null,
      body: SafeArea(
        child: Column(
          children: [
            isMerchant
                ? ScreenHeader(title: 'Commission Summary')
                : ViewHeader(
                    title: 'Commission Summary',
                    onClose: () {
                      ref.invalidate(commissionSummaryProvider);
                      context.pop();
                    },
                  ),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(
                  message: 'Loading commission summary',
                  fullScreen: true,
                ),
                error: (error, _) {
                  return _RefreshableState(
                    onRefresh: _refresh,
                    child: AppErrorState(
                      title: 'Commission Summary',
                      message: error.toString(),
                    ),
                  );
                },
                data: (result) {
                  if (result.error != null) {
                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: AppErrorState(
                        title: 'Commission Summary',
                        message: result.error!,
                      ),
                    );
                  }

                  final summary = result.result;

                  if (summary == null || summary.currencies.isEmpty) {
                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: const AppEmptyState(message: 'No commission'),
                    );
                  }

                  return _CommissionSummaryBody(
                    summary: summary,
                    onRefresh: _refresh,
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

/* -------------------------------------------------------------------------- */
/*                            REFRESHABLE STATE                               */
/* -------------------------------------------------------------------------- */

class _RefreshableState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const _RefreshableState({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.70,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                             SUMMARY BODY                                   */
/* -------------------------------------------------------------------------- */

class _CommissionSummaryBody extends StatefulWidget {
  final CommissionSummary summary;
  final Future<void> Function() onRefresh;

  const _CommissionSummaryBody({
    required this.summary,
    required this.onRefresh,
  });

  @override
  State<_CommissionSummaryBody> createState() => _CommissionSummaryBodyState();
}

class _CommissionSummaryBodyState extends State<_CommissionSummaryBody>
    with TickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.summary.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _CommissionSummaryBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCurrencies = oldWidget.summary.sortedCurrencyList;
    final newCurrencies = currencies;

    if (oldCurrencies.length != newCurrencies.length) {
      final previousIndex = _tabController.index;

      _tabController.dispose();

      _tabController = TabController(
        length: newCurrencies.length,
        vsync: this,
        initialIndex: previousIndex.clamp(0, newCurrencies.length - 1),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentCurrency {
    final index = _tabController.index.clamp(0, currencies.length - 1);

    return currencies[index];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CurrencyTabs(controller: _tabController, currencies: currencies),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final currency = _currentCurrency;
            final data = widget.summary.getByCurrency(currency);

            return _TotalsCard(currency: currency, fortnight: data?.fortnight);
          },
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final data = widget.summary.getByCurrency(currency);

              if (data == null) {
                return _RefreshableState(
                  onRefresh: widget.onRefresh,
                  child: Text(
                    'No data for this currency',
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(color: context.colorScheme.error),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(context.spacing.sm),
                  children: [
                    _PeriodContainer(
                      title: 'Today',
                      currency: currency,
                      stats: data.today,
                    ),
                    _PeriodContainer(
                      title: 'This Month',
                      currency: currency,
                      stats: data.month,
                    ),
                    _PeriodContainer(
                      title: 'This Year',
                      currency: currency,
                      stats: data.year,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                             PERIOD CONTAINER                               */
/* -------------------------------------------------------------------------- */

class _PeriodContainer extends StatelessWidget {
  final String title;
  final String currency;
  final CommissionStats stats;

  const _PeriodContainer({
    required this.title,
    required this.currency,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: _PeriodCard(title: title, currency: currency, stats: stats),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                               TOTALS CARD                                  */
/* -------------------------------------------------------------------------- */

class _TotalsCard extends StatelessWidget {
  final String currency;
  final CommissionStats? fortnight;

  const _TotalsCard({required this.currency, required this.fortnight});

  @override
  Widget build(BuildContext context) {
    final stats = fortnight;
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    if (stats == null) {
      return Padding(
        padding: EdgeInsets.only(top: spacing.xs),
        child: Text(
          'No Data',
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.error),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(
        top: spacing.sm,
        left: spacing.sm,
        right: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Container(
        margin: EdgeInsets.all(spacing.xs),
        padding: EdgeInsets.symmetric(horizontal: spacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(radius.borderRadius),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.09),
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: spacing.xs),
            Text(
              'Payment Due',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            _CommissionStatsContent(currency: currency, stats: stats),
            SizedBox(height: spacing.xs),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                               PERIOD CARD                                  */
/* -------------------------------------------------------------------------- */

class _PeriodCard extends StatelessWidget {
  final String title;
  final String currency;
  final CommissionStats stats;

  const _PeriodCard({
    required this.title,
    required this.currency,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: spacing.sm),
        _CommissionStatsContent(currency: currency, stats: stats),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                         SHARED STATISTICS CONTENT                          */
/* -------------------------------------------------------------------------- */

class _CommissionStatsContent extends StatelessWidget {
  final String currency;
  final CommissionStats stats;

  const _CommissionStatsContent({required this.currency, required this.stats});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final neutralColor = colorScheme.onSurfaceVariant;
    final paidColor = Colors.green.shade700;
    final pendingColor = colorScheme.error;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Commission',
              style: AppTextStyles.tiny(context).copyWith(color: neutralColor),
            ),
            Text(
              'Paid',
              style: AppTextStyles.tiny(context).copyWith(color: paidColor),
            ),
            Text(
              'Pending',
              style: AppTextStyles.tiny(context).copyWith(color: pendingColor),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              NumberFormatService.formatAmount(
                stats.totalCommission,
                currency: currency,
              ),
              style: AppTextStyles.smallNumber(context),
            ),
            Text(
              NumberFormatService.formatAmount(stats.paid, currency: currency),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: paidColor),
            ),
            Text(
              NumberFormatService.formatAmount(
                stats.notPaid,
                currency: currency,
              ),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: pendingColor),
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total',
              style: AppTextStyles.tiny(context).copyWith(color: neutralColor),
            ),
            Text(
              'Fee',
              style: AppTextStyles.tiny(context).copyWith(color: neutralColor),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              NumberFormatService.formatAmount(
                stats.totalAmount,
                currency: currency,
              ),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: neutralColor),
            ),
            Text(
              NumberFormatService.formatAmount(
                stats.totalFee,
                currency: currency,
              ),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: neutralColor),
            ),
          ],
        ),
      ],
    );
  }
}
