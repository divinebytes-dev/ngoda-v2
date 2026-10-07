import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/treasury/treasury_balance_entry.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/treasury/provider/wallet_snapshot_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class PeriodicBalancesScreen extends ConsumerWidget {
  const PeriodicBalancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final asyncData = ref.watch(walletSnapshotProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Treasury Wallet Overview'),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(
                  message: 'Loading gold tokens periodic balances',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(
                    title: 'Error',
                    message: error.toString(),
                  );
                },
                data: (statement) {
                  if (statement.error != null) {
                    return AppErrorState(
                      title: 'Error',
                      message: statement.error,
                    );
                  }

                  final balances = statement.result;

                  if (balances == null) {
                    return const AppErrorState(
                      title: 'Error',
                      message: 'Wallet balances are not available',
                    );
                  }

                  return Column(
                    children: [
                      _BalanceHeader(
                        fiscalYear: balances.fiscalYear,
                        period: balances.period,
                      ),
                      SizedBox(height: spacing.sm),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            spacing.lg,
                            0,
                            spacing.lg,
                            spacing.lg,
                          ),
                          child: Column(
                            children: balances.balances
                                .map(
                                  (balance) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: spacing.lg,
                                    ),
                                    child: _BalanceCard(balance: balance),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
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

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.fiscalYear, required this.period});

  final num fiscalYear;
  final num period;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: spacing.lg),
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        children: [
          _HeaderRow(label: 'Fiscal Year', value: fiscalYear.toString()),
          SizedBox(height: spacing.sm),
          _HeaderRow(label: 'Period', value: period.toString()),
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

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final TreasuryBalanceEntry balance;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final closingColor = balance.closing >= 0
        ? Colors.green
        : colorScheme.error;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        onTap: () {
          final currency = balance.currencyCode;

          context.push('/treasury-wallet/$currency');
        },
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    balance.currencyCode.toUpperCase(),
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              _BalanceRow(label: 'Opening', value: balance.opening),
              SizedBox(height: spacing.xs),
              _MovementRow(debit: balance.debit, credit: balance.credit),
              SizedBox(height: spacing.xs),
              _BalanceRow(
                label: 'Closing',
                value: balance.closing,
                valueColor: closingColor,
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
    this.valueColor,
    this.strong = false,
  });

  final String label;
  final double value;
  final Color? valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Text(
          NumberFormatService.formatNumber(value),
          style:
              (strong
                      ? AppTextStyles.smallNumber(context)
                      : AppTextStyles.tinyNumber(context))
                  .copyWith(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                    color: valueColor,
                  ),
        ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.debit, required this.credit});

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
          'Movement (Dr / Cr)',
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
        Row(
          children: [
            Text(
              NumberFormatService.formatNumber(debit),
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: colorScheme.error, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: spacing.xs),
            Text(
              '/',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
            SizedBox(width: spacing.xs),
            Text(
              NumberFormatService.formatNumber(credit),
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
