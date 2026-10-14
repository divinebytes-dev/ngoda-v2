import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/tax/tax_settlement_item.dart';
import 'package:ngoda/data_models/tax/tax_settlement_items_page.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/screens/finance/providers/tax_settlement_items_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';

class TaxSettlementItemsScreen extends ConsumerStatefulWidget {
  final SettlementItemsParams params;
  const TaxSettlementItemsScreen({super.key, required this.params});
  @override
  ConsumerState<TaxSettlementItemsScreen> createState() =>
      _TaxSettlementItemsScreenState();
}

class _TaxSettlementItemsScreenState
    extends ConsumerState<TaxSettlementItemsScreen> {
  late int currentPage;
  late int pageSize;
  late SettlementItemsParams _currentParams;
  @override
  void initState() {
    super.initState();
    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
    _currentParams = widget.params;
  }

  SettlementItemsParams get currentParams {
    return _currentParams;
  }

  /* =========================================================
   * REFRESH
   * ========================================================= */
  Future<void> _refresh() async {
    ref.invalidate(taxSettlementItemsProvider(currentParams));
    await ref.read(taxSettlementItemsProvider(currentParams).future);
  }

  /* =========================================================
   * PAGINATION
   * ========================================================= */
  void _previousPage() {
    if (currentPage <= 1) {
      return;
    }
    setState(() {
      currentPage--;
      _currentParams = widget.params.copyWith(
        page: currentPage,
        pageSize: pageSize,
      );
    });
  }

  void _nextPage() {
    setState(() {
      currentPage++;
      _currentParams = widget.params.copyWith(
        page: currentPage,
        pageSize: pageSize,
      );
    });
  }

  void _changePageSize(int newPageSize) {
    if (newPageSize < 1 || newPageSize == pageSize) return;
    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
      _currentParams = widget.params.copyWith(
        page: currentPage,
        pageSize: pageSize,
      );
    });
  }

  /* =========================================================
   * BUILD
   * ========================================================= */
  @override
  Widget build(BuildContext context) {
    final drilldownAsync = ref.watch(taxSettlementItemsProvider(currentParams));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Government Tax Settlement Details',
              onClose: () {
                ref.invalidate(taxSettlementItemsProvider(currentParams));
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: drilldownAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading settlement items',
                    fullScreen: false,
                  ),
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }
                    final drilldown = response.result;
                    if (drilldown == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }
                    return _DrilldownContent(
                      drilldown: drilldown,
                      currency: widget.params.currency,
                      onPrevious: drilldown.pagination.hasPrevious
                          ? _previousPage
                          : null,
                      onNext: drilldown.pagination.hasNext ? _nextPage : null,
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

/* =========================================================
 * CONTENT
 * ========================================================= */
class _DrilldownContent extends StatelessWidget {
  final TaxSettlementItemsPage drilldown;
  final String currency;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onPageSizeChanged;
  const _DrilldownContent({
    required this.drilldown,
    required this.currency,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });
  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ScreenScalingService.scaleSize(context, 10);
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              ScreenScalingService.scaleSize(context, 16),
            ),
            children: [
              /*
               * BATCH SUMMARY
               */
              _SettlementSummaryCard(drilldown: drilldown, currency: currency),
              SizedBox(height: ScreenScalingService.scaleSize(context, 20)),
              /*
               * ITEMS HEADER
               */
              _SectionHeader(
                title: 'Settlement Items',
                trailing: drilldown.pagination.totalEntries.toString(),
              ),
              SizedBox(height: ScreenScalingService.scaleSize(context, 10)),
              /*
               * ITEMS
               */
              if (!drilldown.hasItems)
                SizedBox(
                  height: ScreenScalingService.scaleSize(context, 220),
                  child: const AppEmptyState(),
                )
              else
                ...drilldown.items.map(
                  (item) => Padding(
                    padding: EdgeInsets.only(
                      bottom: ScreenScalingService.scaleSize(context, 10),
                    ),
                    child: _SettlementItemCard(item: item, currency: currency),
                  ),
                ),
            ],
          ),
        ),
        /*
         * FIXED PAGINATION
         */
        AppPagination(
          page: drilldown.pagination.page,
          totalPages: drilldown.pagination.totalPages,
          totalEntries: drilldown.pagination.totalEntries,
          hasPrevious: drilldown.pagination.hasPrevious,
          hasNext: drilldown.pagination.hasNext,
          pageSize: drilldown.pagination.pageSize,
          entryLabel: 'items',
          onPrevious: () => onPrevious?.call(),
          onNext: () => onNext?.call(),
          onPageSizeChanged: onPageSizeChanged,
        ),
      ],
    );
  }
}

