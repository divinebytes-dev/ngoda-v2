import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/liquidation/liquidated_loans_today.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/liquidated_loans_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LiquidatedLoansScreen extends ConsumerStatefulWidget {
  final LoanLiquidationParams params;

  const LiquidatedLoansScreen({super.key, required this.params});

  @override
  ConsumerState<LiquidatedLoansScreen> createState() =>
      _LiquidatedLoansScreenState();
}

class _LiquidatedLoansScreenState extends ConsumerState<LiquidatedLoansScreen> {
  late int currentPage;
  late int pageSize;
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();

    currentPage = widget.params.page;
    pageSize = widget.params.pageSize;

    selectedDate = DateTime.tryParse(widget.params.startDate) ?? DateTime.now();
  }

  LoanLiquidationParams get currentParams {
    return LoanLiquidationParams.fromDateTime(
      startDate: selectedDate,
      page: currentPage,
      pageSize: pageSize,
    );
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate == null) {
      return;
    }

    final isSameDate =
        pickedDate.year == selectedDate.year &&
        pickedDate.month == selectedDate.month &&
        pickedDate.day == selectedDate.day;

    if (isSameDate) {
      return;
    }

    setState(() {
      selectedDate = pickedDate;
      currentPage = 1;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(liquidatedLoansProvider(currentParams));

    await ref.read(liquidatedLoansProvider(currentParams).future);
  }

  void _previousPage() {
    if (currentPage <= 1) {
      return;
    }

    setState(() {
      currentPage--;
    });
  }

  void _nextPage() {
    setState(() {
      currentPage++;
    });
  }

  void _changePageSize(int newPageSize) {
    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final drilldownAsync = ref.watch(liquidatedLoansProvider(currentParams));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Liquidated Loans',
              onClose: () {
                ref.invalidate(liquidatedLoansProvider(currentParams));

                context.pop();
              },
            ),
            _LiquidationDateSelector(date: selectedDate, onTap: _selectDate),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: drilldownAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading liquidated loans',
                    fullScreen: false,
                  ),
                  error: (error, _) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final drilldown = response.result;

                    if (drilldown == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _LiquidatedLoansContent(
                      drilldown: drilldown,
                      pageSize: pageSize,
                      onPrevious: _previousPage,
                      onNext: _nextPage,
                      onPageSizeChanged: _changePageSize,
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

class _LiquidationDateSelector extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _LiquidationDateSelector({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.padding,
        spacing.xs,
        spacing.padding,
        spacing.sm,
      ),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius.sm),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.padding,
              vertical: spacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: iconSize.small),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liquidation Date',
                        style: AppTextStyles.tiny(context).copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(date),
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: iconSize.small,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidatedLoansContent extends StatelessWidget {
  final LiquidatedLoansToday drilldown;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onPageSizeChanged;

  const _LiquidatedLoansContent({
    required this.drilldown,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              0,
              spacing.padding,
              spacing.lg,
            ),
            children: [
              _LoanSummaryCard(drilldown: drilldown),
              SizedBox(height: spacing.lg),
              _SectionHeader(
                title: 'Liquidated Loans',
                trailing: drilldown.pagination.totalEntries.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (drilldown.rows.isEmpty)
                const AppEmptyState()
              else
                ...drilldown.rows.map(
                  (loan) => Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _LoanItemCard(loan: loan),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              spacing.sm,
              spacing.padding,
              spacing.sm,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: AppPagination(
              page: drilldown.pagination.page,
              totalPages: drilldown.pagination.totalPages,
              totalEntries: drilldown.pagination.totalEntries,
              hasPrevious: drilldown.pagination.hasPrevious,
              hasNext: drilldown.pagination.hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
              entryLabel: 'loans',
              pageSize: pageSize,
              onPageSizeChanged: onPageSizeChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoanSummaryCard extends StatelessWidget {
  final LiquidatedLoansToday drilldown;

  const _LoanSummaryCard({required this.drilldown});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final totalPrincipal = drilldown.rows.fold<double>(
      0,
      (total, loan) => total + loan.principalLiquidated,
    );

    final totalInterest = drilldown.rows.fold<double>(
      0,
      (total, loan) => total + loan.interestLiquidated,
    );

    final totalLiquidated = drilldown.rows.fold<double>(
      0,
      (total, loan) => total + loan.totalLiquidated,
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Liquidation Summary',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.lg),
          _SummaryRow(
            label: 'Total Loans',
            value: drilldown.pagination.totalEntries.toString(),
          ),
          SizedBox(height: spacing.sm),
          _SummaryRow(
            label: 'Loans on this page',
            value: drilldown.rows.length.toString(),
          ),
          SizedBox(height: spacing.lg),
          Divider(height: 1, color: colorScheme.outlineVariant),
          SizedBox(height: spacing.lg),
          _SummaryRow(
            label: 'Principal Liquidated',
            value: NumberFormatService.formatAmount(
              totalPrincipal,
              currency: 'usd',
            ),
          ),
          SizedBox(height: spacing.sm),
          _SummaryRow(
            label: 'Interest Liquidated',
            value: NumberFormatService.formatAmount(
              totalInterest,
              currency: 'usd',
            ),
          ),
          SizedBox(height: spacing.sm),
          _SummaryRow(
            label: 'Total Liquidated',
            value: NumberFormatService.formatAmount(
              totalLiquidated,
              currency: 'usd',
            ),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _LoanItemCard extends StatelessWidget {
  final LiquidatedLoanRow loan;

  const _LoanItemCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final borrowerName = _resolveBorrowerName(loan);

    final borrowerContact = _resolveBorrowerContact(loan);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      borrowerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (borrowerContact != null) ...[
                      SizedBox(height: spacing.xs),
                      Text(
                        borrowerContact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              _LoanStatusBadge(status: loan.loanStatus),
            ],
          ),
          SizedBox(height: spacing.padding),
          Divider(height: 1, color: colorScheme.outlineVariant),
          SizedBox(height: spacing.padding),
          _DetailRow(
            label: 'Document Number',
            value: loan.documentNumber.isEmpty
                ? 'Not available'
                : loan.documentNumber,
          ),
          SizedBox(height: spacing.sm),
          _DetailRow(
            label: 'Liquidated At',
            value: _formatDateTime(context, loan.liquidatedAt),
          ),
          SizedBox(height: spacing.padding),
          _AmountRow(
            label: 'Principal Liquidated',
            value: loan.principalLiquidated,
          ),
          SizedBox(height: spacing.sm),
          _AmountRow(
            label: 'Interest Liquidated',
            value: loan.interestLiquidated,
          ),
          SizedBox(height: spacing.sm),
          Divider(height: 1, color: colorScheme.outlineVariant),
          SizedBox(height: spacing.sm),
          _AmountRow(
            label: 'Total Liquidated',
            value: loan.totalLiquidated,
            strong: true,
          ),
        ],
      ),
    );
  }

  String _resolveBorrowerName(LiquidatedLoanRow loan) {
    final firstName = loan.firstName?.trim();
    final surname = loan.surname?.trim();

    final names = <String>[
      if (firstName != null && firstName.isNotEmpty) firstName,
      if (surname != null && surname.isNotEmpty) surname,
    ];

    if (names.isNotEmpty) {
      return names.join(' ');
    }

    final email = loan.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email;
    }

    final phone = loan.phone?.trim();

    if (phone != null && phone.isNotEmpty) {
      return phone;
    }

    return loan.userId;
  }

  String? _resolveBorrowerContact(LiquidatedLoanRow loan) {
    final email = loan.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email;
    }

    final phone = loan.phone?.trim();

    if (phone != null && phone.isNotEmpty) {
      return phone;
    }

    return null;
  }

  String _formatDateTime(BuildContext context, DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final local = value.toLocal();

    final date = MaterialLocalizations.of(context).formatMediumDate(local);

    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));

    return '$date, $time';
  }
}

class _LoanStatusBadge extends StatelessWidget {
  final String status;

  const _LoanStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = _statusColor(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        _formatStatus(status),
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String value) {
    switch (value.trim().toLowerCase()) {
      case 'liquidated':
        return Colors.red;

      case 'partially_liquidated':
        return Colors.orange;

      case 'active':
        return Colors.blue;

      case 'repaid':
      case 'closed':
        return Colors.green;

      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return 'Unknown';
    }

    return normalized
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}'
                    '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final bool strong;

  const _AmountRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Text(
          NumberFormatService.formatAmount(value, currency: 'usd'),
          textAlign: TextAlign.end,
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

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
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Text(
          value,
          textAlign: TextAlign.end,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
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
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Text(
            trailing,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _RefreshableState extends StatelessWidget {
  final Widget child;

  const _RefreshableState({required this.child});

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
