import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

GamificationNotificationType _notificationType(
  GamificationNotification notification,
) {
  return switch (notification.notificationType.trim().toLowerCase()) {
    'points_earned' => GamificationNotificationType.pointsEarned,

    'level_up' => GamificationNotificationType.levelUp,

    'level_down' => GamificationNotificationType.levelDown,

    'badge_awarded' => GamificationNotificationType.badgeAwarded,

    'challenge_completed' => GamificationNotificationType.challengeCompleted,

    'reward_available' => GamificationNotificationType.rewardAvailable,

    _ => GamificationNotificationType.unknown,
  };
}

GamificationIntensity gamificationIntensityFor(
  GamificationNotification notification,
) {
  final notificationType = _notificationType(notification);

  if (notificationType == GamificationNotificationType.levelUp ||
      notificationType == GamificationNotificationType.badgeAwarded) {
    return GamificationIntensity.epic;
  }

  if (notificationType == GamificationNotificationType.challengeCompleted ||
      notificationType == GamificationNotificationType.rewardAvailable) {
    return GamificationIntensity.large;
  }

  if (notification.points < 25) {
    return GamificationIntensity.tiny;
  }

  if (notification.points < 100) {
    return GamificationIntensity.small;
  }

  if (notification.points < 500) {
    return GamificationIntensity.medium;
  }

  if (notification.points < 2000) {
    return GamificationIntensity.large;
  }

  return GamificationIntensity.epic;
}

abstract final class GamificationMotion {
  static const tiny = Duration(milliseconds: 850);

  static const standard = Duration(milliseconds: 1250);

  static const milestone = Duration(milliseconds: 1700);

  static const epic = Duration(milliseconds: 2200);

  static const reduced = Duration(milliseconds: 650);
}

abstract final class GamificationColors {
  static const gold = Color(0xFFFFC928);

  static const darkGold = Color(0xFFB56B00);

  static const orange = Color(0xFFFF8A00);

  static const cream = Color(0xFFFFF5CC);

  static const purple = Color(0xFF7657FF);

  static const success = Color(0xFF19B76A);

  static const foreground = Color(0xFF372600);

  static const secondaryForeground = Color(0xFF6F5A25);
}

class GamificationCelebrationOverlay extends StatefulWidget {
  final GamificationNotification notification;

  final Duration? duration;

  final VoidCallback onPresented;

  final VoidCallback onComplete;

  const GamificationCelebrationOverlay({
    super.key,
    required this.notification,
    this.duration,
    required this.onPresented,
    required this.onComplete,
  });

  @override
  State<GamificationCelebrationOverlay> createState() {
    return _GamificationCelebrationOverlayState();
  }
}

