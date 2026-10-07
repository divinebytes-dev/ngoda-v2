import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_display_card.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:ngoda/ui/enums/enums.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController identifierCtrl = TextEditingController();

  bool isValid = false;

  @override
  void dispose() {
    identifierCtrl.dispose();

    super.dispose();
  }

  void _onIdentifierChanged(String value) {
    final valid = value.trim().isNotEmpty;

    if (valid == isValid) {
      return;
    }

    setState(() {
      isValid = valid;
    });
  }

  Future<void> _requestPasswordReset() async {
    FocusScope.of(context).unfocus();

    final identifier = identifierCtrl.text.trim();

    if (identifier.isEmpty) {
      return;
    }

    try {
      final method = await ref
          .read(authProvider.notifier)
          .requestPasswordReset(identifier: identifier);

      if (!mounted) {
        return;
      }

      switch (method) {
        case PasswordResetMethod.email:
          await DialogService.success(
            context,
            message:
                'Password reset instructions have been sent. '
                'Please check your email.',
          );

          break;

        case PasswordResetMethod.phone:
          context.push('/reset-password-otp', extra: identifier);

          break;
      }
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
                  title: 'Forgot Password',
                  onClose: () {
                    context.pop();
                  },
                ),

                SizedBox(height: spacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        const _PasswordResetInfoCard(),

                        SizedBox(height: spacing.lg),

                        AppDisplayCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Account',
                                style: AppTextStyles.large(context),
                              ),

                              SizedBox(height: spacing.lg),

                              InputField(
                                controller: identifierCtrl,
                                placeholder: 'Email / phone',
                                keyboardType: TextInputType.emailAddress,
                                onChanged: _onIdentifierChanged,
                              ),

                              if (state.error != null) ...[
                                SizedBox(height: spacing.sm),

                                Text(
                                  state.error!,
                                  style: AppTextStyles.small(
                                    context,
                                  ).copyWith(color: colorScheme.error),
                                ),
                              ],
                              SizedBox(height: spacing.lg),

                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      text: 'Back to Login',
                                      isPrimary: false,
                                      onPressed: state.isLoading
                                          ? null
                                          : () {
                                              context.go('/login');
                                            },
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Reset Password',
                                      isProcessing: state.isLoading,
                                      isDisabled: !isValid || state.isLoading,
                                      onPressed: !isValid || state.isLoading
                                          ? null
                                          : _requestPasswordReset,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _PasswordResetInfoCard extends StatelessWidget {
  const _PasswordResetInfoCard();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return AppDisplayCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_reset_outlined,
            size: iconSize.medium,
            color: colorScheme.primary,
          ),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Text(
              'Enter the email address or phone number '
              'you use to log in. We will send instructions '
              'to reset your password.',
              style: AppTextStyles.small(context),
            ),
          ),
        ],
      ),
    );
  }
}
