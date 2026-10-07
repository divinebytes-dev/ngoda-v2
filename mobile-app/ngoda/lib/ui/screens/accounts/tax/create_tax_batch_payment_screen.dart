import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/commission/commission_settlement_date.dart';
import 'package:ngoda/data_models/commission/last_commission_settlement_dates.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/notifier/accounts_transaction_notifier.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_transaction_provider.dart';
import 'package:ngoda/ui/screens/accounts/state/accounts_transaction_state.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/currency_tabs.dart';
import 'package:ngoda/ui/widgets/date_time_input.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CreateTaxBatchPaymentScreen extends ConsumerWidget {
  const CreateTaxBatchPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(accountsDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Create Government Tax Payment Batch',
              onClose: () {
                ref.read(accountsTransactionProvider.notifier).reset();

                context.pop();
              },
            ),
            Expanded(
              child: dashboardAsync.when(
                loading: () => const AppLoader(
                  message: 'Loading government tax settlement dates',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return Center(child: Text(error.toString()));
                },
                data: (response) {
                  if (response.error != null) {
                    return Center(child: Text(response.error!));
                  }

                  final settlementDates =
                      response.result?.lastGovernmentTaxSettlementDates;

                  if (settlementDates == null) {
                    return const AppEmptyState(
                      message: 'No government tax settlement dates available',
                    );
                  }

                  return _TransactionBody(settlementDates: settlementDates);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionBody extends StatefulWidget {
  const _TransactionBody({required this.settlementDates});

  final LastCommissionSettlementDates settlementDates;

  @override
  State<_TransactionBody> createState() => _TransactionBodyState();
}

class _TransactionBodyState extends State<_TransactionBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get currencies => widget.settlementDates.sortedCurrencyList;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: currencies.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _TransactionBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.settlementDates.sortedCurrencyList.length !=
        widget.settlementDates.sortedCurrencyList.length) {
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
      return const AppEmptyState(message: 'No settlement currencies available');
    }

    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);

    return Column(
      children: [
        CurrencyTabs(controller: _tabController, currencies: currencies),
        SizedBox(height: spacing.sm),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: currencies.map((currency) {
              final data = widget.settlementDates.rows
                  .where((item) => item.currencyCode == currency)
                  .toList();

              final settlement = data.isNotEmpty ? data.first : null;

              final startDate = settlement?.nextStartDate ?? yearStart;

              final paymentUnderway =
                  settlement?.endDate != null &&
                  settlement?.status != null &&
                  settlement?.paymentUnderway == true;

              final lockedEndDate = paymentUnderway
                  ? settlement!.endDate
                  : null;

              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: spacing.lg),
                child: Column(
                  children: [
                    _SectionCard(currency: currency, items: data),
                    SizedBox(height: spacing.md),
                    _InputSection(
                      currency: currency,
                      startDate: startDate,
                      lockedEndDate: lockedEndDate,
                      paymentUnderway: paymentUnderway,
                      paymentStatus: settlement?.status,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.currency, required this.items});

  final String currency;
  final List<CommissionSettlementDate> items;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Text(
          'No settlement history',
          style: AppTextStyles.small(
            context,
          ).copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      children: items.map((item) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.xs),
          child: _ItemCard(currency: currency, item: item),
        );
      }).toList(),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.currency, required this.item});

  final String currency;
  final CommissionSettlementDate item;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: spacing.sm),
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _ValueRow(
            label: 'Start Date',
            value: DateFormatService.formatDateOnly(item.startDate),
          ),
          SizedBox(height: spacing.sm),
          _ValueRow(
            label: 'End Date',
            value: DateFormatService.formatDateOnly(item.endDate),
          ),
          if (item.nextStartDate != null) ...[
            SizedBox(height: spacing.sm),
            _ValueRow(
              label: 'Next Start Date',
              value: DateFormatService.formatDateOnly(item.nextStartDate!),
            ),
          ],
          SizedBox(height: spacing.sm),
          _ValueRow(
            label: 'Payment Status',
            value: item.status == null
                ? 'No Payment'
                : item.status == 'settled'
                ? 'Completed'
                : 'Pending',
          ),
        ],
      ),
    );
  }
}

class _InputSection extends ConsumerStatefulWidget {
  const _InputSection({
    required this.currency,
    required this.startDate,
    required this.paymentUnderway,
    this.lockedEndDate,
    this.paymentStatus,
  });

