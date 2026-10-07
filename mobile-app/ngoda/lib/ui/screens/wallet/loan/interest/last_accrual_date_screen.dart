import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/last_interest_acrual_date_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LastAccrualDateScreen extends ConsumerStatefulWidget {
  const LastAccrualDateScreen({super.key});

  @override
  ConsumerState<LastAccrualDateScreen> createState() =>
      _LastAccrualDateScreenState();
}

class _LastAccrualDateScreenState extends ConsumerState<LastAccrualDateScreen> {
  Future<void> _refresh() async {
    ref.invalidate(lastInterestAccrualDateProvider);

    await ref.read(lastInterestAccrualDateProvider.future);
  }

  void _close() {
    ref.invalidate(lastInterestAccrualDateProvider);

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final asyncData = ref.watch(lastInterestAccrualDateProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: ViewHeader(
                title: 'Last Interest Accrual Date',
                onClose: _close,
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncData.when(
                  loading: () => const _RefreshableState(
                    child: AppLoader(
                      message: 'Getting last accrual date',
                      fullScreen: false,
                    ),
                  ),
                  error: (error, _) => _RefreshableState(
                    child: AppErrorState(message: error.toString()),
                  ),
                  data: (result) {
                    if (result.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: result.error!),
                      );
                    }

                    return _AccrualDateContent(date: result.result);
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

class _AccrualDateContent extends StatelessWidget {
  const _AccrualDateContent({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(spacing.lg),
      children: [
        SizedBox(height: spacing.lg),

        Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(context.radius.lg),
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(spacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(context.radius.md),
            ),
            child: Column(
              children: [
                Container(
                  width: context.iconSize.xl,
                  height: context.iconSize.xl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    color: colorScheme.primary,
                    size: context.iconSize.medium,
                  ),
                ),

                SizedBox(height: spacing.lg),

                Text(
                  'Last Interest Accrual',
                  style: AppTextStyles.small(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                SizedBox(height: spacing.sm),

                Text(
                  date == null
                      ? 'No accrual run recorded'
                      : DateFormatService.formatCronJobDateTime(date),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),

                SizedBox(height: spacing.lg),

                Divider(
                  height: 1,
                  color: colorScheme.outline.withValues(alpha: 0.12),
                ),

                SizedBox(height: spacing.md),

                Text(
                  'Pull down to refresh the latest accrual status.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
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
