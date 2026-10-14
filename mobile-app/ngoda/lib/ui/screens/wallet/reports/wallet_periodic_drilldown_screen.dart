import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/wallet_entry_params.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_entry.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/wallet_periodic_balances_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class WalletPeriodicDrilldownScreen extends ConsumerStatefulWidget {
  const WalletPeriodicDrilldownScreen({super.key, required this.params});

  final WalletEntryParams params;

  @override
  ConsumerState<WalletPeriodicDrilldownScreen> createState() =>
      _WalletPeriodicDrilldownScreenState();
}

class _WalletPeriodicDrilldownScreenState
    extends ConsumerState<WalletPeriodicDrilldownScreen> {
  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
  }

  WalletEntryParams get currentParams {
    return widget.params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(walletPeriodicBalancesProvider(currentParams));

    await ref.read(walletPeriodicBalancesProvider(currentParams).future);
  }

  void _previousPage() {
    if (currentPage <= 1) {
      return;
    }

    setState(() {
      currentPage--;
    });
  }

  void _nextPage() {
    setState(() {
      currentPage++;
    });
  }

  void _changePageSize(int newPageSize) {
    if (newPageSize == pageSize) {
      return;
    }

    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final drilldownAsync = ref.watch(
      walletPeriodicBalancesProvider(currentParams),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Wallet Period Details',
              onClose: () {
                ref.invalidate(walletPeriodicBalancesProvider(currentParams));

                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: drilldownAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading wallet entries',
                    fullScreen: false,
                  ),
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(message: error.toString()),
                  ),
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

class _DrilldownContent extends StatelessWidget {
  const _DrilldownContent({
    required this.drilldown,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final PeriodicBalanceDrilldown drilldown;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final pagination = drilldown.pagination;

    final role = getCurrentUser().role;
    final canDisplay = role == 'finance' || role == 'accounts';

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.sm,
              spacing.md,
              spacing.lg,
            ),
            children: [
              _PeriodSummaryCard(drilldown: drilldown),

              SizedBox(height: spacing.lg),

              _SectionHeader(
                title: 'Wallet entries',
                description: 'Movements recorded in this fiscal period.',
                count: pagination.totalEntries,
              ),

              SizedBox(height: spacing.sm),

              if (!drilldown.hasEntries)
                const SizedBox(height: 220, child: AppEmptyState())
              else
                for (
                  var index = 0;
                  index < drilldown.entries.length;
                  index++
                ) ...[
                  _WalletEntryCard(
                    entry: drilldown.entries[index],
                    currency: drilldown.currencyCode,
                    onTap:
                        drilldown.entries[index].documentNumber.isEmpty ||
                            !canDisplay
                        ? null
                        : () {
                            context.push(
                              '/recent-transactions/'
                              '${drilldown.entries[index].documentNumber}',
                            );
                          },
                  ),

                  if (index < drilldown.entries.length - 1)
                    SizedBox(height: spacing.sm),
                ],
            ],
          ),
        ),

        if (pagination.totalEntries > 0)
          AppPagination(
            page: pagination.page,
            totalPages: pagination.totalPages,
            totalEntries: pagination.totalEntries,
            hasPrevious: pagination.hasPrevious,
            hasNext: pagination.hasNext,
            pageSize: pagination.pageSize,
            onPrevious: onPrevious ?? () {},
            onNext: onNext ?? () {},
            onPageSizeChanged: onPageSizeChanged,
          ),
      ],
    );
  }
}

class _PeriodSummaryCard extends StatelessWidget {
  const _PeriodSummaryCard({required this.drilldown});

  final PeriodicBalanceDrilldown drilldown;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final currency = drilldown.currencyCode;

    final symbol = CurrencyService.symbol(currency);

