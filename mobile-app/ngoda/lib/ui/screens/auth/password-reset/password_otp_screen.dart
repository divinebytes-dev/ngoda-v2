import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class ResetPasswordOtpScreen extends ConsumerStatefulWidget {
  final String phone;

  const ResetPasswordOtpScreen({super.key, required this.phone});

  @override
  ConsumerState<ResetPasswordOtpScreen> createState() =>
      _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState
    extends ConsumerState<ResetPasswordOtpScreen> {
  final TextEditingController otpCtrl = TextEditingController();

  bool isValid = false;

  @override
  void dispose() {
    otpCtrl.dispose();

    super.dispose();
  }

  void _onOtpChanged(String value) {
    final otp = value.trim();

    final valid = RegExp(r'^\d{6}$').hasMatch(otp);

    if (valid == isValid) {
      return;
    }

    setState(() {
      isValid = valid;
    });
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();

    final otp = otpCtrl.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      return;
    }

    try {
      await ref
          .read(authProvider.notifier)
          .verifyPasswordResetOtp(phone: widget.phone, otp: otp);

      if (!mounted) {
        return;
      }

      /*
       * OTP verification establishes the
       * temporary authenticated Supabase
       * recovery session.
       */
      context.go('/new-password');
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<void> _resendCode() async {
    FocusScope.of(context).unfocus();

    try {
      await ref
          .read(authProvider.notifier)
          .requestPasswordReset(identifier: widget.phone);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'A new verification code has been sent.',
      );
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
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              ViewHeader(
                title: 'Verify Code',
                onClose: () {
                  context.pop();
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
                          'Enter verification code',
                          style: AppTextStyles.large(context),
                        ),

                        SizedBox(height: spacing.sm),

                        Text(
                          'Enter the 6-digit code sent to '
                          '${widget.phone}.',
                          style: AppTextStyles.small(context),
                        ),

                        SizedBox(height: spacing.lg),

                        InputField(
                          controller: otpCtrl,
                          placeholder: 'Verification code',
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: _onOtpChanged,
                          onSubmitted: (_) {
                            if (isValid && !state.isLoading) {
                              _verifyOtp();
                            }
                          },
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

                        AppButton(
                          text: 'Verify',
                          isProcessing: state.isLoading,
                          onPressed: isValid && !state.isLoading
                              ? _verifyOtp
                              : null,
                        ),

                        SizedBox(height: spacing.sm),

                        Center(
                          child: TextButton(
                            onPressed: state.isLoading ? null : _resendCode,
                            child: Text(
                              'Resend code',
                              style: AppTextStyles.small(
                                context,
                              ).copyWith(color: colorScheme.primary),
                            ),
                          ),
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
    );
  }
}
