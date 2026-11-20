import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/finance/fiscal_period.dart';
import 'package:ngoda/data_models/finance/fiscal_period_summary.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/fiscal_periods_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
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

    _tabController = TabController(length: 2, initialIndex: 1, vsync: this);
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
              Tab(text: summary.previousFiscalYear.toString()),
              Tab(text: summary.currentFiscalYear.toString()),
            ],
          ),
        ),
        SizedBox(height: spacing.sm),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _FiscalYearView(
                fiscalYear: summary.previousFiscalYear,
                periods: summary.previousPeriods,
              ),
              _FiscalYearView(
                fiscalYear: summary.currentFiscalYear,
                periods: summary.currentPeriods,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FiscalYearView extends StatelessWidget {
  final int fiscalYear;
  final List<FiscalPeriod> periods;

  const _FiscalYearView({required this.fiscalYear, required this.periods});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final sortedPeriods = [...periods]
      ..sort((first, second) {
        return first.period.compareTo(second.period);
      });

    return ListView(
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
          closedPeriodCount: sortedPeriods
              .where((period) => period.isClosed)
              .length,
        ),
        SizedBox(height: spacing.sm),
        if (sortedPeriods.isEmpty)
          _NoPeriodsCard(fiscalYear: fiscalYear)
        else ...[
          const _PeriodTableHeader(),
          ...sortedPeriods.map((period) {
            return _PeriodRow(period: period);
          }),
        ],
      ],
    );
  }
}

class _FiscalYearTitle extends StatelessWidget {
  final int fiscalYear;
  final int periodCount;
  final int closedPeriodCount;

  const _FiscalYearTitle({
    required this.fiscalYear,
    required this.periodCount,
    required this.closedPeriodCount,
  });

  String get _yearStatus {
    if (periodCount == 0) {
      return 'Not configured';
    }

    if (closedPeriodCount == periodCount) {
      return 'Closed';
    }

    if (closedPeriodCount == 0) {
      return 'Open';
    }

    return 'Partially closed';
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
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
        SizedBox(width: spacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _yearStatus,
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$periodCount periods',
              style: AppTextStyles.tinyNumber(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
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
