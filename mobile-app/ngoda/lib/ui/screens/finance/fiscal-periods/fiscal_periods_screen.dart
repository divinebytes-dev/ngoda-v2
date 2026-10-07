import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/finance/fiscal_period.dart';
import 'package:ngoda/data_models/finance/fiscal_period_summary.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/fiscal_periods_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/open_fiscal_year_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FiscalPeriodsScreen extends ConsumerStatefulWidget {
  const FiscalPeriodsScreen({super.key});

  @override
  ConsumerState<FiscalPeriodsScreen> createState() {
    return _FiscalPeriodsScreenState();
  }
}

class _FiscalPeriodsScreenState extends ConsumerState<FiscalPeriodsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(fiscalPeriodsProvider);

    await ref.read(fiscalPeriodsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final asyncPeriods = ref.watch(fiscalPeriodsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Fiscal Periods',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncPeriods.when(
                  loading: () {
                    return const AppLoader(
                      message: 'Loading fiscal periods',
                      fullScreen: false,
                    );
                  },
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(
                        title: 'Fiscal Periods',
                        message: error.toString(),
                      ),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          title: 'Fiscal Periods',
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final summary = response.result;

                    if (summary == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _FiscalPeriodsContent(
                      tabController: _tabController,
                      summary: summary,
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

class _FiscalPeriodsContent extends StatelessWidget {
  final TabController tabController;
  final FiscalPeriodSummary summary;

  const _FiscalPeriodsContent({
    required this.tabController,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(horizontal: spacing.padding),
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius.borderRadius),
          ),
          child: TabBar(
            controller: tabController,
            indicator: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: colorScheme.onPrimary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            labelStyle: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: summary.currentFiscalYear.toString()),
              Tab(text: summary.nextFiscalYear.toString()),
            ],
          ),
        ),
        SizedBox(height: spacing.sm),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _FiscalYearView(
                fiscalYear: summary.currentFiscalYear,
                periods: summary.currentPeriods,
                isCurrentFiscalYear: true,
              ),
              _FiscalYearView(
                fiscalYear: summary.nextFiscalYear,
                periods: summary.nextPeriods,
                isCurrentFiscalYear: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FiscalYearView extends ConsumerWidget {
  final int fiscalYear;
  final List<FiscalPeriod> periods;
  final bool isCurrentFiscalYear;

  const _FiscalYearView({
    required this.fiscalYear,
    required this.periods,
    required this.isCurrentFiscalYear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final actionState = ref.watch(openFiscalYearProvider);

    final sortedPeriods = [...periods]
      ..sort((first, second) {
        return first.period.compareTo(second.period);
      });

    final hasPeriods = sortedPeriods.isNotEmpty;

    final hasOpenPeriods = sortedPeriods.any((period) => !period.isClosed);

    final allPeriodsClosed = hasPeriods && !hasOpenPeriods;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              spacing.sm,
              spacing.padding,
              spacing.sm,
            ),
            children: [
              _FiscalYearTitle(
                fiscalYear: fiscalYear,
                periodCount: sortedPeriods.length,
              ),
              SizedBox(height: spacing.sm),
              if (!hasPeriods)
                _NoPeriodsCard(fiscalYear: fiscalYear)
              else ...[
                const _PeriodTableHeader(),
                ...sortedPeriods.map((period) {
                  return _PeriodRow(period: period);
                }),
              ],
            ],
          ),
        ),
        _FiscalYearActions(
          fiscalYear: fiscalYear,
          isCurrentFiscalYear: isCurrentFiscalYear,
          hasPeriods: hasPeriods,
          hasOpenPeriods: hasOpenPeriods,
          allPeriodsClosed: allPeriodsClosed,
          isLoading: actionState.isLoading,
          onOpen: () async {
            await _openFiscalYear(context: context, ref: ref);
          },
          onClose: () async {
            await _closeFiscalYear(context: context, ref: ref);
          },
        ),
        if (actionState.error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.padding,
              0,
              spacing.padding,
              spacing.sm,
            ),
            child: AppErrorState(message: actionState.error!),
          ),
      ],
    );
  }

  Future<void> _openFiscalYear({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    if (periods.isNotEmpty) {
      return;
    }

    final confirmed = await _confirmAction(
      context: context,
      title: 'Open Fiscal Year $fiscalYear',
      message:
          'Create the fiscal periods for fiscal year '
          '$fiscalYear using the previous fiscal year '
          'configuration?',
      actionText: 'Open',
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final success = await ref
        .read(openFiscalYearProvider.notifier)
        .openFiscalYear();

    if (!context.mounted || !success) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fiscal year $fiscalYear opened successfully')),
    );

    ref.read(openFiscalYearProvider.notifier).reset();
  }

  Future<void> _closeFiscalYear({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final hasOpenPeriods = periods.any((period) => !period.isClosed);

    if (!hasOpenPeriods) {
      return;
    }

    final confirmed = await _confirmAction(
      context: context,
      title: 'Close Fiscal Year $fiscalYear',
      message:
          'Close all open periods for fiscal year '
          '$fiscalYear?',
      actionText: 'Close',
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final success = await ref
        .read(openFiscalYearProvider.notifier)
        .closeFiscalYear(fiscalYear: fiscalYear);

    if (!context.mounted || !success) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fiscal year $fiscalYear closed successfully')),
    );

    ref.read(openFiscalYearProvider.notifier).reset();
  }

  Future<bool?> _confirmAction({
    required BuildContext context,
    required String title,
    required String message,
    required String actionText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(actionText),
            ),
          ],
        );
      },
    );
  }
}

