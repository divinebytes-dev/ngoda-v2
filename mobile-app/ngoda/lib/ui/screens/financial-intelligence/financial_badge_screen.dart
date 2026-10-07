import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge.dart';
import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge_list.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/screens/financial-intelligence/provider/financial_badges_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class FinancialBadgeScreen extends ConsumerWidget {
  const FinancialBadgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(financialBadgesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Financial Badges',
              onClose: () {
                ref.invalidate(financialBadgesProvider);

                context.pop();
              },
            ),
            Expanded(
              child: result.when(
                loading: () => const AppLoader(
                  message: 'Loading financial badges',
                  fullScreen: true,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.hasError) {
                    return AppErrorState(message: response.error);
                  }

                  final data = response.result;

                  if (data == null || data.isEmpty) {
                    return const AppEmptyState();
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(financialBadgesProvider);

                      await ref.read(financialBadgesProvider.future);
                    },
                    child: _BadgeBody(data: data),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeBody extends StatelessWidget {
  const _BadgeBody({required this.data});

  final FinancialBadgeList data;

  @override
  Widget build(BuildContext context) {
    final horizontal = ScreenScalingService.scaleSize(context, 16);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        ScreenScalingService.scaleSize(context, 8),
        horizontal,
        ScreenScalingService.scaleSize(context, 32),
      ),
      children: [
        _BadgeSummaryCard(data: data),

        SizedBox(height: ScreenScalingService.scaleSize(context, 28)),

        Text(
          'Your financial achievements',
          style: AppTextStyles.medium(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 4)),

        Text(
          'Build each financial behaviour and unlock new milestones.',
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: ScreenScalingService.scaleSize(context, 20)),

        for (final behavior in data.behaviorCodes) ...[
          _BehaviourBadgeSection(
            behavior: behavior,
            badges: data.badgesForBehavior(behavior),
            earnedCount: data.earnedCountForBehavior(behavior),
            completion: data.completionForBehavior(behavior),
            nextBadge: data.nextBadgeForBehavior(behavior),
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 20)),
        ],
      ],
    );
  }
}

class _BadgeSummaryCard extends StatelessWidget {
  const _BadgeSummaryCard({required this.data});