    final name = CurrencyService.name(currency);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(
          color: drilldown.hasDifference
              ? colorScheme.error.withValues(alpha: 0.09)
              : _gold.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CurrencyIcon(currency: currency, symbol: symbol),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      '${currency.toUpperCase()}'
                      ' • FY ${drilldown.fiscalYear}'
                      ' • Period ${drilldown.period}',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              _ReconciliationBadge(hasDifference: drilldown.hasDifference),
            ],
          ),

          SizedBox(height: spacing.lg),

          _SummaryRow(
            label: 'Opening balance',
            value: drilldown.openingBalance,
            currency: currency,
            strong: true,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Total debit',
            value: drilldown.totalDebit,
            currency: currency,
            valueColor: colorScheme.error,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Total credit',
            value: drilldown.totalCredit,
            currency: currency,
            valueColor: AppColors.success,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Net movement',
            value: drilldown.movement,
            currency: currency,
          ),

          SizedBox(height: spacing.md),

          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),

          SizedBox(height: spacing.md),

          _SummaryRow(
            label: 'Calculated closing',
            value: drilldown.calculatedClosingBalance,
            currency: currency,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Snapshot closing',
            value: drilldown.closingBalance,
            currency: currency,
            strong: true,
          ),

          if (drilldown.hasDifference) ...[
            SizedBox(height: spacing.md),

            _DifferencePanel(
              difference: drilldown.difference,
              currency: currency,
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrencyIcon extends StatelessWidget {
  const _CurrencyIcon({required this.currency, required this.symbol});

  final String currency;
  final String symbol;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final fallback = currency.isEmpty
        ? '?'
        : currency
              .substring(0, currency.length >= 2 ? 2 : currency.length)
              .toUpperCase();

    return Container(
      width: spacing.xxl,
      height: spacing.xxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: symbol.toLowerCase() == "gold"
          ? Text(
              symbol.isNotEmpty ? symbol : fallback,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700),
            )
          : Text(
              symbol.isNotEmpty ? symbol : fallback,
              style: AppTextStyles.small(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700),
            ),
    );
  }
}

class _ReconciliationBadge extends StatelessWidget {
  const _ReconciliationBadge({required this.hasDifference});

  final bool hasDifference;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final color = hasDifference ? colorScheme.error : AppColors.success;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDifference
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),

          SizedBox(width: spacing.xs),

          Text(
            hasDifference ? 'Difference' : 'Balanced',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DifferencePanel extends StatelessWidget {
  const _DifferencePanel({required this.difference, required this.currency});

  final double difference;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(spacing.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance difference',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  'The calculated and snapshot closing balances do not match.',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          SizedBox(width: spacing.sm),

          Text(
            NumberFormatService.formatAmount(difference, currency: currency),
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final double value;
  final String currency;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    final valueStyle = strong
        ? AppTextStyles.smallNumber(context)
        : AppTextStyles.tinyNumber(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: strong
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),

        SizedBox(width: context.spacing.sm),

        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: valueStyle.copyWith(
            color: valueColor,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.description,
    required this.count,
  });

  final String title;
  final String description;
  final int count;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.medium(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              SizedBox(height: spacing.xs),

              Text(
                description,
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        SizedBox(width: spacing.sm),

        Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.xs,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(spacing.md),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _WalletEntryCard extends StatelessWidget {
  const _WalletEntryCard({
    required this.entry,
    required this.currency,
    required this.onTap,
  });

  final PeriodicBalanceEntry entry;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final movementColor = entry.isDebit
        ? colorScheme.error
        : entry.isCredit
        ? AppColors.success
        : colorScheme.onSurfaceVariant;

    final movementAmount = entry.isDebit
        ? entry.debit
        : entry.isCredit
        ? entry.credit
        : 0.0;

    final movementPrefix = entry.isDebit
        ? '-'
        : entry.isCredit
        ? '+'
        : '';

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.md),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  _MovementIcon(
                    isDebit: entry.isDebit,
                    isCredit: entry.isCredit,
                  ),

                  SizedBox(width: spacing.md),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTxType(entry.transactionType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$movementPrefix'
                        '${NumberFormatService.formatAmount(movementAmount, currency: currency)}',
                        style: AppTextStyles.smallNumber(context).copyWith(
                          color: movementColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      SizedBox(height: spacing.xs),

                      Text(
                        DateFormatService.formatDisplayDate(entry.createdAt),
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),

                  if (onTap != null) ...[
                    SizedBox(width: spacing.xs),

                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),

              SizedBox(height: spacing.md),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),

              SizedBox(height: spacing.sm),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Running balance',
                      style: AppTextStyles.tiny(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Text(
                    NumberFormatService.formatAmount(
                      entry.runningBalance,
                      currency: currency,
                    ),
                    style: AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementIcon extends StatelessWidget {
  const _MovementIcon({required this.isDebit, required this.isCredit});

  final bool isDebit;
  final bool isCredit;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final Color color;
    final IconData icon;

    if (isDebit) {
      color = colorScheme.error;
      icon = Icons.arrow_upward_rounded;
    } else if (isCredit) {
      color = AppColors.success;
      icon = Icons.arrow_downward_rounded;
    } else {
      color = colorScheme.onSurfaceVariant;
      icon = Icons.remove_rounded;
    }

    return Container(
      width: spacing.xl,
      height: spacing.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
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
