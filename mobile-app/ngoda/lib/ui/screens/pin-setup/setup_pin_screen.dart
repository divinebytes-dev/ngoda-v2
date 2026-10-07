import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/pin_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  static const int _pinLength = 4;

  String firstEntry = '';
  String confirmEntry = '';

  bool isConfirming = false;
  bool isSaving = false;

  String? error;

  String get currentInput {
    return isConfirming ? confirmEntry : firstEntry;
  }

  void _onKeyTap(String value) {
    if (isSaving || currentInput.length >= _pinLength) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      error = null;

      if (!isConfirming) {
        firstEntry += value;

        if (firstEntry.length == _pinLength) {
          Future.delayed(const Duration(milliseconds: 180), () {
            if (!mounted) {
              return;
            }

            setState(() {
              isConfirming = true;
            });
          });
        }

        return;
      }

      confirmEntry += value;

      if (confirmEntry.length == _pinLength) {
        Future.microtask(_savePin);
      }
    });
  }

  void _onDelete() {
    if (isSaving) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      error = null;

      if (isConfirming && confirmEntry.isNotEmpty) {
        confirmEntry = confirmEntry.substring(0, confirmEntry.length - 1);

        return;
      }

      if (!isConfirming && firstEntry.isNotEmpty) {
        firstEntry = firstEntry.substring(0, firstEntry.length - 1);
      }
    });
  }

  Future<void> _savePin() async {
    if (isSaving) {
      return;
    }

    if (firstEntry != confirmEntry) {
      HapticFeedback.heavyImpact();

      setState(() {
        error = 'PINs do not match';
        confirmEntry = '';
      });

      return;
    }

    setState(() {
      isSaving = true;
      error = null;
    });

    try {
      final hive = ref.read(hiveServiceProvider);

      final hashedPin = PinService.hashPin(firstEntry);

      await hive.saveItem(HiveBoxName.auth, 'pin', hashedPin);

      if (!mounted) {
        return;
      }

      context.go('/user-dashboard');
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      setState(() {
        isSaving = false;
        confirmEntry = '';
        error = 'Unable to save PIN. Please try again.';
      });
    }
  }

  Widget _buildDot(BuildContext context, int index) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final filled = index < currentInput.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: filled ? spacing.md : spacing.sm,
      height: filled ? spacing.md : spacing.sm,
      margin: EdgeInsets.symmetric(horizontal: spacing.xs),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? colorScheme.primary
            : colorScheme.primary.withValues(alpha: 0.18),
      ),
    );
  }

  Widget _buildKey(BuildContext context, String value) {
    final colorScheme = context.colorScheme;

    return Expanded(
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isSaving
                ? null
                : () {
                    _onKeyTap(value);
                  },
            child: Ink(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.08),
              ),
              child: Center(
                child: Text(
                  value,
                  style: AppTextStyles.largeNumber(context).copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDelete(BuildContext context) {
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    return Expanded(
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isSaving ? null : _onDelete,
            child: Ink(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.05),
              ),
              child: Center(
                child: Icon(
                  Icons.backspace_outlined,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyKey() {
    return const Expanded(child: SizedBox.shrink());
  }

  Widget _buildKeyboardRow(BuildContext context, List<String> values) {
    final spacing = context.spacing;

    return Row(
      children: [
        _buildKey(context, values[0]),

        SizedBox(width: spacing.lg),

        _buildKey(context, values[1]),

        SizedBox(width: spacing.lg),

        _buildKey(context, values[2]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.xxl),
          child: Column(
            children: [
              const Spacer(),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  isConfirming ? 'Confirm PIN' : 'Create PIN',
                  key: ValueKey(isConfirming),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.large(context).copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              SizedBox(height: spacing.sm),

              Text(
                isConfirming
                    ? 'Re-enter your secure PIN'
                    : 'Create a secure 4-digit PIN',
                textAlign: TextAlign.center,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),

              SizedBox(height: spacing.xl),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pinLength,
                  (index) => _buildDot(context, index),
                ),
              ),

              SizedBox(height: spacing.sm),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: error == null
                    ? SizedBox(
                        key: const ValueKey('no-error'),
                        height: spacing.lg,
                      )
                    : Text(
                        error!,
                        key: ValueKey(error),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(color: colorScheme.error),
                      ),
              ),

              SizedBox(height: spacing.xxl),

              Column(
                children: [
                  _buildKeyboardRow(context, const ['1', '2', '3']),

                  SizedBox(height: spacing.lg),

                  _buildKeyboardRow(context, const ['4', '5', '6']),

                  SizedBox(height: spacing.lg),

                  _buildKeyboardRow(context, const ['7', '8', '9']),

                  SizedBox(height: spacing.lg),

                  Row(
                    children: [
                      _buildEmptyKey(),

                      SizedBox(width: spacing.lg),

                      _buildKey(context, '0'),

                      SizedBox(width: spacing.lg),

                      _buildDelete(context),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              if (isSaving)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing.md),
                  child: CircularProgressIndicator(color: colorScheme.primary),
                )
              else
                SizedBox(height: spacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
