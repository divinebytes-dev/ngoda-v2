import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_entry.dart';
import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_page.dart';
import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_type.dart';
import 'package:ngoda/data_models/params/loyalty_ledger_params.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/gamification/provider/loyalty_ledger_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LoyaltyLedgerScreen extends ConsumerStatefulWidget {
  final LoyaltyLedgerParams params;

  const LoyaltyLedgerScreen({
    super.key,
    this.params = const LoyaltyLedgerParams(),
  });

  @override
  ConsumerState<LoyaltyLedgerScreen> createState() {
    return _LoyaltyLedgerScreenState();
  }
}

class _LoyaltyLedgerScreenState extends ConsumerState<LoyaltyLedgerScreen> {
  late int currentPage;
  late int pageSize;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;

    pageSize = widget.params.pageSize;
  }

  LoyaltyLedgerParams get currentParams {
    return widget.params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(loyaltyLedgerProvider(currentParams));

    await ref.read(loyaltyLedgerProvider(currentParams).future);
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
    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(loyaltyLedgerProvider(currentParams));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Points History',
              onClose: () {
                ref.invalidate(loyaltyLedgerProvider(currentParams));

                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ledgerAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading points history',
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

                    final ledger = response.result;

                    if (ledger == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _LedgerContent(
                      ledger: ledger,
                      pageSize: pageSize,
                      onPrevious: ledger.pagination.hasPrevious
                          ? _previousPage
                          : null,
                      onNext: ledger.pagination.hasNext ? _nextPage : null,
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

class _LedgerContent extends StatelessWidget {
  final LoyaltyLedgerPage ledger;
  final int pageSize;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onPageSizeChanged;

  const _LedgerContent({
    required this.ledger,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
            children: [
              _HistorySummary(totalEntries: ledger.pagination.totalEntries),
              SizedBox(height: spacing.md),
              if (ledger.rows.isEmpty)
                SizedBox(
                  height: spacing.xxxxl * 4,
                  child: const AppEmptyState(),
                )
              else
                ...ledger.rows.map((entry) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _LedgerEntryCard(entry: entry),
                  );
                }),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.sm,
              spacing.md,
              spacing.sm,
            ),
            decoration: BoxDecoration(
              color: context.theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: AppPagination(
              page: ledger.pagination.page,
              totalPages: ledger.pagination.totalPages,
              totalEntries: ledger.pagination.totalEntries,
              hasPrevious: ledger.pagination.hasPrevious,
              hasNext: ledger.pagination.hasNext,
              onPrevious: onPrevious ?? () {},
              onNext: onNext ?? () {},
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

class _HistorySummary extends StatelessWidget {
  final int totalEntries;

  const _HistorySummary({required this.totalEntries});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: _LedgerColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: _LedgerColors.gold.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: iconSize.medium,
            color: _LedgerColors.gold,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'Every points movement is recorded here.',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: spacing.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.sm,
            ),
            decoration: BoxDecoration(
              color: context.colorScheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(radius.borderRadius),
              border: Border.all(
                color: context.colorScheme.outlineVariant.withValues(
                  alpha: 0.09,
                ),
              ),
            ),
            child: Text(
              totalEntries.toString(),
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerEntryCard extends StatelessWidget {
  final LoyaltyLedgerEntry entry;

  const _LedgerEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final positive = entry.pointsDelta > 0;

    final neutral = entry.pointsDelta == 0;

    final color = neutral
        ? colorScheme.onSurfaceVariant
        : positive
        ? _LedgerColors.success
        : colorScheme.error;

    final prefix = positive ? '+' : '';

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _ledgerIcon(entry.ledgerType),
                  color: color,
                  size: iconSize.medium,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.description ?? _formatLabel(entry.eventType),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      DateFormatService.formatDateTime(entry.createdAt),
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                '$prefix${_formatPoints(entry.pointsDelta)} pts',
                style: AppTextStyles.smallNumber(
                  context,
                ).copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Divider(
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.12),
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: _BalanceValue(
                  label: 'Available balance',
                  value: entry.availableBalanceAfter,
                ),
              ),
              Container(
                height: iconSize.xl,
                width: 1,
                color: colorScheme.outline.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _BalanceValue(
                  label: 'Tier balance',
                  value: entry.tierBalanceAfter,
                ),
              ),
            ],
          ),
          // if (entry.sourceReference != null) ...[
          //   SizedBox(height: spacing.sm),
          //   Align(
          //     alignment: Alignment.centerLeft,
          //     child: Text(
          //       'Reference: ${entry.sourceReference}',
          //       maxLines: 1,
          //       overflow: TextOverflow.ellipsis,
          //       style: AppTextStyles.tiny(
          //         context,
          //       ).copyWith(color: colorScheme.onSurfaceVariant),
          //     ),
          //   ),
          // ],
        ],
      ),
    );
  }
}

class _BalanceValue extends StatelessWidget {
  final String label;
  final int value;

  const _BalanceValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: spacing.xs),
        Text(
          _formatPoints(value),
          style: AppTextStyles.tinyNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
      ],
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

abstract final class _LedgerColors {
  static const gold = Color(0xFFD4AF37);

  static const success = Color(0xFF19B76A);
}

IconData _ledgerIcon(LoyaltyLedgerType type) {
  return switch (type) {
    LoyaltyLedgerType.earn => Icons.add_rounded,
    LoyaltyLedgerType.redeem => Icons.card_giftcard_rounded,
    LoyaltyLedgerType.reverse => Icons.undo_rounded,
    LoyaltyLedgerType.expire => Icons.schedule_rounded,
    LoyaltyLedgerType.adjustment => Icons.tune_rounded,
    LoyaltyLedgerType.unknown => Icons.stars_rounded,
  };
}

String _formatLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Points activity';
  }

  return value
      .trim()
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _formatPoints(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
