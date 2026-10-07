import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/password_validator_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_display_card.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final TextEditingController newPasswordCtrl = TextEditingController();

  final TextEditingController confirmPasswordCtrl = TextEditingController();

  bool isValid = false;
  String? validationError;

  @override
  void dispose() {
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();

    super.dispose();
  }

  void _validate() {
    final password = newPasswordCtrl.text;

    final confirmPassword = confirmPasswordCtrl.text;

    String? error;

    /*
     * Do not show a password error until
     * the user starts entering a password.
     */
    if (password.isNotEmpty) {
      error = PasswordValidatorService.validate(password);
    }

    /*
     * Only show mismatch after the user has
     * started entering the confirmation.
     */
    if (error == null &&
        confirmPassword.isNotEmpty &&
        password != confirmPassword) {
      error = 'Passwords do not match';
    }

    final valid =
        PasswordValidatorService.isValid(password) &&
        confirmPassword.isNotEmpty &&
        password == confirmPassword;

    if (valid == isValid && error == validationError) {
      return;
    }

    setState(() {
      isValid = valid;
      validationError = error;
    });
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();

    final password = newPasswordCtrl.text;

    final confirmPassword = confirmPasswordCtrl.text;

    final passwordError = PasswordValidatorService.validate(password);

    if (passwordError != null) {
      setState(() {
        isValid = false;
        validationError = passwordError;
      });

      return;
    }

    if (password != confirmPassword) {
      setState(() {
        isValid = false;
        validationError = 'Passwords do not match';
      });

      return;
    }

    try {
      await ref
          .read(authProvider.notifier)
          .completePasswordReset(newPassword: password);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Your password has been changed successfully.',
      );

      if (!mounted) {
        return;
      }

      context.go('/login');
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final colorScheme = context.colorScheme;

    final state = ref.watch(authProvider);

    final error = validationError ?? state.error;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'New Password',
                  onClose: () {
                    context.go('/login');
                  },
                ),

                SizedBox(height: spacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: AppDisplayCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Create a new password',
                            style: AppTextStyles.large(context),
                          ),

                          SizedBox(height: spacing.sm),

                          Text(
                            PasswordValidatorService.requirements,
                            style: AppTextStyles.small(context),
                          ),

                          SizedBox(height: spacing.lg),

                          InputField(
                            controller: newPasswordCtrl,
                            placeholder: 'New Password',
                            keyboardType: TextInputType.text,
                            obscureText: true,
                            showPasswordToggle: true,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) {
                              _validate();
                            },
                          ),

                          /*
                           * Standard spacing between
                           * consecutive input fields.
                           */
                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: confirmPasswordCtrl,
                            placeholder: 'Confirm Password',
                            keyboardType: TextInputType.text,
                            obscureText: true,
                            showPasswordToggle: true,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) {
                              _validate();
                            },
                            onSubmitted: (_) {
                              if (isValid && !state.isLoading) {
                                _resetPassword();
                              }
                            },
                          ),

                          if (error != null) ...[
                            SizedBox(height: spacing.sm),

                            Text(
                              error,
                              style: AppTextStyles.small(
                                context,
                              ).copyWith(color: colorScheme.error),
                            ),
                          ],

                          SizedBox(height: spacing.lg),

                          AppButton(
                            text: 'Change Password',
                            isProcessing: state.isLoading,
                            isDisabled: !isValid || state.isLoading,
                            onPressed: isValid && !state.isLoading
                                ? _resetPassword
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