  final String currency;
  final DateTime startDate;
  final DateTime? lockedEndDate;
  final bool paymentUnderway;
  final String? paymentStatus;

  @override
  ConsumerState<_InputSection> createState() => _InputSectionState();
}

class _InputSectionState extends ConsumerState<_InputSection> {
  final endDateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _syncDates();
    });
  }

  @override
  void didUpdateWidget(covariant _InputSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.startDate != widget.startDate ||
        oldWidget.lockedEndDate != widget.lockedEndDate ||
        oldWidget.paymentUnderway != widget.paymentUnderway ||
        oldWidget.currency != widget.currency) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _syncDates();
      });
    }
  }

  void _syncDates() {
    final notifier = ref.read(accountsTransactionProvider.notifier);

    notifier.updateStartDate(widget.startDate);

    if (widget.paymentUnderway && widget.lockedEndDate != null) {
      endDateCtrl.text = DateFormatService.formatDateOnly(
        widget.lockedEndDate!,
      );

      notifier.updateEndDate(widget.lockedEndDate!);

      return;
    }

    endDateCtrl.clear();
  }

  @override
  void dispose() {
    endDateCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final notifier = ref.read(accountsTransactionProvider.notifier);

    final state = ref.watch(accountsTransactionProvider);

    final canCreatePayment =
        !widget.paymentUnderway &&
        !state.isLoading &&
        state.isValid &&
        state.endDate != null;

    return Container(
      margin: EdgeInsets.all(spacing.sm),
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _LockedDateField(label: 'Start Date', date: widget.startDate),
          SizedBox(height: spacing.sm),
          if (widget.paymentUnderway && widget.lockedEndDate != null)
            _LockedDateField(label: 'End Date', date: widget.lockedEndDate!)
          else
            DateInputField(
              controller: endDateCtrl,
              placeholder: 'End Date',
              initialDate: widget.startDate,
              firstDate: widget.startDate,
              lastDate: DateTime.now(),
              onDateSelected: (date) {
                notifier.updateStartDate(widget.startDate);

                notifier.updateEndDate(date);
              },
            ),
          if (widget.paymentUnderway) ...[
            SizedBox(height: spacing.sm),
            _ValueRow(
              label: 'Payment Status',
              value: widget.paymentStatus == 'settled'
                  ? 'Completed'
                  : 'Pending',
            ),
          ],
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  isPrimary: false,
                  isDisabled: state.isLoading,
                  onPressed: state.isLoading
                      ? null
                      : () {
                          endDateCtrl.clear();

                          notifier.reset();

                          context.pop();
                        },
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppButton(
                  text: widget.paymentUnderway
                      ? 'Payment Underway'
                      : 'Create Payment',
                  isProcessing: state.isLoading,
                  onPressed: !canCreatePayment
                      ? null
                      : () async {
                          await _handleCreatePayment(
                            notifier,
                            state,
                            widget.currency,
                          );
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleCreatePayment(
    AccountsTransactionNotifier notifier,
    AccountsTransactionState state,
    String currency,
  ) async {
    try {
      if (widget.paymentUnderway) {
        throw Exception(
          'A payment is already underway '
          'for this settlement.',
        );
      }

      final startDate = widget.startDate;
      final endDate = state.endDate;

      if (endDate == null) {
        throw Exception('Please select an end date.');
      }

      if (endDate.isBefore(startDate)) {
        throw Exception(
          'End date cannot be before '
          'the start date.',
        );
      }

      final confirmed = await _confirm(context, startDate, endDate);

      if (confirmed != true) {
        return;
      }

      await notifier.createTaxPaymentBatch(
        startDate: startDate,
        endDate: endDate,
        currency: currency,
      );

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message:
            'Government Tax Batch Payment '
            'Created Successfully',
      );

      endDateCtrl.clear();

      ref.invalidate(accountsDashboardProvider);

      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirm(
    BuildContext context,
    DateTime startDate,
    DateTime endDate,
  ) {
    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Payment Batch',
      rows: [
        PaymentRow(
          'Start Date',
          DateFormatService.formatDisplayDate(startDate),
        ),
        PaymentRow('End Date', DateFormatService.formatDisplayDate(endDate)),
      ],
    );
  }
}

class _LockedDateField extends StatelessWidget {
  const _LockedDateField({required this.label, required this.date});

  final String label;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final value = DateFormatService.formatDisplayDate(date);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: iconSize.small,
            color: colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
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
                  value,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
