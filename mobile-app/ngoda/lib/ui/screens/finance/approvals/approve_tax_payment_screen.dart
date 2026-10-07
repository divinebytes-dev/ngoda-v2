import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/tax/tax_settlement_batch.dart';
import 'package:ngoda/data_models/tax/tax_settlement_batch_data.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/tax_settlement_data_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ApproveTaxPaymentScreen extends ConsumerWidget {
  const ApproveTaxPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const statuses = ['draft'];

    final asyncData = ref.watch(taxSettlementDataProvider(statuses));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Approve Government Tax Settlement',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncData.when(
                loading: () =>
                    const AppLoader(message: 'Loading settlement data'),
                error: (error, _) => AppErrorState(
                  title: 'Approve Government Tax Settlement',
                  message: error.toString(),
                ),
                data: (data) {
                  if (data.error != null) {
                    return AppErrorState(
                      title: 'Approve Government Tax Settlement',
                      message: data.error!,
                    );
                  }

                  final settlementData = data.result;

                  if (settlementData == null) {
                    return const AppEmptyState();
                  }

                  return _Body(settlementData: settlementData);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.settlementData});

  final TaxSettlementBatchData settlementData;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with TickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.settlementData.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _Body oldWidget) {
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
      return const AppEmptyState();
    }

    return Column(
      children: [
        _CurrencyTabs(controller: _tabController, currencies: currencies),
        SizedBox(height: spacing.md),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final batch = widget.settlementData.batchByCurrencyAndStatus(
                currency,
                'draft',
              );

              if (batch == null) {
                return const AppEmptyState();
              }

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.padding,
                  0,
                  spacing.padding,
                  spacing.lg,
                ),
                child: _BatchCard(currency: currency, batch: batch),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _CurrencyTabs extends StatelessWidget {
  const _CurrencyTabs({required this.controller, required this.currencies});

  final TabController controller;
  final List<String> currencies;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.padding),
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        tabs: currencies.map((currency) {
          return Tab(
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  currency.toUpperCase(),
                  style: AppTextStyles.small(context),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BatchCard extends ConsumerWidget {
  const _BatchCard({required this.currency, required this.batch});

  final String currency;
  final TaxSettlementBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final state = ref.watch(financeTransactionProvider);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius.borderRadius),
            ),
            onTap: () {
              context.push(
                '/profile/approve-tax-settlement/entries',
                extra: SettlementItemsParams(
                  batchId: batch.id,
                  currency: currency,
                  page: 1,
                  pageSize: 50,
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(spacing.md),
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
                      Icon(
                        Icons.chevron_right,
                        size: iconSize.medium,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  _SummaryRow(
                    label: 'Total Amount',
                    value: NumberFormatService.formatAmount(
                      batch.totalAmount,
                      currency: currency,
                    ),
                    strong: true,
                  ),
                  SizedBox(height: spacing.sm),
                  _SummaryRow(label: 'Period', value: batch.period.toString()),
                  SizedBox(height: spacing.sm),
                  _SummaryRow(
                    label: 'Fiscal Year',
                    value: batch.fiscalYear.toString(),
                  ),
                  SizedBox(height: spacing.sm),
                  _SummaryRow(label: 'Status', value: batch.status),
                  SizedBox(height: spacing.md),
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
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Reject',
                    isPrimary: false,
                    isDisabled: state.isLoading,
                    onPressed: state.isLoading
                        ? null
                        : () async {
                            await _handleApproval(context, ref, 'cancel');
                          },
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppButton(
                    text: 'Approve',
                    isProcessing: state.isLoading,
                    onPressed: state.isLoading
                        ? null
                        : () async {
                            await _handleApproval(context, ref, 'approve');
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApproval(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final notifier = ref.read(financeTransactionProvider.notifier);

    try {
      final isApproval = action == 'approve';

      final title = isApproval
          ? 'Approve Government Tax Settlement'
          : 'Reject Government Tax Settlement';

      final confirmed = await _confirmApproval(context, title);

      if (confirmed != true) {
        return;
      }

      await notifier.taxPaymentBatchApproval(batchId: batch.id, action: action);

      ref.invalidate(taxSettlementDataProvider(const ['draft']));

      if (!context.mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: isApproval
            ? 'Tax Settlement Approved Successfully'
            : 'Tax Settlement Rejected Successfully',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    } finally {
      notifier.reset();
    }
  }

  Future<bool?> _confirmApproval(BuildContext context, String title) {
    return DialogService.paymentConfirmation(
      context,
      title: title,
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            batch.totalAmount,
            currency: currency,
          ),
          isBold: true,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
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
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
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
