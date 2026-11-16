import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/core/providers/user_engagement_service_provider.dart';
import 'package:ngoda/services/app_update_service.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/more_tile.dart';

class EngagementSettingsSection extends ConsumerStatefulWidget {
  const EngagementSettingsSection({super.key});

  @override
  ConsumerState<EngagementSettingsSection> createState() {
    return _EngagementSettingsSectionState();
  }
}

class _EngagementSettingsSectionState
    extends ConsumerState<EngagementSettingsSection> {
  bool? _enabled;
  bool _busy = false;
  Timer? _reviewTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());

    // Check only after the settings section has settled on screen.
    _reviewTimer = Timer(const Duration(seconds: 2), () {
      if (!_canPromptForReview()) {
        return;
      }

      unawaited(
        ref
            .read(userEngagementServiceProvider)
            .maybeRequestReview(shouldPrompt: _canPromptForReview),
      );
    });
  }

  bool _canPromptForReview() {
    if (!mounted || _busy) {
      return false;
    }

    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }

    if (ref.read(authProvider).isLocked) {
      return false;
    }

    return ModalRoute.of(context)?.isCurrent == true;
  }

  Future<void> _load() async {
    try {
      final enabled = await ref
          .read(userEngagementServiceProvider)
          .remindersEnabled();

      if (!mounted) {
        return;
      }

      setState(() {
        _enabled = enabled;
      });
    } catch (_) {
      if (mounted) {
        _error();
      }
    }
  }

  Future<void> _setRemindersEnabled(bool value) async {
    setState(() {
      _busy = true;
    });

    try {
      await ref.read(userEngagementServiceProvider).setRemindersEnabled(value);

      if (!mounted) {
        return;
      }

      await _load();
    } catch (_) {
      if (mounted) {
        _error();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _rateApp() async {
    _reviewTimer?.cancel();

    try {
      await ref.read(userEngagementServiceProvider).openStoreListing();
    } catch (_) {
      if (mounted) {
        _error();
      }
    }
  }

  void _error() {
    SnackbarService.error(
      context,
      'Unable to complete this action. Please try again.',
    );
  }

  @override
  void dispose() {
    _reviewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: Text('App reminders', style: AppTextStyles.small(context)),
            subtitle: Text(
              'A reminder after three days away. '
              'System notification permission is required.',
              style: AppTextStyles.tiny(context),
            ),
            value: _enabled ?? false,
            onChanged: _enabled == null || _busy ? null : _setRemindersEnabled,
          ),
          MoreTile(
            icon: Icons.star_outline,
            label: 'Rate Ngoda',
            onTap: _rateApp,
          ),
          MoreTile(
            icon: Icons.system_update,
            label: 'Check for updates',
            onTap: () {
              _reviewTimer?.cancel();

              unawaited(
                ref.read(appUpdateServiceProvider).checkUpdates(context),
              );
            },
          ),
        ],
      ),
    );
  }
  // Widget build(BuildContext context) {
  //   // final spacing = context.spacing;
  //   final radius = context.radius;
  //   final colorScheme = context.colorScheme;
  //   return Column(
  //     mainAxisSize: MainAxisSize.min,
  //     children: [
  //       SwitchListTile(
  //         title: Text('App reminders', style: AppTextStyles.small(context)),
  //         subtitle: Text(
  //           'A reminder after three days away. '
  //           'System notification permission is required.',
  //           style: AppTextStyles.tiny(context),
  //         ),
  //         value: _enabled ?? false,
  //         onChanged: _enabled == null || _busy ? null : _setRemindersEnabled,
  //       ),
  //       ListTile(
  //         leading: Container(
  //           padding: EdgeInsets.all(context.spacing.sm),
  //           decoration: BoxDecoration(
  //             color: colorScheme.primary.withValues(alpha: 0.1),
  //             borderRadius: BorderRadius.circular(radius.borderRadius),
  //           ),
  //           child: Icon(
  //             Icons.star_outline,
  //             size: context.iconSize.medium,
  //             color: colorScheme.primary,
  //           ),
  //         ),
  //         title: Text('Rate Ngoda', style: AppTextStyles.small(context)),
  //         trailing: Icon(
  //           Icons.chevron_right,
  //           size: context.iconSize.medium,
  //           color: colorScheme.onSurfaceVariant,
  //         ),
  //         onTap: _rateApp,
  //       ),
  //       ListTile(
  //         leading: Container(
  //           padding: EdgeInsets.all(context.spacing.sm),
  //           decoration: BoxDecoration(
  //             color: colorScheme.primary.withValues(alpha: 0.1),
  //             borderRadius: BorderRadius.circular(radius.borderRadius),
  //           ),
  //           child: Icon(
  //             Icons.system_update,
  //             size: context.iconSize.medium,
  //             color: colorScheme.primary,
  //           ),
  //         ),
  //         title: Text('Check for updates', style: AppTextStyles.small(context)),
  //         trailing: Icon(
  //           Icons.chevron_right,
  //           size: context.iconSize.medium,
  //           color: colorScheme.onSurfaceVariant,
  //         ),
  //         onTap: () {
  //           _reviewTimer?.cancel();
  //           unawaited(ref.read(appUpdateServiceProvider).checkUpdates(context));
  //         },
  //       ),
  //     ],
  //   );
  // }
}
