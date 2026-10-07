import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/commission/settlement_batch.dart';
import 'package:ngoda/data_models/commission/settlement_batch_data.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/providers/settlement_data_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class SettledCommissionSummaryScreen extends ConsumerWidget {
  const SettledCommissionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(settlementDataProvider(const ['settled']));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Settled Agents Commission Summary',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(
                  message: 'Loading settled commission',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(message: response.error.toString());
                  }

                  final settlementData = response.result;

                  if (settlementData == null ||
                      settlementData.batches.isEmpty) {
                    return const AppEmptyState(
                      message: 'No settled commission settlement',
                    );
                  }

                  return _TransactionBody(settlementData: settlementData);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionBody extends StatefulWidget {
  const _TransactionBody({required this.settlementData});

  final SettlementBatchData settlementData;

  @override
  State<_TransactionBody> createState() => _TransactionBodyState();
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.settlementData.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.settlementData.currencyList.length !=
        widget.settlementData.currencyList.length) {
      _tabController.dispose();

      _tabController = TabController(length: currencies.length, vsync: this);
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

    if (currencies.isEmpty) {
      return const AppEmptyState(message: 'No settled commission settlement');
    }

    return Column(
      children: [
        CurrencyTabs(controller: _tabController, currencies: currencies),
        SizedBox(height: spacing.sm),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final batch = widget.settlementData.batchByCurrency(currency);

              if (batch == null) {
                return const AppEmptyState(
                  message: 'No settled settlement batch',
                );
              }

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.sm,
                  0,
                  spacing.sm,
                  spacing.lg,
                ),
                child: _SettlementBatchCard(currency: currency, batch: batch),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettlementBatchCard extends StatelessWidget {
  const _SettlementBatchCard({required this.currency, required this.batch});

  final String currency;
  final SettlementBatch batch;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final statusColor = _statusColor(batch.status, colorScheme);

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        onTap: () {
          context.push(
            '/payments/commission-summary/entries',
            extra: SettlementItemsParams(
              batchId: batch.id,
              currency: batch.currencyCode,
              page: 1,
              pageSize: 50,
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commission Settlement',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          'FY ${batch.fiscalYear} • '
                          'Period ${batch.period}',
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: batch.status, color: statusColor),
                  SizedBox(width: spacing.xs),
                  Icon(
                    Icons.chevron_right,
                    size: iconSize.small,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              AppValueRow(label: 'Agents', value: batch.totalAgents.toString()),
              AppValueRow(
                label: 'Total Amount',
                value: NumberFormatService.formatAmount(
                  batch.totalAmount,
                  currency: currency,
                ),
              ),
              AppValueRow(
                label: 'Start Date',
                value: DateFormatService.formatDisplayDate(batch.startDate),
              ),
              AppValueRow(
                label: 'End Date',
                value: DateFormatService.formatDisplayDate(batch.endDate),
              ),
              AppValueRow(
                label: 'Document Number',
                value: batch.documentNumber,
              ),
              if (batch.reference != null && batch.reference!.trim().isNotEmpty)
                AppValueRow(label: 'Reference', value: batch.reference!),
              if (batch.approvedAt != null)
                AppValueRow(
                  label: 'Approved At',
                  value: DateFormatService.formatDisplayDate(batch.approvedAt!),
                ),
              if (batch.errorMessage != null &&
                  batch.errorMessage!.trim().isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                _ErrorCard(message: batch.errorMessage!),
              ],
              SizedBox(height: spacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: iconSize.small,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: spacing.xs),
                  Text(
                    'View settlement items',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    currency.toUpperCase(),
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    switch (status.trim().toLowerCase()) {
      case 'partial':
        return Colors.orange;

      case 'processing':
      case 'pending':
        return Colors.amber;

      case 'failed':
        return colorScheme.error;

      case 'settled':
        return Colors.green;

      case 'draft':
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        _formatStatus(status),
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: iconSize.small,
            color: colorScheme.error,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
