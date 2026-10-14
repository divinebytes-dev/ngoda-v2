import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gl/gl_totals.dart';
import 'package:ngoda/data_models/gl/token_gl_account_summary.dart';
import 'package:ngoda/data_models/gl/token_gl_summary.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/treasury/provider/gold_token_balances_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class TokenGlAccountBalanceScreen extends ConsumerWidget {
  const TokenGlAccountBalanceScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(goldTokenBalancesProvider);

    await ref.read(goldTokenBalancesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(goldTokenBalancesProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: balancesAsync.when(
            loading: () => const AppLoader(
              message: 'Loading token GL balances',
              fullScreen: true,
            ),
            error: (error, _) {
              return _RefreshableState(
                child: AppErrorState(message: error.toString()),
              );
            },
            data: (response) {
              if (response.error != null) {
                return _RefreshableState(
                  child: AppErrorState(message: response.error.toString()),
                );
              }

              final summary = response.result;

              if (summary == null) {
                return const _RefreshableState(child: AppEmptyState());
              }

              return _GlBalancesContent(summary: summary);
            },
          ),
        ),
      ),
    );
  }
}

class _GlBalancesContent extends StatelessWidget {
  const _GlBalancesContent({required this.summary});

  final TokenGLSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: ViewHeader(
            title: 'Gold Token GL Account Balances',
            onClose: () {
              context.pop();
            },
          ),
        ),
        SliverToBoxAdapter(child: _GlHeader(summary: summary)),
        SliverToBoxAdapter(
          child: _AccountsHeader(accountCount: summary.accountCount),
        ),
        if (!summary.hasAccounts)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: AppEmptyState()),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(spacing.lg, spacing.sm, spacing.lg, 0),
            sliver: SliverList.separated(
              itemCount: summary.accounts.length,
              itemBuilder: (context, index) {
                final account = summary.accounts[index];

                return _GlAccountCard(
                  account: account,
                  currency: summary.currencyCode,
                );
              },
              separatorBuilder: (context, index) {
                return SizedBox(height: spacing.sm);
              },
            ),
          ),
        SliverToBoxAdapter(
          child: _TotalsCard(
            totals: summary.totals,
            currency: summary.currencyCode,
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: spacing.xl)),
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
        ViewHeader(
          title: 'Gold Token GL Account Balances',
          onClose: () {
            context.pop();
          },
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class _GlHeader extends StatelessWidget {
  const _GlHeader({required this.summary});

  final TokenGLSummary summary;

  static const Color gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(spacing.lg, spacing.sm, spacing.lg, 0),
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.token_rounded,
                  color: gold,
                  size: iconSize.small,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gold Token',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '${summary.currencyCode.toUpperCase()} GL balances',
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
          Divider(height: 1, color: colorScheme.outlineVariant),
          SizedBox(height: spacing.md),
          _HeaderRow(
            label: 'Fiscal Year',
            value: summary.fiscalYear.toString(),
          ),
          SizedBox(height: spacing.sm),
          _HeaderRow(label: 'Period', value: summary.period.toString()),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.small(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({required this.accountCount});

  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, spacing.xl, spacing.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Token GL Accounts',
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
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            child: Text(
              accountCount.toString(),
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

class _GlAccountCard extends StatelessWidget {
  const _GlAccountCard({required this.account, required this.currency});

  final TokenGLAccountSummary account;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final borderRadius = BorderRadius.circular(radius.borderRadius);

    return Material(
      color: colorScheme.surface,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          final params = GlDrilldownParams(
            gl: account.accountCode.trim(),
            currency: currency,
          );

          context.push('/tokens/gl-balances/$params', extra: params);
        },
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      account.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: spacing.xs),
              Text(
                account.accountCode,
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: spacing.md),
              _BalanceRow(
                label: 'Opening',
                value: account.opening,
                strong: true,
              ),
              SizedBox(height: spacing.sm),
              _DebitCreditRow(debit: account.debit, credit: account.credit),
              SizedBox(height: spacing.sm),
              Divider(height: 1, color: colorScheme.outlineVariant),
              SizedBox(height: spacing.sm),
              _BalanceRow(
                label: 'Closing',
                value: account.closing,
                strong: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.currency});

  final GLTotals totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.fromLTRB(spacing.lg, spacing.xl, spacing.lg, 0),
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gold Token Totals',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          _BalanceRow(label: 'Opening', value: totals.opening, strong: true),
          SizedBox(height: spacing.sm),
          _DebitCreditRow(debit: totals.debit, credit: totals.credit),
          SizedBox(height: spacing.sm),
          Divider(height: 1, color: colorScheme.outlineVariant),
          SizedBox(height: spacing.sm),
          _BalanceRow(label: 'Closing', value: totals.closing, strong: true),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        Text(
          NumberFormatService.formatBalance(value),
          style:
              (strong
                      ? AppTextStyles.smallNumber(context)
                      : AppTextStyles.tinyNumber(context))
                  .copyWith(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                  ),
        ),
      ],
    );
  }
}

class _DebitCreditRow extends StatelessWidget {
  const _DebitCreditRow({required this.debit, required this.credit});

  final double debit;
  final double credit;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Debit / Credit',
          style: AppTextStyles.tiny(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          children: [
            Text(
              NumberFormatService.formatBalance(debit),
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: spacing.sm),
            Text(
              '/',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
            SizedBox(width: spacing.sm),
            Text(
              NumberFormatService.formatBalance(credit),
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