/* =========================================================
 * BATCH SUMMARY
 * ========================================================= */
class _SettlementSummaryCard extends StatelessWidget {
  final TaxSettlementItemsPage drilldown;
  final String currency;
  const _SettlementSummaryCard({
    required this.drilldown,
    required this.currency,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Government Tax Settlement',
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                currency.toUpperCase(),
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
          _SummaryRow(
            label: 'Total Amount',
            value: NumberFormatService.formatAmount(
              drilldown.totalAmount,
              currency: currency,
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
 * ITEM CARD
 * ========================================================= */
class _SettlementItemCard extends StatelessWidget {
  final TaxSettlementItem item;
  final String currency;
  const _SettlementItemCard({required this.item, required this.currency});
  @override
  Widget build(BuildContext context) {
    final radius = ScreenScalingService.scaleSize(context, 14);
    final errorMessage = item.errorMessage?.trim();
    return Container(
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 14)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /*
           * ITEM STATUS
           */
          Row(
            children: [
              Text(
                'Status',
                style: AppTextStyles.tiny(context).copyWith(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _ItemStatusBadge(status: item.status),
            ],
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 12)),
          /*
           * TAX
           */
          _AmountRow(
            label: 'Tax',
            value: item.totalTaxAmount,
            currency: currency,
            strong: true,
          ),
          SizedBox(height: ScreenScalingService.scaleSize(context, 10)),
          /*
           * WITHDRAWAL VOLUME
           */
          _AmountRow(
            label: 'Withdrawal Volume',
            value: item.totalAmount,
            currency: currency,
          ),
          /*
           * ERROR
           */
          if (errorMessage != null && errorMessage.isNotEmpty) ...[
            SizedBox(height: ScreenScalingService.scaleSize(context, 14)),
            _ItemErrorMessage(message: errorMessage),
          ],
        ],
      ),
    );
  }
}

/* =========================================================
 * ITEM STATUS BADGE
 * ========================================================= */
class _ItemStatusBadge extends StatelessWidget {
  final String status;
  const _ItemStatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenScalingService.scaleSize(context, 9),
        vertical: ScreenScalingService.scaleSize(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 20),
        ),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        _formatStatus(status),
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String value) {
    switch (value.trim().toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'pending':
        return Colors.amber;
      case 'approved':
        return Colors.blue;
      case 'processing':
        return Colors.amber;
      case 'partial':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      case 'settled':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Unknown';
    }
    return normalized
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}'
                    '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

/* =========================================================
 * ITEM ERROR MESSAGE
 * ========================================================= */
class _ItemErrorMessage extends StatelessWidget {
  final String message;
  const _ItemErrorMessage({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 10)),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 10),
        ),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: ScreenScalingService.scaleSize(context, 17),
            color: Colors.red,
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
 * AMOUNT ROW
 * ========================================================= */
class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final bool strong;
  const _AmountRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: Colors.grey.shade500, fontWeight: FontWeight.w600),
        ),
        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: strong
              ? AppTextStyles.mediumNumber(
                  context,
                ).copyWith(fontWeight: FontWeight.w700)
              : AppTextStyles.smallNumber(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/* =========================================================
 * SUMMARY ROW
 * ========================================================= */
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: Colors.grey.shade500, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: AppTextStyles.mediumNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/* =========================================================
 * SECTION HEADER
 * ========================================================= */
class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;
  const _SectionHeader({required this.title, required this.trailing});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ScreenScalingService.scaleSize(context, 9),
            vertical: ScreenScalingService.scaleSize(context, 4),
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            trailing,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/* =========================================================
 * REFRESHABLE STATE
 * ========================================================= */
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