  final FinancialBadgeList data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final percent = data.completionPercent.clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 18)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: ScreenScalingService.scaleSize(context, 52),
                height: ScreenScalingService.scaleSize(context, 52),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: colors.primary,
                  size: ScreenScalingService.scaleSize(context, 27),
                ),
              ),

              SizedBox(width: ScreenScalingService.scaleSize(context, 14)),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your achievements',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(
                      height: ScreenScalingService.scaleSize(context, 3),
                    ),
                    Text(
                      '${data.earnedCount} of '
                      '${data.totalCount} badges earned',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              Text(
                '${percent.toStringAsFixed(0)}%',
                style: AppTextStyles.mediumNumber(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 18)),

          ClipRRect(
            borderRadius: BorderRadius.circular(
              ScreenScalingService.scaleSize(context, 20),
            ),
            child: LinearProgressIndicator(
              value: data.completionRatio.clamp(0, 1),
              minHeight: ScreenScalingService.scaleSize(context, 9),
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 18)),

          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  icon: Icons.check_circle_outline,
                  label: 'Earned',
                  value: data.earnedCount.toString(),
                  color: colors.primary,
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  icon: Icons.lock_outline,
                  label: 'Locked',
                  value: data.lockedCount.toString(),
                  color: colors.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Total',
                  value: data.totalCount.toString(),
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: ScreenScalingService.scaleSize(context, 15),
              color: color,
            ),
            SizedBox(width: ScreenScalingService.scaleSize(context, 5)),
            Text(
              value,
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: ScreenScalingService.scaleSize(context, 2)),
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _BehaviourBadgeSection extends StatelessWidget {
  const _BehaviourBadgeSection({
    required this.behavior,
    required this.badges,
    required this.earnedCount,
    required this.completion,
    required this.nextBadge,
  });

  final String behavior;
  final List<FinancialBadge> badges;
  final int earnedCount;
  final double completion;
  final FinancialBadge? nextBadge;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;

    final first = badges.first;

    final color = _BadgeColors.behavior(context, behavior);

    /*
     * The current next milestone is intentionally
     * excluded from the collection.
     *
     * It is displayed prominently above the
     * collection instead.
     */
    final collection = badges
        .where((badge) => nextBadge == null || badge.id != nextBadge!.id)
        .toList(growable: false);

    final completionPercent = (completion * 100)
        .clamp(0, 100)
        .toStringAsFixed(0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 18),
        ),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /*
           * Behaviour identity and overall
           * badge completion.
           */
          Row(
            children: [
              Container(
                width: ScreenScalingService.scaleSize(context, 44),
                height: ScreenScalingService.scaleSize(context, 44),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _BadgeIcons.behavior(behavior),
                  size: ScreenScalingService.scaleSize(context, 22),
                  color: color,
                ),
              ),

              SizedBox(width: ScreenScalingService.scaleSize(context, 12)),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first.behaviorLabel,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(
                      height: ScreenScalingService.scaleSize(context, 2),
                    ),
                    Text(
                      '$earnedCount of '
                      '${badges.length} achievements unlocked',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ScreenScalingService.scaleSize(context, 9),
                  vertical: ScreenScalingService.scaleSize(context, 5),
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(
                    ScreenScalingService.scaleSize(context, 20),
                  ),
                ),
                child: Text(
                  '$completionPercent%',
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          SizedBox(height: ScreenScalingService.scaleSize(context, 12)),

          ClipRRect(
            borderRadius: BorderRadius.circular(
              ScreenScalingService.scaleSize(context, 20),
            ),
            child: LinearProgressIndicator(
              value: completion.clamp(0, 1),
              minHeight: ScreenScalingService.scaleSize(context, 6),
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),

          /*
           * The next milestone is the main action
           * inside each behaviour.
           */
          if (nextBadge != null) ...[
            SizedBox(height: ScreenScalingService.scaleSize(context, 18)),

            _NextBadgeCard(
              badge: nextBadge!,
              color: color,
              onTap: () {
                _showBadgeDetails(context, nextBadge!, color);
              },
            ),
          ],

          if (nextBadge == null && earnedCount == badges.length) ...[
            SizedBox(height: ScreenScalingService.scaleSize(context, 18)),

            _CompletedBehaviourCard(
              behaviorLabel: first.behaviorLabel,
              color: color,
            ),
          ],

          /*
           * Collection comes after the next
           * milestone.
           */
          if (collection.isNotEmpty) ...[
            SizedBox(height: ScreenScalingService.scaleSize(context, 20)),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Badge collection',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${collection.where((badge) => badge.earned).length} unlocked',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),

            SizedBox(height: ScreenScalingService.scaleSize(context, 10)),

            SizedBox(
              height: ScreenScalingService.scaleSize(context, 162),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: collection.length,
                separatorBuilder: (_, _) => SizedBox(
                  width: ScreenScalingService.scaleSize(context, 10),
                ),
                itemBuilder: (context, index) {
                  final badge = collection[index];

                  return _BadgeCard(
                    badge: badge,
                    color: color,
                    onTap: () {
                      _showBadgeDetails(context, badge, color);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextBadgeCard extends StatelessWidget {
  const _NextBadgeCard({
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final FinancialBadge badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final money = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);

    final achieved = badge.achievedValueUsd;

    final threshold = badge.thresholdUsd;

    final hasProgress = achieved != null && threshold > 0;

    final progress = hasProgress ? (achieved / threshold).clamp(0.0, 1.0) : 0.0;

    final remaining = hasProgress
        ? (threshold - achieved).clamp(0.0, double.infinity)
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 16),
        ),
        child: Ink(
          width: double.infinity,
          padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(
              ScreenScalingService.scaleSize(context, 16),
            ),
            border: Border.all(color: color.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: ScreenScalingService.scaleSize(context, 36),
                    height: ScreenScalingService.scaleSize(context, 36),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.flag_outlined,
                      color: color,
                      size: ScreenScalingService.scaleSize(context, 19),
                    ),
                  ),

                  SizedBox(width: ScreenScalingService.scaleSize(context, 10)),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXT MILESTONE',
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: color, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(
                          height: ScreenScalingService.scaleSize(context, 2),
                        ),
                        Text(
                          badge.name,
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),

                  Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ],
              ),

              SizedBox(height: ScreenScalingService.scaleSize(context, 12)),

              Row(
                children: [
                  _MilestoneChip(label: badge.levelLabel, color: color),
                  SizedBox(width: ScreenScalingService.scaleSize(context, 6)),
                  Expanded(
                    child: Text(
                      badge.metricLabel,
                      textAlign: TextAlign.right,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),

              SizedBox(height: ScreenScalingService.scaleSize(context, 14)),

              if (hasProgress) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current',
                            style: AppTextStyles.tiny(
                              context,
                            ).copyWith(color: colors.onSurfaceVariant),
                          ),
                          SizedBox(
                            height: ScreenScalingService.scaleSize(context, 2),
                          ),
                          Text(
                            money.format(achieved),
                            style: AppTextStyles.smallNumber(
                              context,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),

                    Icon(
                      Icons.arrow_forward_rounded,
                      size: ScreenScalingService.scaleSize(context, 18),
                      color: colors.onSurfaceVariant,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Target',
                            style: AppTextStyles.tiny(
                              context,
                            ).copyWith(color: colors.onSurfaceVariant),
                          ),
                          SizedBox(
                            height: ScreenScalingService.scaleSize(context, 2),
                          ),
                          Text(
                            money.format(threshold),
                            textAlign: TextAlign.right,
                            style: AppTextStyles.smallNumber(context).copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ScreenScalingService.scaleSize(context, 12)),

                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          ScreenScalingService.scaleSize(context, 20),
                        ),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: ScreenScalingService.scaleSize(context, 7),
                          color: color,
                          backgroundColor: colors.surfaceContainerHighest,
                        ),
                      ),
                    ),

                    SizedBox(
                      width: ScreenScalingService.scaleSize(context, 10),
                    ),

                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: AppTextStyles.tinyNumber(
                        context,
                      ).copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),

                if (remaining != null && remaining > 0) ...[
                  SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
                  Text(
                    '${money.format(remaining)} '
                    'remaining to unlock',
                    style: AppTextStyles.tiny(
                      context,
                    ).copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Target',
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                    Text(
                      money.format(threshold),
                      style: AppTextStyles.smallNumber(
                        context,
                      ).copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),

                SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

                Text(
                  'Keep building your '
                  '${badge.metricLabel.toLowerCase()} '
                  'activity to unlock this badge.',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MilestoneChip extends StatelessWidget {
  const _MilestoneChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenScalingService.scaleSize(context, 9),
        vertical: ScreenScalingService.scaleSize(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 20),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CompletedBehaviourCard extends StatelessWidget {
  const _CompletedBehaviourCard({
    required this.behaviorLabel,
    required this.color,
  });

  final String behaviorLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 14)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 14),
        ),
        border: Border.all(color: color.withValues(alpha: 0.009)),
      ),
      child: Row(
        children: [
          Container(
            width: ScreenScalingService.scaleSize(context, 36),
            height: ScreenScalingService.scaleSize(context, 36),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: color,
              size: ScreenScalingService.scaleSize(context, 20),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$behaviorLabel complete',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: ScreenScalingService.scaleSize(context, 2)),
                Text(
                  'All available $behaviorLabel badges have been earned.',
                  style: AppTextStyles.tiny(context).copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final FinancialBadge badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final activeColor = badge.earned ? color : colors.onSurfaceVariant;

    return SizedBox(
      width: ScreenScalingService.scaleSize(context, 132),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            ScreenScalingService.scaleSize(context, 15),
          ),
          child: Ink(
            padding: EdgeInsets.all(
              ScreenScalingService.scaleSize(context, 12),
            ),
            decoration: BoxDecoration(
              color: badge.earned
                  ? color.withValues(alpha: 0.09)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(
                ScreenScalingService.scaleSize(context, 15),
              ),
              border: Border.all(
                color: badge.earned
                    ? color.withValues(alpha: 0.09)
                    : colors.outlineVariant.withValues(alpha: 0.09),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: ScreenScalingService.scaleSize(context, 36),
                      height: ScreenScalingService.scaleSize(context, 36),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.13),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        badge.earned
                            ? Icons.workspace_premium
                            : Icons.lock_outline,
                        size: ScreenScalingService.scaleSize(context, 19),
                        color: activeColor,
                      ),
                    ),

                    const Spacer(),

                    Text(
                      badge.levelLabel,
                      style: AppTextStyles.tiny(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ScreenScalingService.scaleSize(context, 10)),

                Text(
                  badge.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.small(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: badge.earned ? null : colors.onSurfaceVariant,
                  ),
                ),

                const Spacer(),

                Row(
                  children: [
                    Icon(
                      badge.earned
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      size: ScreenScalingService.scaleSize(context, 14),
                      color: activeColor,
                    ),
                    SizedBox(width: ScreenScalingService.scaleSize(context, 4)),
                    Text(
                      badge.earned ? 'Earned' : 'Locked',
                      style: AppTextStyles.tiny(context).copyWith(
                        color: activeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showBadgeDetails(
  BuildContext context,
  FinancialBadge badge,
  Color color,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _BadgeDetailSheet(badge: badge, color: color);
    },
  );
}

class _BadgeDetailSheet extends StatelessWidget {
  const _BadgeDetailSheet({required this.badge, required this.color});

  final FinancialBadge badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final money = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);

    final achievedAt = badge.achievedAt;

    final achieved = badge.achievedValueUsd;

    final hasProgress =
        !badge.earned && achieved != null && badge.thresholdUsd > 0;

    final progress = hasProgress
        ? (achieved / badge.thresholdUsd).clamp(0.0, 1.0)
        : 0.0;

    final remaining = hasProgress
        ? (badge.thresholdUsd - achieved).clamp(0.0, double.infinity)
        : null;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ScreenScalingService.scaleSize(context, 20),
          ScreenScalingService.scaleSize(context, 4),
          ScreenScalingService.scaleSize(context, 20),
          ScreenScalingService.scaleSize(context, 28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: ScreenScalingService.scaleSize(context, 72),
                height: ScreenScalingService.scaleSize(context, 72),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: badge.earned ? 0.14 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  badge.earned ? Icons.workspace_premium : Icons.lock_outline,
                  color: badge.earned ? color : colors.onSurfaceVariant,
                  size: ScreenScalingService.scaleSize(context, 34),
                ),
              ),
            ),

            SizedBox(height: ScreenScalingService.scaleSize(context, 14)),

            Center(
              child: Text(
                badge.name,
                textAlign: TextAlign.center,
                style: AppTextStyles.medium(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),

            SizedBox(height: ScreenScalingService.scaleSize(context, 6)),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: ScreenScalingService.scaleSize(context, 8),
                runSpacing: ScreenScalingService.scaleSize(context, 6),
                children: [
                  _DetailChip(label: badge.behaviorLabel, color: color),
                  _DetailChip(label: badge.metricLabel, color: color),
                  _DetailChip(label: badge.levelLabel, color: color),
                ],
              ),
            ),

            if (badge.description?.trim().isNotEmpty == true) ...[
              SizedBox(height: ScreenScalingService.scaleSize(context, 18)),
              Text(
                badge.description!,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colors.onSurfaceVariant),
              ),
            ],

            SizedBox(height: ScreenScalingService.scaleSize(context, 20)),

            _DetailRow(
              label: 'Status',
              value: badge.statusLabel,
              emphasized: true,
            ),

            _DetailRow(label: 'Activity', value: badge.metricLabel),

            _DetailRow(
              label: 'Threshold',
              value: money.format(badge.thresholdUsd),
            ),

            if (badge.earned && achieved != null)
              _DetailRow(
                label: 'Achieved value',
                value: money.format(achieved),
              ),

            if (badge.earned && badge.achievementPeriodLabel != null)
              _DetailRow(
                label: 'Achieved in',
                value: badge.achievementPeriodLabel!,
              ),

            if (badge.earned && achievedAt != null)
              _DetailRow(
                label: 'Achieved on',
                value: DateFormat('dd MMM yyyy').format(achievedAt.toLocal()),
              ),

            if (hasProgress) ...[
              SizedBox(height: ScreenScalingService.scaleSize(context, 18)),

              Text(
                'Progress',
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              SizedBox(height: ScreenScalingService.scaleSize(context, 8)),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${money.format(achieved)} '
                      'of '
                      '${money.format(badge.thresholdUsd)}',
                      style: AppTextStyles.tinyNumber(context),
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),

              SizedBox(height: ScreenScalingService.scaleSize(context, 7)),

              ClipRRect(
                borderRadius: BorderRadius.circular(
                  ScreenScalingService.scaleSize(context, 20),
                ),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: ScreenScalingService.scaleSize(context, 7),
                  color: color,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),

              if (remaining != null && remaining > 0) ...[
                SizedBox(height: ScreenScalingService.scaleSize(context, 7)),
                Text(
                  '${money.format(remaining)} remaining',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],

            if (!badge.earned && !hasProgress) ...[
              SizedBox(height: ScreenScalingService.scaleSize(context, 16)),

              Container(
                width: double.infinity,
                padding: EdgeInsets.all(
                  ScreenScalingService.scaleSize(context, 14),
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(
                    ScreenScalingService.scaleSize(context, 14),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: ScreenScalingService.scaleSize(context, 18),
                      color: colors.onSurfaceVariant,
                    ),
                    SizedBox(width: ScreenScalingService.scaleSize(context, 9)),
                    Expanded(
                      child: Text(
                        'Reach '
                        '${money.format(badge.thresholdUsd)} '
                        'in '
                        '${badge.metricLabel.toLowerCase()} '
                        'to unlock this badge.',
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenScalingService.scaleSize(context, 10),
        vertical: ScreenScalingService.scaleSize(context, 5),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(
          ScreenScalingService.scaleSize(context, 20),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ScreenScalingService.scaleSize(context, 6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextStyles.tinyNumber(context).copyWith(
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeColors {
  const _BadgeColors._();

  static Color behavior(BuildContext context, String behavior) {
    final colors = Theme.of(context).colorScheme;

    switch (behavior.trim().toLowerCase()) {
      case 'saver':
        return colors.primary;

      case 'investor':
        return colors.tertiary;

      case 'shopper':
        return colors.error;

      case 'borrower':
        /*
         * Borrower is borrowing / loan
         * disbursement behaviour.
         *
         * It does not represent repayment.
         */
        return colors.secondary;

      default:
        return colors.onSurfaceVariant;
    }
  }
}

class _BadgeIcons {
  const _BadgeIcons._();

  static IconData behavior(String behavior) {
    switch (behavior.trim().toLowerCase()) {
      case 'saver':
        return Icons.savings_outlined;

      case 'investor':
        return Icons.trending_up;

      case 'shopper':
        return Icons.shopping_bag_outlined;

      case 'borrower':
        return Icons.account_balance_outlined;

      default:
        return Icons.workspace_premium_outlined;
    }
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:intl/intl.dart';

// import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge.dart';
// import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge_list.dart';
// import 'package:ngoda/services/screen_scaling_service.dart';
// import 'package:ngoda/ui/screens/financial-intelligence/provider/financial_badges_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_empty_state.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class FinancialBadgeScreen extends ConsumerWidget {
//   const FinancialBadgeScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final result = ref.watch(financialBadgesProvider);

//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             ViewHeader(
//               title: 'Financial Badges',
//               onClose: () {
//                 ref.invalidate(financialBadgesProvider);

//                 context.pop();
//               },
//             ),
//             Expanded(
//               child: result.when(
//                 loading: () => const AppLoader(
//                   message: 'Loading financial badges',
//                   fullScreen: true,
//                 ),
//                 error: (error, _) {
//                   return AppErrorState(message: error.toString());
//                 },
//                 data: (response) {
//                   if (response.hasError) {
//                     return AppErrorState(message: response.error);
//                   }

//                   final data = response.result;

//                   if (data == null || data.isEmpty) {
//                     return const AppEmptyState();
//                   }

//                   return RefreshIndicator(
//                     onRefresh: () async {
//                       ref.invalidate(financialBadgesProvider);

//                       await ref.read(financialBadgesProvider.future);
//                     },
//                     child: _BadgeBody(data: data),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _BadgeBody extends StatelessWidget {
//   const _BadgeBody({required this.data});

//   final FinancialBadgeList data;

//   @override
//   Widget build(BuildContext context) {
//     final horizontal = ScreenScalingService.scaleSize(context, 16);

//     return ListView(
//       physics: const AlwaysScrollableScrollPhysics(),
//       padding: EdgeInsets.fromLTRB(
//         horizontal,
//         ScreenScalingService.scaleSize(context, 8),
//         horizontal,
//         ScreenScalingService.scaleSize(context, 32),
//       ),
//       children: [
//         _BadgeSummaryCard(data: data),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 24)),
//         for (final behavior in data.behaviorCodes) ...[
//           _BehaviourBadgeSection(
//             behavior: behavior,
//             badges: data.badgesForBehavior(behavior),
//             earnedCount: data.earnedCountForBehavior(behavior),
//             completion: data.completionForBehavior(behavior),
//             nextBadge: data.nextBadgeForBehavior(behavior),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 28)),
//         ],
//       ],
//     );
//   }
// }

// class _BadgeSummaryCard extends StatelessWidget {
//   const _BadgeSummaryCard({required this.data});

//   final FinancialBadgeList data;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     final percent = data.completionPercent.clamp(0, 100);

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 18)),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 16),
//         ),
//         border: Border.all(
//           color: colors.outlineVariant.withValues(alpha: 0.55),
//         ),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 width: ScreenScalingService.scaleSize(context, 48),
//                 height: ScreenScalingService.scaleSize(context, 48),
//                 decoration: BoxDecoration(
//                   color: colors.primary.withValues(alpha: 0.12),
//                   shape: BoxShape.circle,
//                 ),
//                 child: Icon(
//                   Icons.workspace_premium_outlined,
//                   color: colors.primary,
//                   size: ScreenScalingService.scaleSize(context, 25),
//                 ),
//               ),
//               SizedBox(width: ScreenScalingService.scaleSize(context, 14)),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Your achievements',
//                       style: AppTextStyles.small(
//                         context,
//                       ).copyWith(fontWeight: FontWeight.w700),
//                     ),
//                     SizedBox(
//                       height: ScreenScalingService.scaleSize(context, 3),
//                     ),
//                     Text(
//                       '${data.earnedCount} of '
//                       '${data.totalCount} badges earned',
//                       style: AppTextStyles.tiny(
//                         context,
//                       ).copyWith(color: colors.onSurfaceVariant),
//                     ),
//                   ],
//                 ),
//               ),
//               Text(
//                 '${percent.toStringAsFixed(0)}%',
//                 style: AppTextStyles.mediumNumber(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//             ],
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           ClipRRect(
//             borderRadius: BorderRadius.circular(
//               ScreenScalingService.scaleSize(context, 20),
//             ),
//             child: LinearProgressIndicator(
//               value: data.completionRatio.clamp(0, 1),
//               minHeight: ScreenScalingService.scaleSize(context, 9),
//               backgroundColor: colors.surfaceContainerHighest,
//             ),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           Row(
//             children: [
//               Expanded(
//                 child: _SummaryValue(
//                   label: 'Earned',
//                   value: data.earnedCount.toString(),
//                 ),
//               ),
//               Expanded(
//                 child: _SummaryValue(
//                   label: 'Locked',
//                   value: data.lockedCount.toString(),
//                 ),
//               ),
//               Expanded(
//                 child: _SummaryValue(
//                   label: 'Total',
//                   value: data.totalCount.toString(),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryValue extends StatelessWidget {
//   const _SummaryValue({required this.label, required this.value});

//   final String label;
//   final String value;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           value,
//           style: AppTextStyles.smallNumber(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         Text(
//           label,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colors.onSurfaceVariant),
//         ),
//       ],
//     );
//   }
// }

// class _BehaviourBadgeSection extends StatelessWidget {
//   const _BehaviourBadgeSection({
//     required this.behavior,
//     required this.badges,
//     required this.earnedCount,
//     required this.completion,
//     required this.nextBadge,
//   });

//   final String behavior;
//   final List<FinancialBadge> badges;
//   final int earnedCount;
//   final double completion;
//   final FinancialBadge? nextBadge;

//   @override
//   Widget build(BuildContext context) {
//     if (badges.isEmpty) {
//       return const SizedBox.shrink();
//     }

//     final colors = Theme.of(context).colorScheme;

//     final first = badges.first;

//     final color = _BadgeColors.behavior(context, behavior);

//     final collection = badges
//         .where((badge) => nextBadge == null || badge.id != nextBadge!.id)
//         .toList(growable: false);

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Container(
//               width: ScreenScalingService.scaleSize(context, 38),
//               height: ScreenScalingService.scaleSize(context, 38),
//               decoration: BoxDecoration(
//                 color: color.withValues(alpha: 0.12),
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 _BadgeIcons.behavior(behavior),
//                 size: ScreenScalingService.scaleSize(context, 20),
//                 color: color,
//               ),
//             ),
//             SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     first.behaviorLabel,
//                     style: AppTextStyles.small(
//                       context,
//                     ).copyWith(fontWeight: FontWeight.w700),
//                   ),
//                   Text(
//                     '$earnedCount of '
//                     '${badges.length} earned',
//                     style: AppTextStyles.tiny(
//                       context,
//                     ).copyWith(color: colors.onSurfaceVariant),
//                   ),
//                 ],
//               ),
//             ),
//             Text(
//               '${(completion * 100).clamp(0, 100).toStringAsFixed(0)}%',
//               style: AppTextStyles.tinyNumber(
//                 context,
//               ).copyWith(fontWeight: FontWeight.w700, color: color),
//             ),
//           ],
//         ),
//         SizedBox(height: ScreenScalingService.scaleSize(context, 10)),
//         ClipRRect(
//           borderRadius: BorderRadius.circular(
//             ScreenScalingService.scaleSize(context, 20),
//           ),
//           child: LinearProgressIndicator(
//             value: completion.clamp(0, 1),
//             minHeight: ScreenScalingService.scaleSize(context, 6),
//             color: color,
//             backgroundColor: colors.surfaceContainerHighest,
//           ),
//         ),

//         // The next milestone is intentionally
//         // shown before the collection.
//         if (nextBadge != null) ...[
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           _NextBadgeCard(
//             badge: nextBadge!,
//             color: color,
//             onTap: () {
//               _showBadgeDetails(context, nextBadge!, color);
//             },
//           ),
//         ],

//         if (collection.isNotEmpty) ...[
//           SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//           Text(
//             'Badge collection',
//             style: AppTextStyles.tiny(context).copyWith(
//               fontWeight: FontWeight.w700,
//               color: colors.onSurfaceVariant,
//             ),
//           ),
//           SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
//           SizedBox(
//             height: ScreenScalingService.scaleSize(context, 174),
//             child: ListView.separated(
//               scrollDirection: Axis.horizontal,
//               itemCount: collection.length,
//               separatorBuilder: (_, __) =>
//                   SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
//               itemBuilder: (context, index) {
//                 final badge = collection[index];

//                 return _BadgeCard(
//                   badge: badge,
//                   color: color,
//                   onTap: () {
//                     _showBadgeDetails(context, badge, color);
//                   },
//                 );
//               },
//             ),
//           ),
//         ],

//         if (nextBadge == null && earnedCount == badges.length) ...[
//           SizedBox(height: ScreenScalingService.scaleSize(context, 14)),
//           _CompletedBehaviourCard(
//             behaviorLabel: first.behaviorLabel,
//             color: color,
//           ),
//         ],
//       ],
//     );
//   }
// }

// class _NextBadgeCard extends StatelessWidget {
//   const _NextBadgeCard({
//     required this.badge,
//     required this.color,
//     required this.onTap,
//   });

//   final FinancialBadge badge;
//   final Color color;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     final money = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);

//     final achieved = badge.achievedValueUsd;

//     final threshold = badge.thresholdUsd;

//     final hasProgress = achieved != null && threshold > 0;

//     final progress = hasProgress ? (achieved / threshold).clamp(0.0, 1.0) : 0.0;

//     final remaining = hasProgress
//         ? (threshold - achieved).clamp(0.0, double.infinity)
//         : null;

//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 16),
//         ),
//         child: Ink(
//           width: double.infinity,
//           padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 16)),
//           decoration: BoxDecoration(
//             color: color.withValues(alpha: 0.07),
//             borderRadius: BorderRadius.circular(
//               ScreenScalingService.scaleSize(context, 16),
//             ),
//             border: Border.all(color: color.withValues(alpha: 0.30)),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(
//                     Icons.flag_outlined,
//                     color: color,
//                     size: ScreenScalingService.scaleSize(context, 20),
//                   ),
//                   SizedBox(width: ScreenScalingService.scaleSize(context, 8)),
//                   Expanded(
//                     child: Text(
//                       'NEXT MILESTONE',
//                       style: AppTextStyles.tiny(
//                         context,
//                       ).copyWith(color: color, fontWeight: FontWeight.w700),
//                     ),
//                   ),
//                   Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
//                 ],
//               ),
//               SizedBox(height: ScreenScalingService.scaleSize(context, 10)),
//               Text(
//                 badge.name,
//                 style: AppTextStyles.small(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//               SizedBox(height: ScreenScalingService.scaleSize(context, 3)),
//               Text(
//                 '${badge.levelLabel} • '
//                 '${money.format(threshold)} '
//                 '${badge.metricLabel.toLowerCase()}',
//                 style: AppTextStyles.tiny(
//                   context,
//                 ).copyWith(color: colors.onSurfaceVariant),
//               ),
//               if (hasProgress) ...[
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 14)),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         '${money.format(achieved)} '
//                         'of '
//                         '${money.format(threshold)}',
//                         style: AppTextStyles.tinyNumber(
//                           context,
//                         ).copyWith(fontWeight: FontWeight.w600),
//                       ),
//                     ),
//                     Text(
//                       '${(progress * 100).toStringAsFixed(0)}%',
//                       style: AppTextStyles.tinyNumber(
//                         context,
//                       ).copyWith(color: color, fontWeight: FontWeight.w700),
//                     ),
//                   ],
//                 ),
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 7)),
//                 ClipRRect(
//                   borderRadius: BorderRadius.circular(
//                     ScreenScalingService.scaleSize(context, 20),
//                   ),
//                   child: LinearProgressIndicator(
//                     value: progress,
//                     minHeight: ScreenScalingService.scaleSize(context, 6),
//                     color: color,
//                     backgroundColor: colors.surfaceContainerHighest,
//                   ),
//                 ),
//                 if (remaining != null && remaining > 0) ...[
//                   SizedBox(height: ScreenScalingService.scaleSize(context, 7)),
//                   Text(
//                     '${money.format(remaining)} '
//                     'to go',
//                     style: AppTextStyles.tiny(
//                       context,
//                     ).copyWith(color: colors.onSurfaceVariant),
//                   ),
//                 ],
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _CompletedBehaviourCard extends StatelessWidget {
//   const _CompletedBehaviourCard({
//     required this.behaviorLabel,
//     required this.color,
//   });

//   final String behaviorLabel;
//   final Color color;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(ScreenScalingService.scaleSize(context, 14)),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.07),
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 14),
//         ),
//       ),
//       child: Row(
//         children: [
//           Icon(Icons.check_circle_outline, color: color),
//           SizedBox(width: ScreenScalingService.scaleSize(context, 10)),
//           Expanded(
//             child: Text(
//               'All $behaviorLabel badges '
//               'earned',
//               style: AppTextStyles.tiny(
//                 context,
//               ).copyWith(color: color, fontWeight: FontWeight.w600),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _BadgeCard extends StatelessWidget {
//   const _BadgeCard({
//     required this.badge,
//     required this.color,
//     required this.onTap,
//   });

//   final FinancialBadge badge;
//   final Color color;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     final activeColor = badge.earned ? color : colors.onSurfaceVariant;

//     return SizedBox(
//       width: ScreenScalingService.scaleSize(context, 142),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           onTap: onTap,
//           borderRadius: BorderRadius.circular(
//             ScreenScalingService.scaleSize(context, 16),
//           ),
//           child: Ink(
//             padding: EdgeInsets.all(
//               ScreenScalingService.scaleSize(context, 12),
//             ),
//             decoration: BoxDecoration(
//               color: badge.earned
//                   ? color.withValues(alpha: 0.09)
//                   : colors.surfaceContainerHighest.withValues(alpha: 0.45),
//               borderRadius: BorderRadius.circular(
//                 ScreenScalingService.scaleSize(context, 16),
//               ),
//               border: Border.all(
//                 color: badge.earned
//                     ? color.withValues(alpha: 0.42)
//                     : colors.outlineVariant,
//               ),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Container(
//                       width: ScreenScalingService.scaleSize(context, 38),
//                       height: ScreenScalingService.scaleSize(context, 38),
//                       decoration: BoxDecoration(
//                         color: activeColor.withValues(alpha: 0.13),
//                         shape: BoxShape.circle,
//                       ),
//                       child: Icon(
//                         badge.earned
//                             ? Icons.workspace_premium
//                             : Icons.lock_outline,
//                         size: ScreenScalingService.scaleSize(context, 20),
//                         color: activeColor,
//                       ),
//                     ),
//                     const Spacer(),
//                     Text(
//                       badge.levelLabel,
//                       style: AppTextStyles.tiny(context).copyWith(
//                         fontWeight: FontWeight.w700,
//                         color: activeColor,
//                       ),
//                     ),
//                   ],
//                 ),
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 10)),
//                 Text(
//                   badge.name,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                   style: AppTextStyles.small(context).copyWith(
//                     fontWeight: FontWeight.w700,
//                     color: badge.earned ? null : colors.onSurfaceVariant,
//                   ),
//                 ),
//                 const Spacer(),
//                 Row(
//                   children: [
//                     Icon(
//                       badge.earned
//                           ? Icons.check_circle_outline
//                           : Icons.lock_outline,
//                       size: ScreenScalingService.scaleSize(context, 14),
//                       color: activeColor,
//                     ),
//                     SizedBox(width: ScreenScalingService.scaleSize(context, 4)),
//                     Text(
//                       badge.earned ? 'Earned' : 'Locked',
//                       style: AppTextStyles.tiny(context).copyWith(
//                         color: activeColor,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// void _showBadgeDetails(
//   BuildContext context,
//   FinancialBadge badge,
//   Color color,
// ) {
//   showModalBottomSheet<void>(
//     context: context,
//     isScrollControlled: true,
//     showDragHandle: true,
//     builder: (context) {
//       return _BadgeDetailSheet(badge: badge, color: color);
//     },
//   );
// }

// class _BadgeDetailSheet extends StatelessWidget {
//   const _BadgeDetailSheet({required this.badge, required this.color});

//   final FinancialBadge badge;
//   final Color color;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     final money = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);

//     final achievedAt = badge.achievedAt;

//     final achieved = badge.achievedValueUsd;

//     final hasProgress =
//         !badge.earned && achieved != null && badge.thresholdUsd > 0;

//     final progress = hasProgress
//         ? (achieved / badge.thresholdUsd).clamp(0.0, 1.0)
//         : 0.0;

//     final remaining = hasProgress
//         ? (badge.thresholdUsd - achieved).clamp(0.0, double.infinity)
//         : null;

//     return SafeArea(
//       top: false,
//       child: SingleChildScrollView(
//         padding: EdgeInsets.fromLTRB(
//           ScreenScalingService.scaleSize(context, 20),
//           ScreenScalingService.scaleSize(context, 4),
//           ScreenScalingService.scaleSize(context, 20),
//           ScreenScalingService.scaleSize(context, 28),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Center(
//               child: Container(
//                 width: ScreenScalingService.scaleSize(context, 72),
//                 height: ScreenScalingService.scaleSize(context, 72),
//                 decoration: BoxDecoration(
//                   color: color.withValues(alpha: badge.earned ? 0.14 : 0.08),
//                   shape: BoxShape.circle,
//                 ),
//                 child: Icon(
//                   badge.earned ? Icons.workspace_premium : Icons.lock_outline,
//                   color: badge.earned ? color : colors.onSurfaceVariant,
//                   size: ScreenScalingService.scaleSize(context, 34),
//                 ),
//               ),
//             ),
//             SizedBox(height: ScreenScalingService.scaleSize(context, 14)),
//             Center(
//               child: Text(
//                 badge.name,
//                 textAlign: TextAlign.center,
//                 style: AppTextStyles.medium(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//             ),
//             SizedBox(height: ScreenScalingService.scaleSize(context, 6)),
//             Center(
//               child: Wrap(
//                 alignment: WrapAlignment.center,
//                 spacing: ScreenScalingService.scaleSize(context, 8),
//                 runSpacing: ScreenScalingService.scaleSize(context, 6),
//                 children: [
//                   _DetailChip(label: badge.behaviorLabel, color: color),
//                   _DetailChip(label: badge.metricLabel, color: color),
//                   _DetailChip(label: badge.levelLabel, color: color),
//                 ],
//               ),
//             ),
//             if (badge.description?.trim().isNotEmpty == true) ...[
//               SizedBox(height: ScreenScalingService.scaleSize(context, 18)),
//               Text(
//                 badge.description!,
//                 style: AppTextStyles.small(
//                   context,
//                 ).copyWith(color: colors.onSurfaceVariant),
//               ),
//             ],
//             SizedBox(height: ScreenScalingService.scaleSize(context, 20)),
//             _DetailRow(
//               label: 'Status',
//               value: badge.statusLabel,
//               emphasized: true,
//             ),
//             _DetailRow(label: 'Activity', value: badge.metricLabel),
//             _DetailRow(
//               label: 'Threshold',
//               value: money.format(badge.thresholdUsd),
//             ),
//             if (badge.earned && achieved != null)
//               _DetailRow(
//                 label: 'Achieved value',
//                 value: money.format(achieved),
//               ),
//             if (badge.earned && badge.achievementPeriodLabel != null)
//               _DetailRow(
//                 label: 'Achieved in',
//                 value: badge.achievementPeriodLabel!,
//               ),
//             if (badge.earned && achievedAt != null)
//               _DetailRow(
//                 label: 'Achieved on',
//                 value: DateFormat('dd MMM yyyy').format(achievedAt.toLocal()),
//               ),
//             if (hasProgress) ...[
//               SizedBox(height: ScreenScalingService.scaleSize(context, 18)),
//               Text(
//                 'Progress',
//                 style: AppTextStyles.small(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//               SizedBox(height: ScreenScalingService.scaleSize(context, 8)),
//               Row(
//                 children: [
//                   Expanded(
//                     child: Text(
//                       '${money.format(achieved)} '
//                       'of '
//                       '${money.format(badge.thresholdUsd)}',
//                       style: AppTextStyles.tinyNumber(context),
//                     ),
//                   ),
//                   Text(
//                     '${(progress * 100).toStringAsFixed(0)}%',
//                     style: AppTextStyles.tinyNumber(
//                       context,
//                     ).copyWith(color: color, fontWeight: FontWeight.w700),
//                   ),
//                 ],
//               ),
//               SizedBox(height: ScreenScalingService.scaleSize(context, 7)),
//               ClipRRect(
//                 borderRadius: BorderRadius.circular(
//                   ScreenScalingService.scaleSize(context, 20),
//                 ),
//                 child: LinearProgressIndicator(
//                   value: progress,
//                   minHeight: ScreenScalingService.scaleSize(context, 7),
//                   color: color,
//                   backgroundColor: colors.surfaceContainerHighest,
//                 ),
//               ),
//               if (remaining != null && remaining > 0) ...[
//                 SizedBox(height: ScreenScalingService.scaleSize(context, 7)),
//                 Text(
//                   '${money.format(remaining)} '
//                   'remaining',
//                   style: AppTextStyles.tiny(
//                     context,
//                   ).copyWith(color: colors.onSurfaceVariant),
//                 ),
//               ],
//             ],
//             if (!badge.earned && !hasProgress) ...[
//               SizedBox(height: ScreenScalingService.scaleSize(context, 16)),
//               Container(
//                 width: double.infinity,
//                 padding: EdgeInsets.all(
//                   ScreenScalingService.scaleSize(context, 14),
//                 ),
//                 decoration: BoxDecoration(
//                   color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
//                   borderRadius: BorderRadius.circular(
//                     ScreenScalingService.scaleSize(context, 14),
//                   ),
//                 ),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Icon(
//                       Icons.info_outline,
//                       size: ScreenScalingService.scaleSize(context, 18),
//                       color: colors.onSurfaceVariant,
//                     ),
//                     SizedBox(width: ScreenScalingService.scaleSize(context, 9)),
//                     Expanded(
//                       child: Text(
//                         'Reach '
//                         '${money.format(badge.thresholdUsd)} '
//                         'in '
//                         '${badge.metricLabel.toLowerCase()} '
//                         'to unlock this badge.',
//                         style: AppTextStyles.tiny(
//                           context,
//                         ).copyWith(color: colors.onSurfaceVariant),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _DetailChip extends StatelessWidget {
//   const _DetailChip({required this.label, required this.color});

//   final String label;
//   final Color color;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: EdgeInsets.symmetric(
//         horizontal: ScreenScalingService.scaleSize(context, 10),
//         vertical: ScreenScalingService.scaleSize(context, 5),
//       ),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.10),
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 20),
//         ),
//       ),
//       child: Text(
//         label,
//         style: AppTextStyles.tiny(
//           context,
//         ).copyWith(color: color, fontWeight: FontWeight.w600),
//       ),
//     );
//   }
// }

// class _DetailRow extends StatelessWidget {
//   const _DetailRow({
//     required this.label,
//     required this.value,
//     this.emphasized = false,
//   });

//   final String label;
//   final String value;
//   final bool emphasized;

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;

//     return Padding(
//       padding: EdgeInsets.symmetric(
//         vertical: ScreenScalingService.scaleSize(context, 6),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Expanded(
//             child: Text(
//               label,
//               style: AppTextStyles.tiny(
//                 context,
//               ).copyWith(color: colors.onSurfaceVariant),
//             ),
//           ),
//           SizedBox(width: ScreenScalingService.scaleSize(context, 12)),
//           Flexible(
//             child: Text(
//               value,
//               textAlign: TextAlign.end,
//               style: AppTextStyles.tinyNumber(context).copyWith(
//                 fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _BadgeColors {
//   const _BadgeColors._();

//   static Color behavior(BuildContext context, String behavior) {
//     final colors = Theme.of(context).colorScheme;

//     switch (behavior.trim().toLowerCase()) {
//       case 'saver':
//         return colors.primary;

//       case 'investor':
//         return colors.tertiary;

//       case 'shopper':
//         return colors.error;

//       case 'borrower':
//         return colors.secondary;

//       default:
//         return colors.onSurfaceVariant;
//     }
//   }
// }

// class _BadgeIcons {
//   const _BadgeIcons._();

//   static IconData behavior(String behavior) {
//     switch (behavior.trim().toLowerCase()) {
//       case 'saver':
//         return Icons.savings_outlined;

//       case 'investor':
//         return Icons.trending_up;

//       case 'shopper':
//         return Icons.shopping_bag_outlined;

//       case 'borrower':
//         return Icons.account_balance_outlined;

//       default:
//         return Icons.workspace_premium_outlined;
//     }
//   }
// }
