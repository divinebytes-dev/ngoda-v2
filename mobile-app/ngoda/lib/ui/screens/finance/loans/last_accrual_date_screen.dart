import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/last_interest_acrual_date_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LastAccrualDateScreen extends ConsumerWidget {
  const LastAccrualDateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final asyncData = ref.watch(lastInterestAccrualDateProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Last Interest Accrual Date',
              onClose: () => context.pop(),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(lastInterestAccrualDateProvider);

                  await ref.read(lastInterestAccrualDateProvider.future);
                },
                child: asyncData.when(
                  loading: () => const AppLoader(
                    message: 'Getting last accrual date',
                    fullScreen: false,
                  ),
                  error: (error, _) {
                    return _RefreshableState(
                      child: AppErrorState(
                        title: 'Last Interest Accrual Date',
                        message: error.toString(),
                      ),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          title: 'Last Interest Accrual Date',
                          message: response.error.toString(),
                        ),
                      );
                    }

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(spacing.padding),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.lg),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(radius.sm),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Interest Accrual',
                                style: AppTextStyles.small(context).copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              SizedBox(height: spacing.sm),

                              Text(
                                DateFormatService.formatCronJobDateTime(
                                  response.result,
                                ),
                                style: AppTextStyles.medium(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
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
