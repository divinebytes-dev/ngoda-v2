import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/params/tax_entry_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/screens/reserve-bank/providers/periodic_tax_entries_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ReserveBankTaxEntriesScreen extends ConsumerStatefulWidget {
  const ReserveBankTaxEntriesScreen({super.key, required this.params});

  final TaxEntryParams params;

  @override
  ConsumerState<ReserveBankTaxEntriesScreen> createState() =>
      _ReserveBankTaxEntriesScreenState();
}

class _ReserveBankTaxEntriesScreenState
    extends ConsumerState<ReserveBankTaxEntriesScreen> {
  late TaxEntryParams _params = widget.params;

  @override
  void didUpdateWidget(covariant ReserveBankTaxEntriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.params != widget.params) {
      _params = widget.params;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final provider = taxPeriodicEntriesProvider(_params);
    final drilldownAsync = ref.watch(provider);
    final currency = _params.currency;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Tax Period Details',
              onClose: () => context.pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(provider);
                  await ref.read(provider.future);
                },
                child: drilldownAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading tax entries',
                    fullScreen: false,
                  ),
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(message: error.toString()),
                  ),
                  data: (response) {
                    final error = response.error;
                    if (error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: error.toString()),
                      );
                    }

                    final data = response.result;
                    if (data == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    final summary = data.summary;
                    final rate = summary.taxRate;

                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            key: ValueKey(_params),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              spacing.md,
                              spacing.sm,
                              spacing.md,
                              spacing.lg,
                            ),
                            children: [
                              _DetailsCard(
                                title:
                                    '${currency.toUpperCase()} • FY '
                                    '${_params.fiscalYear} • Period ${summary.period}',
                                lines: [
                                  'Gross amount: ${_formatAmount(summary.grossAmount, currency)}',
                                  'Tax amount: ${_formatAmount(summary.taxAmount, currency)}',
                                  'Effective tax rate: ${rate == null ? '—' : '$rate%'}',
                                ],
                              ),
                              SizedBox(height: spacing.lg),
                              Text(
                                'Tax entries (${data.totalEntries})',
                                style: AppTextStyles.medium(context),
                              ),
                              SizedBox(height: spacing.sm),
                              if (data.entries.isEmpty)
                                const SizedBox(
                                  height: 220,
                                  child: AppEmptyState(),
                                ),
                              for (final entry in data.entries) ...[
                                _DetailsCard(
                                  title: entry.documentNumber,
                                  lines: [
                                    entry.transactionType.replaceAll('_', ' '),
                                    'Gross amount: ${_formatAmount(double.parse(entry.grossAmount), currency)}',
                                    'Tax amount: ${_formatAmount(double.parse(entry.taxAmount), currency)}',
                                    'Tax rate: ${entry.taxRate == null ? '—' : '${entry.taxRate}%'}',
                                    entry.isSettled ? 'Settled' : 'Unsettled',
                                  ],
                                ),
                                SizedBox(height: spacing.sm),
                              ],
                            ],
                          ),
                        ),
                        if (data.totalEntries > 0 || data.hasPrevious)
                          AppPagination(
                            page: data.page,
                            totalPages: data.totalPages,
                            totalEntries: data.totalEntries,
                            hasPrevious: data.hasPrevious,
                            hasNext: data.hasNext,
                            pageSize: data.pageSize,
                            onPrevious: () {
                              if (data.hasPrevious) {
                                setState(
                                  () => _params = _params.copyWith(
                                    page: data.page - 1,
                                  ),
                                );
                              }
                            },
                            onNext: () {
                              if (data.hasNext) {
                                setState(
                                  () => _params = _params.copyWith(
                                    page: data.page + 1,
                                  ),
                                );
                              }
                            },
                            onPageSizeChanged: (pageSize) {
                              if (pageSize != _params.pageSize) {
                                setState(
                                  () => _params = _params.copyWith(
                                    page: 1,
                                    pageSize: pageSize,
                                  ),
                                );
                              }
                            },
                          ),
                      ],
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
}

String _formatAmount(double amount, String currency) =>
    NumberFormatService.formatAmount(amount, currency: currency);

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            for (final line in lines) ...[
              SizedBox(height: spacing.xs),
              Text(line, style: AppTextStyles.small(context)),
            ],
          ],
        ),
      ),
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
