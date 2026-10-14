import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/gl/gl_period_balance.dart';
import 'package:ngoda/data_models/params/wallet_entry_params.dart';
import 'package:ngoda/data_models/params/wallet_snapshot_params.dart';
import 'package:ngoda/data_models/wallet/wallet_periodic_balance.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/wallet_balance_snapshot_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class WalletBalanceSnapshotScreen extends ConsumerWidget {
  const WalletBalanceSnapshotScreen({
    super.key,
    required this.currency,
    required this.walletOwner,
    this.blockchainCode,
  });

  final String currency;
  final String walletOwner;
  final String? blockchainCode;

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Validate GOLD blockchain before creating the parameters.
    if (currency.trim().toLowerCase() == 'gold' &&
        (blockchainCode == null || blockchainCode!.trim().isEmpty)) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ViewHeader(
                title: 'Wallet Balance Snapshots',
                onClose: () => context.pop(),
              ),
              const Expanded(
                child: AppErrorState(
                  message:
                      'Blockchain information is missing for this GOLD wallet. '
                      'Please go back and select a blockchain.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final params = WalletSnapshotParams(
      currency: currency,
      walletOwner: walletOwner,
      blockchainCode: blockchainCode,
    );

    final snapshotAsync = ref.watch(walletBalanceSnapshotProvider(params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Wallet Balance Snapshots',
              onClose: () {
                ref.invalidate(walletBalanceSnapshotProvider(params));
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(ref, params),
                child: snapshotAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading wallet snapshot',
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

                    final snapshot = response.result;

                    if (snapshot == null || snapshot.periods.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _WalletSnapshotContent(
                      snapshot: snapshot,
                      currency: currency,
                      walletOwner: walletOwner,
                      blockchainCode: blockchainCode,
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

  Future<void> _refresh(WidgetRef ref, WalletSnapshotParams params) async {
    ref.invalidate(walletBalanceSnapshotProvider(params));

    await ref.read(walletBalanceSnapshotProvider(params).future);
  }
}

class _WalletSnapshotContent extends StatelessWidget {
  const _WalletSnapshotContent({
    required this.snapshot,
    required this.currency,
    required this.walletOwner,
    this.blockchainCode,
  });

  final WalletBalancePeriod snapshot;
  final String currency;
  final String walletOwner;
  final String? blockchainCode;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.lg,
      ),
      children: [
        _SnapshotHeader(snapshot: snapshot, currency: currency),

        SizedBox(height: spacing.lg),

        _SectionHeader(
          title: 'Fiscal periods',
          description: 'Select a period to view its wallet movements.',
          count: snapshot.periods.length,
        ),

        SizedBox(height: spacing.sm),

        for (var index = 0; index < snapshot.periods.length; index++) ...[
          _PeriodCard(
            period: snapshot.periods[index],
            currency: currency,
            onTap: () => _openPeriod(context, snapshot.periods[index]),
          ),

          if (index < snapshot.periods.length - 1) SizedBox(height: spacing.sm),
        ],
      ],
    );
  }

  void _openPeriod(BuildContext context, GLPeriodBalance period) {
    /*
     * Preserve the existing route
     * contract.
     *
     * Agent wallets use the agent-wallet
     * route. Other wallet owners currently
     * use the treasury-wallet route.
     */
    var url = '/treasury-wallet/$walletOwner/$currency/wallet-entry';

    if (walletOwner == 'agent') {
      url = '/agent-wallet/$walletOwner/$currency/wallet-entry';
    } else if (walletOwner == 'vendor') {
      url = '/vendor-wallet/$walletOwner/$currency/wallet-entry';
    }

    context.push(
      url,
      extra: WalletEntryParams(
        currency: currency,
        fiscalYear: snapshot.fiscalYear,
        period: period.period,
        walletOwner: walletOwner,
        blockchainCode: blockchainCode,
      ),
    );
  }
}

class _SnapshotHeader extends StatelessWidget {
  const _SnapshotHeader({required this.snapshot, required this.currency});

  final WalletBalancePeriod snapshot;
  final String currency;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final symbol = CurrencyService.symbol(currency);

    final name = CurrencyService.name(currency);

    final opening = snapshot.opening;

    final closing = snapshot.closing;

    final movement = snapshot.totalCredit - snapshot.totalDebit;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
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
                      '${currency.toUpperCase()} • Fiscal year ${snapshot.fiscalYear}',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.lg),

          _SummaryAmount(
            label: 'Closing balance',
            value: closing,
            currency: currency,
          ),

          SizedBox(height: spacing.md),

          Divider(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            height: 1,
          ),

          SizedBox(height: spacing.md),

          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Opening',
                  value: opening,
                  currency: currency,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: _Metric(
                  label: 'Net movement',
                  value: movement,
                  currency: currency,
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.md),

          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Total debit',
                  value: snapshot.totalDebit,
                  currency: currency,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: _Metric(
                  label: 'Total credit',
                  value: snapshot.totalCredit,
                  currency: currency,
                ),
              ),
            ],
          ),
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
      child: Text(
        symbol.isNotEmpty ? symbol : fallback,
        style: currency.toLowerCase() == "gold"
            ? AppTextStyles.tiny(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700)
            : AppTextStyles.small(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SummaryAmount extends StatelessWidget {
  const _SummaryAmount({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.xs),

        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: AppTextStyles.mediumNumber(context),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.xs),

        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
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
            style: AppTextStyles.tiny(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.period,
    required this.currency,
    required this.onTap,
  });

  final GLPeriodBalance period;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final movement = period.credit - period.debit;

    final hasActivity = period.debit != 0 || period.credit != 0;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spacing.md),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Period ${period.period}',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),

                        SizedBox(height: spacing.xs),

                        Text(
                          hasActivity
                              ? 'Wallet activity recorded'
                              : 'No movement recorded',
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),

              SizedBox(height: spacing.md),

              _BalanceRow(
                label: 'Opening',
                value: period.opening,
                currency: currency,
                strong: true,
              ),

              SizedBox(height: spacing.sm),

              _DebitCreditRow(
                debit: period.debit,
                credit: period.credit,
                currency: currency,
              ),

              SizedBox(height: spacing.sm),

              _BalanceRow(
                label: 'Net movement',
                value: movement,
                currency: currency,
              ),

              SizedBox(height: spacing.sm),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),

              SizedBox(height: spacing.sm),

              _BalanceRow(
                label: 'Closing',
                value: period.closing,
                currency: currency,
                strong: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
  });

  final String label;
  final double value;
  final String currency;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

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
          style:
              (strong
                      ? AppTextStyles.smallNumber(context)
                      : AppTextStyles.tinyNumber(context))
                  .copyWith(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  ),
        ),
      ],
    );
  }
}

class _DebitCreditRow extends StatelessWidget {
  const _DebitCreditRow({
    required this.debit,
    required this.credit,
    required this.currency,
  });

  final double debit;
  final double credit;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Debit / Credit',
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        SizedBox(width: spacing.sm),

        Flexible(
          child: Text(
            NumberFormatService.formatAmount(debit, currency: currency),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w600),
          ),
        ),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.sm),
          child: Text(
            '/',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),

        Flexible(
          child: Text(
            NumberFormatService.formatAmount(credit, currency: currency),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
