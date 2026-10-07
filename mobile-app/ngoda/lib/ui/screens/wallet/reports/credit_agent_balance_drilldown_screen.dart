import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/merchant/credit_agent_balance_drilldown.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/credit_agent_balance_drilldown_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CreditAgentBalanceDrilldownScreen extends ConsumerStatefulWidget {
  const CreditAgentBalanceDrilldownScreen({super.key, required this.params});

  final CreditAgentBalanceParams params;

  @override
  ConsumerState<CreditAgentBalanceDrilldownScreen> createState() =>
      _CreditAgentBalanceDrilldownScreenState();
}

class _CreditAgentBalanceDrilldownScreenState
    extends ConsumerState<CreditAgentBalanceDrilldownScreen> {
  late final String merchantId;
  late final String currency;

  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    final paramUserId = widget.params.merchantId?.trim();
    final paramCurrency = widget.params.currency?.trim().toLowerCase();

    if (paramUserId == null || paramUserId.isEmpty) {
      throw ArgumentError('CreditAgentBalanceDrilldownScreen requires userId');
    }

    if (paramCurrency == null || paramCurrency.isEmpty) {
      throw ArgumentError(
        'CreditAgentBalanceDrilldownScreen requires currency',
      );
    }

    merchantId = paramUserId;
    currency = paramCurrency;

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;
  }

  CreditAgentBalanceParams get currentParams {
    return widget.params.copyWith(
      merchantId: merchantId,
      currency: currency,
      page: currentPage,
      pageSize: pageSize,
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(creditAgentBalanceDrilldownProvider(currentParams));

    await ref.read(creditAgentBalanceDrilldownProvider(currentParams).future);
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

  void _closeScreen() {
    ref.invalidate(creditAgentBalanceDrilldownProvider(currentParams));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final drilldownAsync = ref.watch(
      creditAgentBalanceDrilldownProvider(currentParams),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Credit Agent Details', onClose: _closeScreen),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: drilldownAsync.when(
                  loading: () {
                    return const AppLoader(
                      message: 'Loading credit agent details',
                      fullScreen: false,
                    );
                  },
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
                      pageSize: pageSize,
                      onPrevious: _previousPage,
                      onNext: _nextPage,
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
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final CreditAgentBalanceDrilldown drilldown;
  final int pageSize;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.md),
            children: [
              _MerchantHeaderCard(
                merchant: drilldown.merchant,
                account: drilldown.account,
              ),
              SizedBox(height: spacing.sm),
              _AccountSummaryCard(
                account: drilldown.account,
                opening: drilldown.opening,
              ),
              SizedBox(height: spacing.lg),
              _SectionHeader(
                title: 'Account Activity',
                trailing: drilldown.pagination.totalEntries.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (drilldown.entries.isEmpty)
                const _InlineEmptyState()
              else
                ...drilldown.entries.map((entry) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _DrilldownEntryCard(
                      entry: entry,
                      onTap: () {
                        if (entry.documentNumber.isEmpty) {
                          return;
                        }

                        context.push(
                          '/profile/recent-transactions/'
                          '${entry.documentNumber}',
                        );
                      },
                    ),
                  );
                }),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.xs),
            child: AppPagination(
              page: drilldown.pagination.page,
              totalPages: drilldown.pagination.totalPages,
              totalEntries: drilldown.pagination.totalEntries,
              hasPrevious: drilldown.pagination.hasPrevious,
              hasNext: drilldown.pagination.hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
              pageSize: pageSize,
              onPageSizeChanged: onPageSizeChanged,
              entryLabel: 'entries',
            ),
          ),
        ),
      ],
    );
  }
}

class _MerchantHeaderCard extends StatelessWidget {
  const _MerchantHeaderCard({required this.merchant, required this.account});

  final CreditAgentDrilldownMerchant merchant;
  final CreditAgentDrilldownAccount account;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final primary = colorScheme.primary;

