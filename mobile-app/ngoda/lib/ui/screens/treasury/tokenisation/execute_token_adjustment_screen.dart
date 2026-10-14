import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/treasury/token_adjustment.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/string_extension.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/providers/token_adjustment_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class ExecuteTokenAdjustmentScreen extends ConsumerStatefulWidget {
  const ExecuteTokenAdjustmentScreen({super.key});

  @override
  ConsumerState<ExecuteTokenAdjustmentScreen> createState() =>
      _ExecuteTokenAdjustmentScreenState();
}

class _ExecuteTokenAdjustmentScreenState
    extends ConsumerState<ExecuteTokenAdjustmentScreen> {
  static const String _status = 'approved';

  Future<void> _refresh() async {
    ref.invalidate(treasuryDashboardProvider);
    ref.invalidate(tokenAdjustmentProvider(_status));

    await ref.read(tokenAdjustmentProvider(_status).future);
  }

  @override
  Widget build(BuildContext context) {
    final asyncAdjustment = ref.watch(tokenAdjustmentProvider(_status));

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Execute Tokens Adjustment'),
            Expanded(
              child: asyncAdjustment.when(
                loading: () => const AppLoader(
                  message: 'Loading token adjustment request',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return _RefreshableState(
                    onRefresh: _refresh,
                    child: AppErrorState(message: error.toString()),
                  );
                },
                data: (response) {
                  final error = response.error;

                  if (error != null) {
                    if (error.contains('NO_DATA')) {
                      return _RefreshableState(
                        onRefresh: _refresh,
                        child: const AppEmptyState(
                          message: 'No pending approval',
                        ),
                      );
                    }

                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: AppErrorState(message: error),
                    );
                  }

                  final adjustment = response.result;

                  if (adjustment == null) {
                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: const AppEmptyState(),
                    );
                  }

                  return TokenAdjustmentBody(
                    adjustment: adjustment,
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

class _RefreshableState extends StatelessWidget {
  const _RefreshableState({required this.child, required this.onRefresh});

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: child),
            ),
          );
        },
      ),
    );
  }
}

class TokenAdjustmentBody extends ConsumerStatefulWidget {
  const TokenAdjustmentBody({
    super.key,
    required this.adjustment,
    required this.onRefresh,
  });

  final TokenAdjustment adjustment;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<TokenAdjustmentBody> createState() =>
      _TokenAdjustmentBodyState();
}

class _TokenAdjustmentBodyState extends ConsumerState<TokenAdjustmentBody> {
  String? _blockchainCode;

