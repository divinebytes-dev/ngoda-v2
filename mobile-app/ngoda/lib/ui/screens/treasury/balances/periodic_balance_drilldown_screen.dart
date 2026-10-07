import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gl/gl_period_balance.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_snapshot_drill.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/treasury/provider/wallet_snapshot_drilldown_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class PeriodicBalanceDrilldownScreen extends ConsumerStatefulWidget {
  const PeriodicBalanceDrilldownScreen({super.key, required this.currency});

  final String currency;

  @override
  ConsumerState<PeriodicBalanceDrilldownScreen> createState() =>
      _PeriodicBalanceDrilldownScreenState();
}

class _PeriodicBalanceDrilldownScreenState
    extends ConsumerState<PeriodicBalanceDrilldownScreen> {
  @override
  Widget build(BuildContext context) {
    final glDrilldownAsync = ref.watch(
      walletSnapshotDrilldownProvider(widget.currency),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Periodic Balance Drilldown',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: glDrilldownAsync.when(
                loading: () => const AppLoader(
                  message: 'Loading wallet balances',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(
                    title: 'Error',
                    message: error.toString(),
                  );
                },
                data: (drill) {
                  if (drill.error != null) {
                    return AppErrorState(title: 'Error', message: drill.error);
                  }

                  final result = drill.result;

                  if (result == null) {
                    return const AppErrorState(
                      title: 'Error',
                      message: 'Wallet balance details are not available',
                    );
                  }

                  return Column(
                    children: [
                      _DrillHeader(result),
                      Expanded(child: _DrillTable(result)),
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

class _DrillHeader extends StatelessWidget {
  const _DrillHeader(this.drill);

  final WalletBalanceSnapshotDrill drill;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.lg),
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drill.currencyCode.toUpperCase(),
            style: AppTextStyles.medium(
              context,
            ).copyWith(color: colorScheme.primary, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Fiscal Year',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
              Text(
                drill.fiscalYear.toString(),
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrillTable extends StatelessWidget {
  const _DrillTable(this.drill);

  final WalletBalanceSnapshotDrill drill;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.xl),
      itemCount: drill.periods.length,
      itemBuilder: (context, index) {
        final period = drill.periods[index];

        return Padding(
          padding: EdgeInsets.only(bottom: spacing.md),
          child: _PeriodCard(period),
        );
      },
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard(this.period);

  final GLPeriodBalance period;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Period ${period.period}',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          _BalanceRow(label: 'Opening', value: period.opening, strong: true),
          SizedBox(height: spacing.xs),
          _MovementRow(debit: period.debit, credit: period.credit),
          SizedBox(height: spacing.xs),
          _BalanceRow(label: 'Closing', value: period.closing, strong: true),
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
          'Dr / Cr',
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
            SizedBox(width: spacing.xs),
            Text(
              '/',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
            SizedBox(width: spacing.xs),
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
