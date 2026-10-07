import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/accounts/finance_document.dart';
import 'package:ngoda/data_models/accounts/journal_line.dart';
import 'package:ngoda/data_models/accounts/wallet_line.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_document_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/recent_transactions_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FinanceDocumentScreen extends ConsumerWidget {
  final String documentNumber;

  const FinanceDocumentScreen({super.key, required this.documentNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDoc = ref.watch(financeDocumentProvider(documentNumber));

    final user = getCurrentUser();
    final role = user.role!;

    final state = ref.watch(financeTransactionProvider);

    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: spacing.md),
            ViewHeader(
              title: 'Financial Document',
              onClose: () {
                ref.invalidate(financeDocumentProvider(documentNumber));

                context.pop();
              },
            ),
            Expanded(
              child: asyncDoc.when(
                loading: () => const AppLoader(
                  message: 'Loading financial document',
                  fullScreen: false,
                ),
                error: (error, stackTrace) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(message: response.error);
                  }

                  final document = response.result;

                  if (document == null) {
                    return const AppErrorState(
                      message: 'Financial document not found',
                    );
                  }

                  final canReverse =
                      document.reversalDocumentNumber == null &&
                      !document.transactionType.toLowerCase().contains(
                        'reversal',
                      );

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(spacing.padding),
                    child: Column(
                      children: [
                        SizedBox(height: spacing.sm),
                        Text(
                          '${formatTxType(document.transactionType)} Document',
                          style: AppTextStyles.small(context).copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: spacing.sm),
                        const _SectionTitle('Journal Entries'),
                        SizedBox(height: spacing.md),
                        _LedgerHeader(),
                        _JournalTable(lines: document.journal),
                        _TotalsCard(document: document),
                        _StatusCard(doc: document),
                        SizedBox(height: spacing.md),
                        const _SectionTitle('Wallet Entries'),
                        _WalletSection(document.wallet),
                        SizedBox(height: spacing.md),
                        if (role == 'finance' && canReverse)
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: spacing.buttonWidth,
                              child: AppButton(
                                isPrimary: true,
                                text: 'Reverse',
                                isProcessing: state.isLoading,
                                onPressed: state.isLoading
                                    ? null
                                    : () async {
                                        await _handleReversal(
                                          document.documentNumber,
                                          document.transactionType,
                                          context,
                                          ref,
                                        );
                                      },
                              ),
                            ),
                          ),
                        SizedBox(height: spacing.md),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleReversal(
    String docNo,
    String transactionType,
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final confirmed = await _confirmReversal(context);

      if (confirmed != true) {
        return;
      }

      if (!context.mounted) {
        return;
      }

      final notifier = ref.read(financeTransactionProvider.notifier);

      await notifier.reverseDocument(
        docNo: docNo,
        transactionType: transactionType,
      );

      ref.invalidate(financeDashboardProvider);

      ref.invalidate(recentTransactionsProvider);

      ref.invalidate(financeDocumentProvider(documentNumber));

      if (!context.mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Document reversal successful',
      );

      ref.read(financeTransactionProvider.notifier).reset();
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmReversal(BuildContext context) {
    return DialogService.confirm(
      context,
      title: 'Confirm Reversal',
      message: 'Reverse Document',
      type: DialogType.question,
    );
  }
}

class _LedgerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.padding,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('GL Account', style: AppTextStyles.small(context)),
          ),
          const _ColumnHeader(label: 'Debit'),
          SizedBox(width: spacing.md),
          const _ColumnHeader(label: 'Credit'),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String label;

  const _ColumnHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: AppTextStyles.small(context),
      ),
    );
  }
}

class _JournalTable extends StatelessWidget {
  final List<JournalLine> lines;

  const _JournalTable({required this.lines});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.symmetric(vertical: spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: lines.map((line) {
          return _LedgerRow(line: line);
        }).toList(),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final JournalLine line;

  const _LedgerRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.padding,
        vertical: spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.glAccountName, style: AppTextStyles.tiny(context)),
                Text(
                  line.glAccountCode,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _AmountCell(value: line.debit, currency: line.currencyCode),
          SizedBox(width: spacing.md),
          _AmountCell(value: line.credit, currency: line.currencyCode),
        ],
      ),
    );
  }
}

class _AmountCell extends StatelessWidget {
  final double value;
  final String currency;

  const _AmountCell({required this.value, required this.currency});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value > 0
              ? NumberFormatService.formatAmount(value, currency: currency)
              : '',
          textAlign: TextAlign.right,
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final FinanceDocument document;

  const _TotalsCard({required this.document});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Totals',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _AmountCell(value: document.totalDebit, currency: document.currency),
          SizedBox(width: spacing.md),
          _AmountCell(value: document.totalCredit, currency: document.currency),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final FinanceDocument doc;

  const _StatusCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = doc.balanced
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            doc.balanced ? 'Balanced' : 'Not Balanced',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          SizedBox(width: spacing.sm),
          Icon(
            doc.balanced ? Icons.check_circle : Icons.error_outline,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: AppTextStyles.small(
          context,
        ).copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  final List<WalletLine> lines;

  const _WalletSection(this.lines);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: lines.map((line) {
        return _WalletLineItem(
          title: line.walletOwner,
          subtitle: line.walletId,
          debit: line.debit,
          credit: line.credit,
          currency: line.currencyCode,
        );
      }).toList(),
    );
  }
}

class _WalletLineItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final double debit;
  final double credit;
  final String currency;

  const _WalletLineItem({
    required this.title,
    required this.subtitle,
    required this.debit,
    required this.credit,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  subtitle,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  debit > 0
                      ? NumberFormatService.formatAmount(
                          debit,
                          currency: currency,
                        )
                      : '',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.smallNumber(
                    context,
                  ).copyWith(color: colorScheme.error),
                ),
              ),
              SizedBox(width: spacing.md),
              SizedBox(
                width: 90,
                child: Text(
                  credit > 0
                      ? NumberFormatService.formatAmount(
                          credit,
                          currency: currency,
                        )
                      : '',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.smallNumber(
                    context,
                  ).copyWith(color: const Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
