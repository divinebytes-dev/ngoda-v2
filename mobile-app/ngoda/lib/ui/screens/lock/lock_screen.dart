import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/biometric_service.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/pin_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const int _pinLength = 4;

  String _input = '';
  String? _error;

  bool _biometricsAvailable = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();

    _initializeBiometrics();
  }

  Future<void> _initializeBiometrics() async {
    final available = await BiometricService.isAvailable();

    if (!mounted) {
      return;
    }

    setState(() {
      _biometricsAvailable = available;
    });

    if (available) {
      await _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) {
      return;
    }

    setState(() {
      _authenticating = true;
      _error = null;
    });

    final success = await BiometricService.authenticate();

    if (!mounted) {
      return;
    }

    setState(() {
      _authenticating = false;
    });

    if (!success) {
      return;
    }

    ref.read(authProvider.notifier).unlock();
  }

  void _onKeyTap(String value) {
    if (_input.length >= _pinLength) {
      return;
    }

    setState(() {
      _input += value;
      _error = null;
    });

    if (_input.length == _pinLength) {
      _validatePin();
    }
  }

  void _onDelete() {
    if (_input.isEmpty) {
      return;
    }

    setState(() {
      _input = _input.substring(0, _input.length - 1);

      _error = null;
    });
  }

  Future<void> _validatePin() async {
    final hive = ref.read(hiveServiceProvider);

    final savedPin = hive.getItem<String>(HiveBoxName.auth, 'pin').result;

    if (savedPin != null && PinService.verifyPin(_input, savedPin)) {
      ref.read(authProvider.notifier).unlock();

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _input = '';
      _error = 'Incorrect PIN';
    });
  }

  Future<void> _logout() async {
    await ref
        .read(authProvider.notifier)
        .logout('Session expired. Please login again.');
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Scaffold(
      backgroundColor: context.theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.margin),
          child: Column(
            children: [
              const Spacer(),

              Icon(
                Icons.lock_outline,
                size: iconSize.large,
                color: colorScheme.primary,
              ),

              SizedBox(height: spacing.md),

              Text(
                'Unlock',
                style: AppTextStyles.large(context).copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),

              SizedBox(height: spacing.sm),

              Text(
                'Enter your PIN',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),

              SizedBox(height: spacing.lg),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  return _PinDot(filled: index < _input.length);
                }),
              ),

              SizedBox(height: spacing.sm),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _error == null
                    ? SizedBox(height: spacing.md)
                    : Text(
                        _error!,
                        key: ValueKey(_error),
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(color: colorScheme.error),
                      ),
              ),

              const Spacer(),

              _PinKeypad(
                biometricsAvailable: _biometricsAvailable,
                authenticating: _authenticating,
                onKeyTap: _onKeyTap,
                onDelete: _onDelete,
                onBiometric: _authenticate,
              ),

              SizedBox(height: spacing.lg),

              TextButton(
                onPressed: _logout,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius.borderRadius),
                  ),
                ),
                child: Text(
                  'Logout',
                  style: AppTextStyles.small(context).copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              SizedBox(height: spacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDot extends StatelessWidget {
  final bool filled;

  const _PinDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: filled ? spacing.md : spacing.sm,
      height: filled ? spacing.md : spacing.sm,
      margin: EdgeInsets.symmetric(horizontal: spacing.xs),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? colorScheme.primary
            : colorScheme.primary.withValues(alpha: 0.2),
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  final bool biometricsAvailable;
  final bool authenticating;
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDelete;
  final VoidCallback onBiometric;

  const _PinKeypad({
    required this.biometricsAvailable,
    required this.authenticating,
    required this.onKeyTap,
    required this.onDelete,
    required this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        _KeypadRow(
          children: [
            _NumberKey(value: '1', onTap: onKeyTap),
            _NumberKey(value: '2', onTap: onKeyTap),
            _NumberKey(value: '3', onTap: onKeyTap),
          ],
        ),

        SizedBox(height: spacing.md),

        _KeypadRow(
          children: [
            _NumberKey(value: '4', onTap: onKeyTap),
            _NumberKey(value: '5', onTap: onKeyTap),
            _NumberKey(value: '6', onTap: onKeyTap),
          ],
        ),

        SizedBox(height: spacing.md),

        _KeypadRow(
          children: [
            _NumberKey(value: '7', onTap: onKeyTap),
            _NumberKey(value: '8', onTap: onKeyTap),
            _NumberKey(value: '9', onTap: onKeyTap),
          ],
        ),

        SizedBox(height: spacing.md),

        _KeypadRow(
          children: [
            _BiometricKey(
              available: biometricsAvailable,
              authenticating: authenticating,
              onTap: onBiometric,
            ),
            _NumberKey(value: '0', onTap: onKeyTap),
            _DeleteKey(onTap: onDelete),
          ],
        ),
      ],
    );
  }
}

class _KeypadRow extends StatelessWidget {
  final List<Widget> children;

  const _KeypadRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: children,
    );
  }
}

class _NumberKey extends StatelessWidget {
  final String value;
  final ValueChanged<String> onTap;

  const _NumberKey({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _KeypadButton(
      onTap: () {
        onTap(value);
      },
      child: Text(
        value,
        style: AppTextStyles.medium(context).copyWith(
          color: context.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BiometricKey extends StatelessWidget {
  final bool available;
  final bool authenticating;
  final VoidCallback onTap;

  const _BiometricKey({
    required this.available,
    required this.authenticating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    if (!available) {
      return const _KeypadPlaceholder();
    }

    return _KeypadButton(
      onTap: authenticating ? null : onTap,
      subtle: true,
      child: Icon(
        Icons.fingerprint,
        size: iconSize.large,
        color: authenticating
            ? colorScheme.primary.withValues(alpha: 0.4)
            : colorScheme.primary,
      ),
    );
  }
}

class _DeleteKey extends StatelessWidget {
  final VoidCallback onTap;

  const _DeleteKey({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _KeypadButton(
      onTap: onTap,
      subtle: true,
      child: Icon(
        Icons.backspace_outlined,
        size: context.iconSize.medium,
        color: context.colorScheme.primary,
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool subtle;

  const _KeypadButton({
    required this.onTap,
    required this.child,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final size = spacing.buttonHeight + spacing.lg;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.primary.withValues(alpha: subtle ? 0.05 : 0.08),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _KeypadPlaceholder extends StatelessWidget {
  const _KeypadPlaceholder();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final size = spacing.buttonHeight + spacing.lg;

    return SizedBox(width: size, height: size);
  }
}
