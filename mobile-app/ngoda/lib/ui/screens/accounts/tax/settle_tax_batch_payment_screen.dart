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
import 'package:ngoda/ui/screens/accounts/providers/accounts_transaction_provider.dart';
import 'package:ngoda/ui/screens/accounts/providers/tax_settlement_data_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class SettleTaxBatchPaymentScreen extends ConsumerWidget {
  const SettleTaxBatchPaymentScreen({super.key});

  static const _statuses = ['approved', 'partial', 'failed'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettlement = ref.watch(taxSettlementDataProvider(_statuses));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Settle Government Tax',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncSettlement.when(
                loading: () => const AppLoader(
                  message: 'Loading settlement data',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(
                    title: 'Settle Government Tax',
                    message: error.toString(),
                  );
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      title: 'Settle Government Tax',
                      message: response.error.toString(),
                    );
                  }

                  final settlementData = response.result;

                  if (settlementData == null ||
                      settlementData.batches.isEmpty) {
                    return const AppEmptyState(
                      message:
                          'No government tax payments '
                          'available for settlement',
                    );
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

  List<String> get currencies => widget.settlementData.currencyList;

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
      return const AppEmptyState(
        message:
            'No government tax payments '
            'available for settlement',
      );
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
                return const AppEmptyState(message: 'No tax settlement batch');
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

class _SettlementBatchCard extends ConsumerWidget {
  const _SettlementBatchCard({required this.currency, required this.batch});

  final String currency;
  final TaxSettlementBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final state = ref.watch(accountsTransactionProvider);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius.borderRadius),
            ),
            onTap: () {
              context.push(
                '/payments/settle-tax-payment/entries',
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
                        size: iconSize.small,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  AppValueRow(
                    label: 'Total Amount',
                    value: NumberFormatService.formatAmount(
                      batch.totalAmount,
                      currency: currency,
                    ),
                  ),
                  AppValueRow(label: 'Period', value: batch.period.toString()),
                  AppValueRow(
                    label: 'Fiscal Year',
                    value: batch.fiscalYear.toString(),
                  ),
                  AppValueRow(
                    label: 'Status',
                    value: batch.status,
                    addBottomSpacing: false,
                  ),
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
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Cancel',
                    isPrimary: false,
                    isDisabled: state.isLoading,
                    onPressed: state.isLoading
                        ? null
                        : () {
                            context.pop();
                          },
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppButton(
                    text: 'Pay',
                    isProcessing: state.isLoading,
                    onPressed: state.isLoading
                        ? null
                        : () async {
                            await _handleSettlePayment(context, ref);
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

  Future<void> _handleSettlePayment(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(accountsTransactionProvider.notifier);

    try {
      final confirmed = await _confirmSettlement(context);

      if (confirmed != true) {
        return;
      }

      await notifier.settleTaxPaymentBatch(batchId: batch.id);

      ref.invalidate(
        taxSettlementDataProvider(SettleTaxBatchPaymentScreen._statuses),
      );

      if (!context.mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Government Tax Settled Successfully',
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

  Future<bool?> _confirmSettlement(BuildContext context) {
    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Government Tax Settlement',
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