class _GamificationCelebrationOverlayState
    extends State<GamificationCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  Timer? _reducedMotionTimer;

  bool _started = false;

  bool _completed = false;

  GamificationIntensity get _intensity {
    return gamificationIntensityFor(widget.notification);
  }

  bool get _isMajor {
    return _intensity == GamificationIntensity.large ||
        _intensity == GamificationIntensity.epic;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_started) {
      return;
    }

    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onPresented();
      }
    });

    if (MediaQuery.disableAnimationsOf(context)) {
      _reducedMotionTimer = Timer(
        widget.duration ?? GamificationMotion.reduced,
        _complete,
      );

      return;
    }

    _controller =
        AnimationController(
            vsync: this,
            duration: widget.duration ?? _durationFor(_intensity),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _complete();
            }
          })
          ..forward();
  }

  Duration _durationFor(GamificationIntensity intensity) {
    return switch (intensity) {
      GamificationIntensity.tiny => GamificationMotion.tiny,

      GamificationIntensity.small ||
      GamificationIntensity.medium => GamificationMotion.standard,

      GamificationIntensity.large => GamificationMotion.milestone,

      GamificationIntensity.epic => GamificationMotion.epic,
    };
  }

  void _complete() {
    if (_completed) {
      return;
    }

    _completed = true;

    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null || MediaQuery.disableAnimationsOf(context)) {
      return _buildFrame(context, 0.62);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return _buildFrame(context, controller.value);
      },
    );
  }

  Widget _buildFrame(BuildContext context, double value) {
    final entranceProgress = (value / 0.22).clamp(0.0, 1.0);

    final entrance = Curves.easeOutBack.transform(entranceProgress);

    final entranceOpacity = Curves.easeOut.transform(
      (value / 0.12).clamp(0.0, 1.0),
    );

    final travelProgress = Curves.easeInOutCubic.transform(
      ((value - 0.10) / 0.78).clamp(0.0, 1.0),
    );

    final exit = Curves.easeInCubic.transform(
      ((value - 0.82) / 0.18).clamp(0.0, 1.0),
    );

    final opacity = (entranceOpacity * (1 - exit)).clamp(0.0, 1.0);

    final screenHeight = MediaQuery.sizeOf(context).height;

    final verticalOffset =
        -screenHeight * (_isMajor ? 0.28 : 0.32) * travelProgress;

    final celebrationOffset = Offset(0, verticalOffset);

    return IgnorePointer(
      child: Material(
        color: _isMajor
            ? Colors.black.withValues(alpha: 0.28 * opacity)
            : Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isMajor)
              Transform.translate(
                offset: celebrationOffset,
                child: _CelebrationRays(progress: value, opacity: opacity),
              ),

            if (_intensity != GamificationIntensity.tiny)
              Transform.translate(
                offset: celebrationOffset,
                child: _SparkBurst(
                  progress: value,
                  opacity: opacity,
                  particleCount: _particleCount(_intensity),
                ),
              ),

            Align(
              alignment: Alignment.center,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: celebrationOffset,
                  child: Transform.scale(
                    scale: entrance,
                    child: _RewardCard(
                      notification: widget.notification,
                      intensity: _intensity,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _particleCount(GamificationIntensity intensity) {
    return switch (intensity) {
      GamificationIntensity.tiny => 0,
      GamificationIntensity.small => 8,
      GamificationIntensity.medium => 14,
      GamificationIntensity.large => 20,
      GamificationIntensity.epic => 28,
    };
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();

    _controller?.dispose();

    super.dispose();
  }
}

class _RewardCard extends StatelessWidget {
  final GamificationNotification notification;

  final GamificationIntensity intensity;

  const _RewardCard({required this.notification, required this.intensity});

  GamificationNotificationType get _type {
    return _notificationType(notification);
  }

  bool get _isLevelUp {
    return _type == GamificationNotificationType.levelUp;
  }

  bool get _isAchievement {
    return _type == GamificationNotificationType.badgeAwarded ||
        _type == GamificationNotificationType.challengeCompleted;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final radius = context.radius;

    final iconSize = context.iconSize;

    final large =
        intensity == GamificationIntensity.large ||
        intensity == GamificationIntensity.epic;

    final title = notification.title ?? _fallbackTitle();

    final subtitle = notification.subtitle;

    final horizontalPadding = large ? spacing.lg : spacing.md;

    final verticalPadding = large ? spacing.lg : spacing.md;

    return Container(
      constraints: BoxConstraints(
        maxWidth: ScreenScalingService.scaleSize(context, large ? 330 : 270),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, GamificationColors.cream],
        ),
        borderRadius: BorderRadius.circular(large ? radius.xl : radius.lg),
        border: Border.all(
          color: GamificationColors.gold,
          width: large ? 2.4 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: GamificationColors.gold.withValues(alpha: 0.42),
            blurRadius: ScreenScalingService.scaleSize(
              context,
              large ? 38 : 22,
            ),
            spreadRadius: ScreenScalingService.scaleSize(
              context,
              large ? 5 : 2,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon(),
            size: large ? iconSize.xl * 2 : iconSize.xl,
            color: _isLevelUp
                ? GamificationColors.purple
                : GamificationColors.darkGold,
          ),

          SizedBox(height: large ? spacing.md : spacing.sm),

          Text(
            title,
            textAlign: TextAlign.center,
            style:
                (large
                        ? AppTextStyles.veryLarge(context)
                        : AppTextStyles.medium(context))
                    .copyWith(
                      color: GamificationColors.foreground,
                      fontWeight: FontWeight.w800,
                    ),
          ),

          if (notification.points > 0 && !_isLevelUp) ...[
            SizedBox(height: spacing.xs),

            Text(
              '+${notification.points}',
              style: AppTextStyles.largeNumber(context).copyWith(
                color: GamificationColors.darkGold,
                fontWeight: FontWeight.w900,
              ),
            ),

            Text(
              'POINTS',
              style: AppTextStyles.tiny(context).copyWith(
                color: GamificationColors.darkGold,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ],

          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            SizedBox(height: spacing.sm),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.small(context).copyWith(
                color: GamificationColors.secondaryForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fallbackTitle() {
    if (_isLevelUp) {
      return 'Level up!';
    }

    if (_isAchievement) {
      return 'Achievement unlocked';
    }

    return 'Reward earned';
  }

  IconData _icon() {
    return switch (_type) {
      GamificationNotificationType.levelUp => Icons.workspace_premium_rounded,

      GamificationNotificationType.levelDown => Icons.shield_outlined,

      GamificationNotificationType.badgeAwarded => Icons.military_tech_rounded,

      GamificationNotificationType.challengeCompleted =>
        Icons.emoji_events_rounded,

      GamificationNotificationType.rewardAvailable =>
        Icons.card_giftcard_rounded,

      _ => Icons.auto_awesome_rounded,
    };
  }
}

class _SparkBurst extends StatelessWidget {
  final double progress;

  final double opacity;

  final int particleCount;

  const _SparkBurst({
    required this.progress,
    required this.opacity,
    required this.particleCount,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final centre = Offset(size.width / 2, size.height / 2);

    final burstProgress = Curves.easeOutCubic.transform(
      ((progress - 0.08) / 0.7).clamp(0.0, 1.0),
    );

    return Stack(
      children: List.generate(particleCount, (index) {
        final angle = (math.pi * 2 * index) / particleCount;

        final alternating = index.isEven ? 1.0 : 0.72;

        final baseRadius = ScreenScalingService.scaleSize(
          context,
          72 + (index % 5) * 17,
        );

        final radius = baseRadius * burstProgress * alternating;

        final point =
            centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);

        final particleSize = ScreenScalingService.scaleSize(
          context,
          index % 4 == 0 ? 18 : 12,
        );

        return Positioned(
          left: point.dx - particleSize / 2,
          top: point.dy - particleSize / 2,
          child: Opacity(
            opacity:
                opacity *
                math.sin(math.pi * burstProgress.clamp(0.0, 1.0)).abs(),
            child: Transform.rotate(
              angle: angle + progress * math.pi,
              child: Icon(
                index % 3 == 0 ? Icons.star_rounded : Icons.auto_awesome,
                size: particleSize,
                color: index.isEven
                    ? GamificationColors.gold
                    : GamificationColors.orange,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CelebrationRays extends StatelessWidget {
  final double progress;

  final double opacity;

  const _CelebrationRays({required this.progress, required this.opacity});

  @override
  Widget build(BuildContext context) {
    final raySize = ScreenScalingService.scaleSize(context, 310);

    return Center(
      child: Transform.rotate(
        angle: progress * 0.35,
        child: Container(
          width: raySize,
          height: raySize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                GamificationColors.gold.withValues(alpha: 0),
                GamificationColors.gold.withValues(alpha: 0.22 * opacity),
                GamificationColors.gold.withValues(alpha: 0),
                GamificationColors.orange.withValues(alpha: 0.18 * opacity),
                GamificationColors.gold.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
