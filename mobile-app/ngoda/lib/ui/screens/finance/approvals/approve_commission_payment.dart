import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/commission/settlement_batch.dart';
import 'package:ngoda/data_models/commission/settlement_batch_data.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/commission_settlement_batch_data_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ApproveCommissionPaymentScreen extends ConsumerStatefulWidget {
  const ApproveCommissionPaymentScreen({super.key});

  @override
  ConsumerState<ApproveCommissionPaymentScreen> createState() =>
      _ApproveCommissionPaymentScreenState();
}

class _ApproveCommissionPaymentScreenState
    extends ConsumerState<ApproveCommissionPaymentScreen> {
  static const _statuses = ['draft'];

  bool _isSubmitting = false;
  String? _processingBatchId;
  String? _processingAction;

  @override
  Widget build(BuildContext context) {
    final transactionState = ref.watch(financeTransactionProvider);
    final asyncData = ref.watch(commissionSettlementDataProvider(_statuses));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Approve Commission Settlement',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: asyncData.when(
                loading: () =>
                    const AppLoader(message: 'Loading settlement data'),
                error: (error, _) => AppErrorState(
                  title: 'Approve Commission Settlement',
                  message: error.toString(),
                ),
                data: (data) {
                  if (data.error != null) {
                    return AppErrorState(
                      title: 'Approve Commission Settlement',
                      message: data.error!,
                    );
                  }

                  final settlementData = data.result;

                  if (settlementData == null ||
                      settlementData.batches.isEmpty) {
                    return const AppEmptyState();
                  }

                  return _Body(
                    settlementData: settlementData,
                    actionsDisabled:
                        _isSubmitting || transactionState.isLoading,
                    processingBatchId: _processingBatchId,
                    processingAction: _processingAction,
                    onAction: _handleApproval,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleApproval(
    String currency,
    SettlementBatch batch,
    String action,
  ) async {
    if (_isSubmitting || ref.read(financeTransactionProvider).isLoading) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final isApproval = action == 'approve';

      final title = isApproval
          ? 'Approve Agent Commission Settlement'
          : 'Reject Agent Commission Settlement';

      final confirmed = await _confirmApproval(title, currency, batch);

      if (!mounted ||
          confirmed != true ||
          ref.read(financeTransactionProvider).isLoading) {
        return;
      }

      final notifier = ref.read(financeTransactionProvider.notifier);
      setState(() {
        _processingBatchId = batch.id;
        _processingAction = action;
      });

      try {
        await notifier.commissionPaymentBatchApproval(
          batchId: batch.id,
          action: action,
        );
      } finally {
        notifier.reset();
        if (mounted) {
          setState(() {
            _processingBatchId = null;
            _processingAction = null;
          });
        }
      }

      if (!mounted) {
        return;
      }

      ref.invalidate(commissionSettlementDataProvider(_statuses));

      await DialogService.success(
        context,
        message: isApproval
            ? 'Settlement Approved Successfully'
            : 'Settlement Rejected Successfully',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool?> _confirmApproval(
    String title,
    String currency,
    SettlementBatch batch,
  ) {
    return DialogService.paymentConfirmation(
      context,
      title: title,
      rows: [
        PaymentRow('Agents', batch.totalAgents.toString()),
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

class _Body extends StatefulWidget {
  const _Body({
    required this.settlementData,
    required this.actionsDisabled,
    required this.processingBatchId,
    required this.processingAction,
    required this.onAction,
  });

  final SettlementBatchData settlementData;
  final bool actionsDisabled;
  final String? processingBatchId;
  final String? processingAction;
  final Future<void> Function(String, SettlementBatch, String) onAction;

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
              final batches = widget.settlementData.byCurrency(currency);

              if (batches.isEmpty) {
                return const AppEmptyState();
              }

              return ListView.separated(
                key: PageStorageKey(currency),
                padding: EdgeInsets.fromLTRB(
                  spacing.padding,
                  0,
                  spacing.padding,
                  spacing.lg,
                ),
                itemCount: batches.length,
                separatorBuilder: (context, index) =>
                    SizedBox(height: spacing.md),
                itemBuilder: (context, index) {
                  final batch = batches[index];

                  return _BatchCard(
                    key: ValueKey(batch.id),
                    currency: currency,
                    batch: batch,
                    actionsDisabled: widget.actionsDisabled,
                    processingAction: widget.processingBatchId == batch.id
                        ? widget.processingAction
                        : null,
                    onAction: (action) =>
                        widget.onAction(currency, batch, action),
                  );
                },
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

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    super.key,
    required this.currency,
    required this.batch,
    required this.actionsDisabled,
    required this.processingAction,
    required this.onAction,
  });

  final String currency;
  final SettlementBatch batch;
  final bool actionsDisabled;
  final String? processingAction;
  final Future<void> Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

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
                '/approve-commission-settlement/entries',
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
                          'Commission Settlement',
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
                  _SummaryRow(label: 'Agents', value: '${batch.totalAgents}'),
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
                    isDisabled: actionsDisabled,
                    isProcessing: processingAction == 'cancel',
                    onPressed: actionsDisabled
                        ? null
                        : () async {
                            await onAction('cancel');
                          },
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: AppButton(
                    text: 'Approve',
                    isDisabled: actionsDisabled,
                    isProcessing: processingAction == 'approve',
                    onPressed: actionsDisabled
                        ? null
                        : () async {
                            await onAction('approve');
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

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/data_models/commission/settlement_batch.dart';
// import 'package:ngoda/data_models/commission/settlement_batch_data.dart';
// import 'package:ngoda/data_models/params/settlement_items_params.dart';
// import 'package:ngoda/data_models/payment/payment_row.dart';
// import 'package:ngoda/services/dialog_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/screens/finance/providers/commission_settlement_batch_data_provider.dart';
// import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_button.dart';
// import 'package:ngoda/ui/widgets/app_empty_state.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class ApproveCommissionPaymentScreen extends ConsumerWidget {
//   const ApproveCommissionPaymentScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     const statuses = ['draft'];

//     final asyncData = ref.watch(commissionSettlementDataProvider(statuses));

//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             ViewHeader(
//               title: 'Approve Commission Settlement',
//               onClose: () => context.pop(),
//             ),
//             Expanded(
//               child: asyncData.when(
//                 loading: () =>
//                     const AppLoader(message: 'Loading settlement data'),
//                 error: (error, _) => AppErrorState(
//                   title: 'Approve Commission Settlement',
//                   message: error.toString(),
//                 ),
//                 data: (data) {
//                   if (data.error != null) {
//                     return AppErrorState(
//                       title: 'Approve Commission Settlement',
//                       message: data.error!,
//                     );
//                   }

//                   final settlementData = data.result;

//                   if (settlementData == null) {
//                     return const AppEmptyState();
//                   }

//                   return _Body(settlementData: settlementData);
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _Body extends StatefulWidget {
//   const _Body({required this.settlementData});

//   final SettlementBatchData settlementData;

//   @override
//   State<_Body> createState() => _BodyState();
// }

// class _BodyState extends State<_Body> with TickerProviderStateMixin {
//   late TabController _tabController;

//   List<String> get currencies => widget.settlementData.sortedCurrencyList;

//   @override
//   void initState() {
//     super.initState();

//     _tabController = TabController(length: currencies.length, vsync: this);
//   }

//   @override
//   void didUpdateWidget(covariant _Body oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     if (oldWidget.settlementData.currencyList.length !=
//         widget.settlementData.currencyList.length) {
//       _tabController.dispose();

//       _tabController = TabController(length: currencies.length, vsync: this);
//     }
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();

//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     if (currencies.isEmpty) {
//       return const AppEmptyState();
//     }

//     return Column(
//       children: [
//         _CurrencyTabs(controller: _tabController, currencies: currencies),
//         SizedBox(height: spacing.md),
//         Expanded(
//           child: TabBarView(
//             controller: _tabController,
//             children: currencies.map((currency) {
//               final batch = widget.settlementData.batchByCurrencyAndStatus(
//                 currency,
//                 'draft',
//               );

//               if (batch == null) {
//                 return const AppEmptyState();
//               }

//               return SingleChildScrollView(
//                 padding: EdgeInsets.fromLTRB(
//                   spacing.padding,
//                   0,
//                   spacing.padding,
//                   spacing.lg,
//                 ),
//                 child: _BatchCard(currency: currency, batch: batch),
//               );
//             }).toList(),
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _CurrencyTabs extends StatelessWidget {
//   const _CurrencyTabs({required this.controller, required this.currencies});

//   final TabController controller;
//   final List<String> currencies;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Container(
//       margin: EdgeInsets.symmetric(horizontal: spacing.padding),
//       padding: EdgeInsets.all(spacing.xs),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainerHighest,
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//       ),
//       child: TabBar(
//         controller: controller,
//         dividerColor: Colors.transparent,
//         indicator: BoxDecoration(
//           color: colorScheme.primary,
//           borderRadius: BorderRadius.circular(radius.borderRadius),
//         ),
//         labelColor: colorScheme.onPrimary,
//         unselectedLabelColor: colorScheme.onSurfaceVariant,
//         tabs: currencies.map((currency) {
//           return Tab(
//             child: SizedBox(
//               width: double.infinity,
//               child: Center(
//                 child: Text(
//                   currency.toUpperCase(),
//                   style: AppTextStyles.small(context),
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

// class _BatchCard extends ConsumerWidget {
//   const _BatchCard({required this.currency, required this.batch});

//   final String currency;
//   final SettlementBatch batch;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     final state = ref.watch(financeTransactionProvider);

//     return Container(
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainer,
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//       ),
//       child: Column(
//         children: [
//           InkWell(
//             borderRadius: BorderRadius.vertical(
//               top: Radius.circular(radius.borderRadius),
//             ),
//             onTap: () {
//               context.push(
//                 '/approve-commission-settlement/entries',
//                 extra: SettlementItemsParams(
//                   batchId: batch.id,
//                   currency: currency,
//                   page: 1,
//                   pageSize: 50,
//                 ),
//               );
//             },
//             child: Padding(
//               padding: EdgeInsets.all(spacing.md),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Text(
//                           'Commission Settlement',
//                           style: AppTextStyles.medium(
//                             context,
//                           ).copyWith(fontWeight: FontWeight.w700),
//                         ),
//                       ),
//                       Icon(
//                         Icons.chevron_right,
//                         size: iconSize.medium,
//                         color: colorScheme.primary,
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: spacing.md),
//                   _SummaryRow(
//                     label: 'Total Amount',
//                     value: NumberFormatService.formatAmount(
//                       batch.totalAmount,
//                       currency: currency,
//                     ),
//                     strong: true,
//                   ),
//                   SizedBox(height: spacing.sm),
//                   _SummaryRow(label: 'Agents', value: '${batch.totalAgents}'),
//                   SizedBox(height: spacing.sm),
//                   _SummaryRow(label: 'Period', value: batch.period.toString()),
//                   SizedBox(height: spacing.sm),
//                   _SummaryRow(
//                     label: 'Fiscal Year',
//                     value: batch.fiscalYear.toString(),
//                   ),
//                   SizedBox(height: spacing.sm),
//                   _SummaryRow(label: 'Status', value: batch.status),
//                   SizedBox(height: spacing.md),
//                   Row(
//                     children: [
//                       Icon(
//                         Icons.visibility_outlined,
//                         size: iconSize.small,
//                         color: colorScheme.onSurfaceVariant,
//                       ),
//                       SizedBox(width: spacing.xs),
//                       Text(
//                         'View settlement items',
//                         style: AppTextStyles.tiny(
//                           context,
//                         ).copyWith(color: colorScheme.onSurfaceVariant),
//                       ),
//                       const Spacer(),
//                       Text(
//                         currency.toUpperCase(),
//                         style: AppTextStyles.tiny(
//                           context,
//                         ).copyWith(fontWeight: FontWeight.w700),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           const Divider(height: 1),
//           Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: AppButton(
//                     text: 'Reject',
//                     isPrimary: false,
//                     isDisabled: state.isLoading,
//                     onPressed: state.isLoading
//                         ? null
//                         : () async {
//                             await _handleApproval(context, ref, 'cancel');
//                           },
//                   ),
//                 ),
//                 SizedBox(width: spacing.sm),
//                 Expanded(
//                   child: AppButton(
//                     text: 'Approve',
//                     isProcessing: state.isLoading,
//                     onPressed: state.isLoading
//                         ? null
//                         : () async {
//                             await _handleApproval(context, ref, 'approve');
//                           },
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _handleApproval(
//     BuildContext context,
//     WidgetRef ref,
//     String action,
//   ) async {
//     final notifier = ref.read(financeTransactionProvider.notifier);

//     try {
//       final isApproval = action == 'approve';

//       final title = isApproval
//           ? 'Approve Agent Commission Settlement'
//           : 'Reject Agent Commission Settlement';

//       final confirmed = await _confirmApproval(context, title);

//       if (confirmed != true) {
//         return;
//       }

//       await notifier.commissionPaymentBatchApproval(
//         batchId: batch.id,
//         action: action,
//       );

//       ref.invalidate(commissionSettlementDataProvider(const ['draft']));

//       if (!context.mounted) {
//         return;
//       }

//       await DialogService.success(
//         context,
//         message: isApproval
//             ? 'Settlement Approved Successfully'
//             : 'Settlement Rejected Successfully',
//       );
//     } catch (error) {
//       if (!context.mounted) {
//         return;
//       }

//       await DialogService.error(context, message: error.toString());
//     } finally {
//       notifier.reset();
//     }
//   }

//   Future<bool?> _confirmApproval(BuildContext context, String title) {
//     return DialogService.paymentConfirmation(
//       context,
//       title: title,
//       rows: [
//         PaymentRow('Agents', batch.totalAgents.toString()),
//         PaymentRow(
//           'Amount',
//           NumberFormatService.formatAmount(
//             batch.totalAmount,
//             currency: currency,
//           ),
//           isBold: true,
//         ),
//       ],
//     );
//   }
// }

// class _SummaryRow extends StatelessWidget {
//   const _SummaryRow({
//     required this.label,
//     required this.value,
//     this.strong = false,
//   });

//   final String label;
//   final String value;
//   final bool strong;

//   @override
//   Widget build(BuildContext context) {
//     final colorScheme = context.colorScheme;

//     return Row(
//       children: [
//         Expanded(
//           child: Text(
//             label,
//             style: AppTextStyles.tiny(context).copyWith(
//               fontWeight: FontWeight.w700,
//               color: colorScheme.onSurfaceVariant,
//             ),
//           ),
//         ),
//         Text(
//           value,
//           style: strong
//               ? AppTextStyles.mediumNumber(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700)
//               : AppTextStyles.smallNumber(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//         ),
//       ],
//     );
//   }
// }