    return Container(
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(radius.sm),
        ),
        child: Row(
          children: [
            Container(
              width: spacing.xl,
              height: spacing.xl,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store_outlined,
                color: primary,
                size: iconSize.small,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (merchant.contact.isNotEmpty) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      merchant.contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (merchant.address?.trim().isNotEmpty ?? false) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      merchant.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: spacing.sm),
            _StatusBadge(active: account.isActive),
          ],
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({required this.account, required this.opening});

  final CreditAgentDrilldownAccount account;
  final CreditAgentDrilldownOpening opening;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final currency = account.currencyCode;
    final symbol = CurrencyService.symbol(currency);
    final name = CurrencyService.name(currency);

    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(radius.sm),
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
                    color: primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    symbol.isNotEmpty ? symbol : currency.toUpperCase(),
                    style: AppTextStyles.medium(
                      context,
                    ).copyWith(color: primary, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        currency.toUpperCase(),
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: context.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            _SummaryRow(
              label: 'Current Cash Owed',
              value: account.currentCashHoldingBalance,
              currency: currency,
              valueColor: Colors.red,
              strong: true,
            ),
            SizedBox(height: spacing.sm),
            _SummaryRow(
              label: 'Current Receivable',
              value: account.currentReceivableBalance,
              currency: currency,
              valueColor: Colors.green,
              strong: true,
            ),
            SizedBox(height: spacing.sm),
            Divider(height: 1, color: AppColors.darkBorder),
            SizedBox(height: spacing.sm),
            _SummaryRow(
              label: 'Opening Cash Owed',
              value: opening.cashHoldingBalance,
              currency: currency,
            ),
            SizedBox(height: spacing.sm),
            _SummaryRow(
              label: 'Opening Receivable',
              value: opening.receivableBalance,
              currency: currency,
            ),
            if (opening.hasSettlement) ...[
              SizedBox(height: spacing.sm),
              Divider(height: 1, color: AppColors.darkBorder),
              SizedBox(height: spacing.sm),
              _SettlementInfo(opening: opening),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettlementInfo extends StatelessWidget {
  const _SettlementInfo({required this.opening});

  final CreditAgentDrilldownOpening opening;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.history_rounded,
          size: iconSize.small,
          color: colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last Settlement',
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (opening.lastSettlementDocumentNumber?.isNotEmpty ??
                  false) ...[
                SizedBox(height: spacing.xs),
                Text(
                  opening.lastSettlementDocumentNumber!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
              if (opening.lastSettlementAt != null) ...[
                SizedBox(height: spacing.xs),
                Text(
                  DateFormatService.formatDateTime(opening.lastSettlementAt!),
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DrilldownEntryCard extends StatelessWidget {
  const _DrilldownEntryCard({required this.entry, required this.onTap});

  final CreditAgentDrilldownEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final currency = entry.currencyCode;

    final receivableMovement = entry.receivableMovement;
    final cashMovement = entry.cashHoldingMovement;

    final hasReceivableMovement = receivableMovement != 0;
    final hasCashMovement = cashMovement != 0;

    final canOpenDocument = entry.documentNumber.isNotEmpty;

    return Material(
      color: AppColors.darkCard,
      borderRadius: BorderRadius.circular(radius.md),
      child: InkWell(
        onTap: canOpenDocument ? onTap : null,
        borderRadius: BorderRadius.circular(radius.md),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  _TransactionIcon(entry: entry),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      formatTxType(entry.transactionType),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateFormatService.formatDisplayDate(entry.createdAt),
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        'FY ${entry.fiscalYear} • P ${entry.period}',
                        style: AppTextStyles.tinyNumber(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (canOpenDocument) ...[
                    SizedBox(width: spacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: iconSize.small,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              if (hasCashMovement || hasReceivableMovement) ...[
                SizedBox(height: spacing.sm),
                Divider(height: 1, color: AppColors.darkBorder),
                SizedBox(height: spacing.sm),
              ],
              if (hasCashMovement)
                _MovementRow(
                  label: 'Cash Owed',
                  movement: cashMovement,
                  currency: currency,
                ),
              if (hasCashMovement && hasReceivableMovement)
                SizedBox(height: spacing.sm),
              if (hasReceivableMovement)
                _MovementRow(
                  label: 'Receivable',
                  movement: receivableMovement,
                  currency: currency,
                ),
              SizedBox(height: spacing.sm),
              Divider(height: 1, color: AppColors.darkBorder),
              SizedBox(height: spacing.sm),
              _RunningBalanceRow(
                label: 'Cash Owed Balance',
                value: entry.cashHoldingRunningBalance,
                currency: currency,
              ),
              SizedBox(height: spacing.sm),
              _RunningBalanceRow(
                label: 'Receivable Balance',
                value: entry.receivableRunningBalance,
                currency: currency,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionIcon extends StatelessWidget {
  const _TransactionIcon({required this.entry});

  final CreditAgentDrilldownEntry entry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;

    final cashMovement = entry.cashHoldingMovement;
    final receivableMovement = entry.receivableMovement;
    final totalMovement = cashMovement + receivableMovement;

    final Color color;
    final IconData icon;

    if (totalMovement > 0) {
      color = Colors.red;
      icon = Icons.arrow_upward_rounded;
    } else if (totalMovement < 0) {
      color = Colors.green;
      icon = Icons.arrow_downward_rounded;
    } else {
      color = AppColors.darkBorder;
      icon = Icons.swap_horiz_rounded;
    }

    return Container(
      width: spacing.xl,
      height: spacing.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: iconSize.small),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.label,
    required this.movement,
    required this.currency,
  });

  final String label;
  final double movement;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final increase = movement > 0;

    final color = increase ? Colors.red : Colors.green;

    final prefix = increase ? '+' : '-';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '$prefix'
          '${NumberFormatService.formatAmount(movement.abs(), currency: currency)}',
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _RunningBalanceRow extends StatelessWidget {
  const _RunningBalanceRow({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: AppTextStyles.tinyNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.currency,
    this.valueColor,
    this.strong = false,
  });

  final String label;
  final double value;
  final String currency;

  final Color? valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final valueStyle = strong
        ? AppTextStyles.smallNumber(context)
        : AppTextStyles.tinyNumber(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = active ? Colors.green : AppColors.darkBorder;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

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
            horizontal: spacing.sm,
            vertical: spacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(radius.sm),
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

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xl),
      child: const AppEmptyState(),
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