class _FiscalYearTitle extends StatelessWidget {
  final int fiscalYear;
  final int periodCount;

  const _FiscalYearTitle({required this.fiscalYear, required this.periodCount});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Fiscal Year $fiscalYear',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          '$periodCount periods',
          style: AppTextStyles.tinyNumber(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PeriodTableHeader extends StatelessWidget {
  const _PeriodTableHeader();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(radius.borderRadius),
        ),
      ),
      child: Row(
        children: [
          const _PeriodColumn(width: 50, text: 'Period'),
          const _PeriodColumn(width: 55, text: 'Name'),
          Expanded(
            child: Text(
              'Opening',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              'Closing',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const _PeriodColumn(
            width: 60,
            text: 'Status',
            align: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final FiscalPeriod period;

  const _PeriodRow({required this.period});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final statusColor = period.isClosed
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant),
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              period.period.toString(),
              style: AppTextStyles.tinyNumber(context),
            ),
          ),
          SizedBox(
            width: 55,
            child: Text(period.periodName, style: AppTextStyles.tiny(context)),
          ),
          Expanded(
            child: Text(
              _formatDate(period.openingDate),
              style: AppTextStyles.tinyNumber(context),
            ),
          ),
          Expanded(
            child: Text(
              _formatDate(period.closingDate),
              style: AppTextStyles.tinyNumber(context),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              period.isClosed ? 'Closed' : 'Open',
              textAlign: TextAlign.right,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _PeriodColumn extends StatelessWidget {
  final double width;
  final String text;
  final TextAlign align;

  const _PeriodColumn({
    required this.width,
    required this.text,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: align,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NoPeriodsCard extends StatelessWidget {
  final int fiscalYear;

  const _NoPeriodsCard({required this.fiscalYear});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'No periods configured for '
            'fiscal year $fiscalYear',
            textAlign: TextAlign.center,
            style: AppTextStyles.small(context),
          ),
        ],
      ),
    );
  }
}

class _FiscalYearActions extends StatelessWidget {
  final int fiscalYear;
  final bool isCurrentFiscalYear;
  final bool hasPeriods;
  final bool hasOpenPeriods;
  final bool allPeriodsClosed;
  final bool isLoading;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _FiscalYearActions({
    required this.fiscalYear,
    required this.isCurrentFiscalYear,
    required this.hasPeriods,
    required this.hasOpenPeriods,
    required this.allPeriodsClosed,
    required this.isLoading,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        spacing.padding,
        spacing.sm,
        spacing.padding,
        spacing.padding,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: isCurrentFiscalYear
          ? AppButton(
              isPrimary: true,
              text: allPeriodsClosed
                  ? 'Fiscal Year $fiscalYear Closed'
                  : 'Close Fiscal Year $fiscalYear',
              isProcessing: isLoading,
              onPressed: hasPeriods && hasOpenPeriods && !isLoading
                  ? onClose
                  : null,
            )
          : AppButton(
              isPrimary: true,
              text: hasPeriods
                  ? 'Fiscal Year $fiscalYear Opened'
                  : 'Open Fiscal Year $fiscalYear',
              isProcessing: isLoading,
              onPressed: !hasPeriods && !isLoading ? onOpen : null,
            ),
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
