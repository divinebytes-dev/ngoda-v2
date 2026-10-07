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
import 'package:ngoda/ui/widgets/view_header.dart';

enum _ChangePinStep { current, newPin, confirm }

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  static const int _pinLength = 4;

  _ChangePinStep step = _ChangePinStep.current;

  String currentPin = '';
  String newPin = '';
  String confirmPin = '';

  bool isProcessing = false;

  String? error;

  String get currentInput {
    switch (step) {
      case _ChangePinStep.current:
        return currentPin;

      case _ChangePinStep.newPin:
        return newPin;

      case _ChangePinStep.confirm:
        return confirmPin;
    }
  }

  String get title {
    switch (step) {
      case _ChangePinStep.current:
        return 'Current PIN';

      case _ChangePinStep.newPin:
        return 'New PIN';

      case _ChangePinStep.confirm:
        return 'Confirm PIN';
    }
  }

  String get subtitle {
    switch (step) {
      case _ChangePinStep.current:
        return 'Enter your current 4-digit PIN';

      case _ChangePinStep.newPin:
        return 'Create a new secure 4-digit PIN';

      case _ChangePinStep.confirm:
        return 'Re-enter your new PIN';
    }
  }

  void _onKeyTap(String value) {
    if (isProcessing || currentInput.length >= _pinLength) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      error = null;

      switch (step) {
        case _ChangePinStep.current:
          currentPin += value;

        case _ChangePinStep.newPin:
          newPin += value;

        case _ChangePinStep.confirm:
          confirmPin += value;
      }
    });

    if (currentInput.length != _pinLength) {
      return;
    }

    switch (step) {
      case _ChangePinStep.current:
        Future.microtask(_verifyCurrentPin);

      case _ChangePinStep.newPin:
        Future.delayed(const Duration(milliseconds: 180), () {
          if (!mounted) {
            return;
          }

          setState(() {
            step = _ChangePinStep.confirm;
            error = null;
          });
        });

      case _ChangePinStep.confirm:
        Future.microtask(_saveNewPin);
    }
  }

  void _onDelete() {
    if (isProcessing) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      error = null;

      switch (step) {
        case _ChangePinStep.current:
          if (currentPin.isNotEmpty) {
            currentPin = currentPin.substring(0, currentPin.length - 1);
          }

        case _ChangePinStep.newPin:
          if (newPin.isNotEmpty) {
            newPin = newPin.substring(0, newPin.length - 1);
          }

        case _ChangePinStep.confirm:
          if (confirmPin.isNotEmpty) {
            confirmPin = confirmPin.substring(0, confirmPin.length - 1);
          }
      }
    });
  }

  Future<void> _verifyCurrentPin() async {
    if (isProcessing) {
      return;
    }

    setState(() {
      isProcessing = true;
      error = null;
    });

    try {
      final hive = ref.read(hiveServiceProvider);

      final storedPin = hive.getItem<String>(HiveBoxName.auth, 'pin').result;
      debugPrint("Stored Pin $storedPin");

      if (storedPin.toString().trim().isEmpty) {
        if (!mounted) {
          return;
        }

        HapticFeedback.heavyImpact();

        setState(() {
          currentPin = '';
          isProcessing = false;
          error = 'No security PIN is configured for this account.';
        });

        return;
      }

      final isValid = PinService.verifyPin(currentPin, storedPin.toString());

      if (!mounted) {
        return;
      }

      if (!isValid) {
        HapticFeedback.heavyImpact();

        setState(() {
          currentPin = '';
          isProcessing = false;
          error = 'Incorrect PIN';
        });

        return;
      }

      HapticFeedback.mediumImpact();

      setState(() {
        isProcessing = false;
        error = null;
        step = _ChangePinStep.newPin;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      setState(() {
        currentPin = '';
        isProcessing = false;
        error = 'Unable to verify PIN. Please try again.';
      });
    }
  }

  Future<void> _saveNewPin() async {
    if (isProcessing) {
      return;
    }

    if (newPin != confirmPin) {
      HapticFeedback.heavyImpact();

      setState(() {
        confirmPin = '';
        error = 'PINs do not match';
      });

      return;
    }

    if (newPin == currentPin) {
      HapticFeedback.heavyImpact();

      setState(() {
        newPin = '';
        confirmPin = '';
        step = _ChangePinStep.newPin;
        error = 'New PIN must be different from your current PIN';
      });

      return;
    }

    setState(() {
      isProcessing = true;
      error = null;
    });

    try {
      final hive = ref.read(hiveServiceProvider);

      final hashedPin = PinService.hashPin(newPin);

      await hive.saveItem(HiveBoxName.auth, 'pin', hashedPin);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      context.pop();
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      setState(() {
        isProcessing = false;
        confirmPin = '';
        error = 'Unable to change PIN. Please try again.';
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
            onTap: isProcessing
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
            onTap: isProcessing ? null : _onDelete,
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
              SizedBox(height: spacing.md),

              ViewHeader(
                title: 'Change PIN',
                onClose: () {
                  context.pop();
                },
              ),

              const Spacer(),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  title,
                  key: ValueKey(step),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.large(context).copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              SizedBox(height: spacing.sm),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  subtitle,
                  key: ValueKey('subtitle-$step'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
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

              if (isProcessing)
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