  @override
  void didUpdateWidget(covariant TokenAdjustmentBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adjustment.id != widget.adjustment.id) {
      _blockchainCode = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final adjustment = widget.adjustment;
    final dashboard = ref.watch(treasuryDashboardProvider);
    final isLoading = ref.watch(treasuryTransactionProvider).isLoading;
    final balances = dashboard.asData?.value.result?.blockchainBalances;
    final codes =
        balances?.map((balance) => balance.blockchainCode).toSet().toList() ??
        <String>[];
    final selected = codes.contains(_blockchainCode) ? _blockchainCode : null;
    final ready =
        !dashboard.isLoading &&
        !dashboard.hasError &&
        dashboard.asData?.value.error == null;
    final current = adjustment.currentCoveragePercent;
    final projected = adjustment.projectedCoveragePercent;
    final isSafe = adjustment.isSafeAfterApproval;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoverageInsight(
                    current: current,
                    projected: projected,
                    isSafe: isSafe,
                  ),
                  SizedBox(height: spacing.lg),
                  _DetailsCard(adjustment),
                  SizedBox(height: spacing.lg),
                  Text(
                    'Execution Blockchain',
                    style: AppTextStyles.small(context),
                  ),
                  SizedBox(height: spacing.sm),
                  dashboard.when(
                    loading: () => const AppLoader(
                      message: 'Loading treasury blockchain balances',
                      fullScreen: false,
                    ),
                    error: (error, _) =>
                        AppErrorState(message: error.toString()),
                    data: (response) {
                      if (response.error != null) {
                        return AppErrorState(message: response.error!);
                      }
                      if (codes.isEmpty) {
                        return const AppEmptyState(
                          message: 'No treasury blockchains available',
                        );
                      }
                      String label(String code) {
                        final balance = balances!.firstWhere(
                          (item) => item.blockchainCode == code,
                        );
                        return '$code — Treasury balance: '
                            '${NumberFormatService.formatNumber(balance.balance)} tokens';
                      }

                      return AbsorbPointer(
                        absorbing: isLoading,
                        child: AppSearchDropdownField<String>(
                          selected: selected,
                          values: codes,
                          hint: 'Select blockchain',
                          displayText: label,
                          filter: (code, query) =>
                              code.toLowerCase().contains(query.toLowerCase()),
                          onSelect: (code) =>
                              setState(() => _blockchainCode = code),
                          itemBuilder: (context, code) => Padding(
                            padding: EdgeInsets.all(spacing.md),
                            child: Text(
                              label(code),
                              style: AppTextStyles.small(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: spacing.lg),
                  _StateCard(
                    title: 'Current State',
                    gold: adjustment.availableGold,
                    tokens: adjustment.totalTokens,
                    coverage: current,
                    color: Colors.blue,
                  ),
                  SizedBox(height: spacing.lg),
                  _StateCard(
                    title: 'After Adjustment',
                    gold: adjustment.projectedGold,
                    tokens: adjustment.projectedTokens,
                    coverage: projected,
                    color: isSafe ? Colors.green : context.colorScheme.error,
                  ),
                  if (!isSafe) ...[
                    SizedBox(height: spacing.lg),
                    const _WarningCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
        _StickyActions(
          adjustment: adjustment,
          blockchainCode: ready ? selected : null,
          onCompleted: widget.onRefresh,
        ),
      ],
    );
  }
}

class _CoverageInsight extends StatelessWidget {
  const _CoverageInsight({
    required this.current,
    required this.projected,
    required this.isSafe,
  });

  final double current;
  final double projected;
  final bool isSafe;

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
            'Coverage Impact',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: _CoverageMetric(
                  label: 'Before',
                  value: current,
                  color: Colors.blue,
                ),
              ),
              Icon(
                Icons.arrow_forward,
                size: context.iconSize.small,
                color: colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: _CoverageMetric(
                  label: 'After',
                  value: projected,
                  color: isSafe ? Colors.green : colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        Text(label, style: AppTextStyles.small(context)),
        SizedBox(height: spacing.xs),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: AppTextStyles.mediumNumber(
            context,
          ).copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.title,
    required this.gold,
    required this.tokens,
    required this.coverage,
    required this.color,
  });

  final String title;
  final double gold;
  final double tokens;
  final double coverage;
  final Color color;

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
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.md),
          _StateRow(label: 'Gold Reserve', value: gold),
          SizedBox(height: spacing.xs),
          _StateRow(label: 'Token Supply', value: tokens),
          SizedBox(height: spacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${coverage.toStringAsFixed(2)}%',
              style: AppTextStyles.mediumNumber(
                context,
              ).copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Flexible(
          child: Text(
            NumberFormatService.formatNumber(value),
            textAlign: TextAlign.right,
            style: AppTextStyles.smallNumber(context),
          ),
        ),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard(this.adjustment);

  final TokenAdjustment adjustment;

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
        children: [
          _DetailRow(
            label: 'Type',
            value: adjustment.adjustmentType,
            isText: true,
          ),
          SizedBox(height: spacing.sm),
          _DetailRow(
            label: 'Quantity',
            value:
                '${NumberFormatService.formatNumber(adjustment.quantity)} '
                '${adjustment.uom}',
          ),
          if (adjustment.description != null &&
              adjustment.description!.trim().isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            _DetailRow(
              label: 'Description',
              value: adjustment.description!,
              isText: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isText = false,
  });

  final String label;
  final String value;
  final bool isText;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        SizedBox(width: spacing.lg),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style:
                (isText
                        ? AppTextStyles.small(context)
                        : AppTextStyles.smallNumber(context))
                    .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            color: colorScheme.error,
            size: context.iconSize.small,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'This adjustment will result in '
              'under-collateralization (coverage < 100%).',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyActions extends ConsumerWidget {
  const _StickyActions({
    required this.adjustment,
    required this.onCompleted,
    required this.blockchainCode,
  });

  final TokenAdjustment adjustment;
  final String? blockchainCode;
  final Future<void> Function() onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final state = ref.watch(treasuryTransactionProvider);

    return Container(
      padding: EdgeInsets.all(spacing.md),
      // decoration: BoxDecoration(
      //   color: colorScheme.surface,
      //   border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      // ),
      child: AppButton(
        isProcessing: state.isLoading,
        isDisabled: state.isLoading || blockchainCode == null,
        text: 'Adjust',
        onPressed: state.isLoading || blockchainCode == null
            ? null
            : () async {
                final completed = await _submit(
                  context,
                  ref,
                  adjustment,
                  blockchainCode!,
                );

                if (!completed) {
                  return;
                }

                await onCompleted();
              },
      ),
    );
  }
}

Future<bool> _submit(
  BuildContext context,
  WidgetRef ref,
  TokenAdjustment adjustment,
  String blockchainCode,
) async {
  final notifier = ref.read(treasuryTransactionProvider.notifier);

  try {
    final confirmed = await _confirm(
      context,
      adjustment.adjustmentType,
      adjustment.quantity,
      adjustment.uom,
      blockchainCode,
    );

    if (confirmed != true) {
      return false;
    }

    await notifier.executeTokenAdjustment(
      id: adjustment.id,
      blockchainCode: blockchainCode,
    );

    if (!context.mounted) {
      return false;
    }

    DialogService.success(
      context,
      message: 'Token ${adjustment.adjustmentType.capitalize()} Successful',
    );

    ref.invalidate(treasuryDashboardProvider);

    notifier.reset();

    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }

    await DialogService.error(context, message: error.toString());

    return false;
  }
}

Future<bool?> _confirm(
  BuildContext context,
  String type,
  double quantity,
  String uom,
  String blockchainCode,
) {
  final tokenUom = quantity == 1 ? 'token' : 'tokens';

  return DialogService.paymentConfirmation(
    context,
    title: 'Confirm Token Adjustment',
    rows: [
      PaymentRow('Blockchain', blockchainCode),
      PaymentRow(
        type.capitalize(),
        '${NumberFormatService.formatNumber(quantity)} '
        '$tokenUom',
      ),
    ],
  );
}
