import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_reset_password_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final currentPasswordCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  @override
  void dispose() {
    currentPasswordCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userResetPasswordProvider);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final newPassword = newPasswordCtrl.text;
    final confirmPassword = confirmPasswordCtrl.text;

    final passwordsMatch =
        confirmPassword.isEmpty || newPassword == confirmPassword;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: EdgeInsets.all(spacing.margin),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Change Password',
                  onClose: () {
                    context.pop();
                  },
                ),

                SizedBox(height: spacing.md),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: context.theme.cardColor,
                            borderRadius: BorderRadius.circular(
                              radius.cardRadius,
                            ),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.09,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Password',
                                style: AppTextStyles.medium(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),

                              SizedBox(height: spacing.xs),

                              Text(
                                'Enter your current password and choose a new secure password.',
                                style: AppTextStyles.small(
                                  context,
                                ).copyWith(color: colorScheme.onSurfaceVariant),
                              ),

                              SizedBox(height: spacing.lg),
                              InputField(
                                controller: currentPasswordCtrl,
                                placeholder: 'Current Password',
                                keyboardType: TextInputType.text,
                                obscureText: true,
                                showPasswordToggle: true,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  _passwordChanged();
                                },
                              ),

                              SizedBox(height: spacing.md),
                              InputField(
                                controller: newPasswordCtrl,
                                placeholder: 'New Password',
                                keyboardType: TextInputType.text,
                                obscureText: true,
                                showPasswordToggle: true,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  _passwordChanged();
                                },
                              ),

                              SizedBox(height: spacing.md),

                              _PasswordStrengthHint(password: newPassword),

                              SizedBox(height: spacing.md),
                              InputField(
                                controller: confirmPasswordCtrl,
                                placeholder: 'Confirm New Password',
                                keyboardType: TextInputType.text,
                                obscureText: true,
                                showPasswordToggle: true,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  _passwordChanged();
                                },
                              ),

                              if (!passwordsMatch) ...[
                                SizedBox(height: spacing.sm),

                                Text(
                                  'Passwords do not match',
                                  style: AppTextStyles.small(
                                    context,
                                  ).copyWith(color: colorScheme.error),
                                ),
                              ],

                              if (state.error != null) ...[
                                SizedBox(height: spacing.md),

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
                                      text: 'Cancel',
                                      isPrimary: false,
                                      isDisabled: state.isLoading,
                                      onPressed: () {
                                        context.pop();
                                      },
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Change Password',
                                      isProcessing: state.isLoading,
                                      isDisabled: !_isValid || state.isLoading,
                                      onPressed: !_isValid || state.isLoading
                                          ? null
                                          : _handleChangePassword,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: spacing.lg),

                        const _SecurityInfoCard(),
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

  void _passwordChanged() {
    setState(() {});

    ref
        .read(userResetPasswordProvider.notifier)
        .changePassword(
          currentPassword: currentPasswordCtrl.text,
          newPassword: newPasswordCtrl.text,
          confirmPassword: confirmPasswordCtrl.text,
        );
  }

  bool get _isValid {
    final currentPassword = currentPasswordCtrl.text;

    final newPassword = newPasswordCtrl.text;

    final confirmPassword = confirmPasswordCtrl.text;

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      return false;
    }

    if (!_hasMinimumLength(newPassword)) {
      return false;
    }

    if (!_hasUppercase(newPassword)) {
      return false;
    }

    if (!_hasLowercase(newPassword)) {
      return false;
    }

    if (!_hasNumber(newPassword)) {
      return false;
    }

    if (!_hasSpecialCharacter(newPassword)) {
      return false;
    }

    if (newPassword != confirmPassword) {
      return false;
    }

    if (newPassword == currentPassword) {
      return false;
    }

    return true;
  }

  Future<void> _handleChangePassword() async {
    FocusScope.of(context).unfocus();

    if (!_isValid) {
      return;
    }

    try {
      await ref
          .read(userResetPasswordProvider.notifier)
          .changePassword(
            currentPassword: currentPasswordCtrl.text,
            newPassword: newPasswordCtrl.text,
            confirmPassword: confirmPasswordCtrl.text,
          );

      if (!mounted) {
        return;
      }

      final state = ref.read(userResetPasswordProvider);

      if (!state.isValid) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Password changed successfully',
      );

      if (!mounted) {
        return;
      }

      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  bool _hasMinimumLength(String password) {
    return password.length >= 8;
  }

  bool _hasUppercase(String password) {
    return RegExp(r'[A-Z]').hasMatch(password);
  }

  bool _hasLowercase(String password) {
    return RegExp(r'[a-z]').hasMatch(password);
  }

  bool _hasNumber(String password) {
    return RegExp(r'[0-9]').hasMatch(password);
  }

  bool _hasSpecialCharacter(String password) {
    return RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(password);
  }
}

class _PasswordStrengthHint extends StatelessWidget {
  final String password;

  const _PasswordStrengthHint({required this.password});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final checks = [
      _PasswordRequirement(
        label: 'At least 8 characters',
        isValid: password.length >= 8,
      ),
      _PasswordRequirement(
        label: 'One uppercase letter',
        isValid: RegExp(r'[A-Z]').hasMatch(password),
      ),
      _PasswordRequirement(
        label: 'One lowercase letter',
        isValid: RegExp(r'[a-z]').hasMatch(password),
      ),
      _PasswordRequirement(
        label: 'One number',
        isValid: RegExp(r'[0-9]').hasMatch(password),
      ),
      _PasswordRequirement(
        label: 'One special character',
        isValid: RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(password),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(context.radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password requirements',
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),

          SizedBox(height: spacing.sm),

          for (var index = 0; index < checks.length; index++) ...[
            _PasswordCheck(requirement: checks[index]),

            if (index < checks.length - 1) SizedBox(height: spacing.xs),
          ],
        ],
      ),
    );
  }
}

class _PasswordCheck extends StatelessWidget {
  final _PasswordRequirement requirement;

  const _PasswordCheck({required this.requirement});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final color = requirement.isValid
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Icon(
          requirement.isValid
              ? Icons.check_circle_outline
              : Icons.circle_outlined,
          size: iconSize.small,
          color: color,
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: Text(
            requirement.label,
            style: AppTextStyles.small(context).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SecurityInfoCard extends StatelessWidget {
  const _SecurityInfoCard();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: iconSize.medium,
            color: colorScheme.primary,
          ),

          SizedBox(width: spacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep your account secure',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  'Use a strong password that you do not use for other accounts.',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordRequirement {
  final String label;
  final bool isValid;

  const _PasswordRequirement({required this.label, required this.isValid});
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';

// import 'package:ngoda/services/dialog_service.dart';
// import 'package:ngoda/services/screen_scaling_service.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/screens/customer/details/providers/user_reset_password_provider.dart';
// import 'package:ngoda/ui/widgets/app_button.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class ResetPasswordScreen extends ConsumerStatefulWidget {
//   const ResetPasswordScreen({super.key});

//   @override
//   ConsumerState<ResetPasswordScreen> createState() =>
//       _ResetPasswordScreenState();
// }

// class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
//   final currentPasswordCtrl = TextEditingController();
//   final newPasswordCtrl = TextEditingController();
//   final confirmPasswordCtrl = TextEditingController();

//   bool showCurrentPassword = false;
//   bool showNewPassword = false;
//   bool showConfirmPassword = false;

//   @override
//   void dispose() {
//     currentPasswordCtrl.dispose();
//     newPasswordCtrl.dispose();
//     confirmPasswordCtrl.dispose();

//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final state = ref.watch(userResetPasswordProvider);

//     final spacing = ScreenScalingService.scaleSize(context, 10);

//     final spacingLg = ScreenScalingService.scaleSize(context, 20);

//     final edgeInset = ScreenScalingService.scaleSize(context, 15);

//     final radius = ScreenScalingService.scaleSize(context, 12);

//     return Scaffold(
//       body: SafeArea(
//         child: GestureDetector(
//           behavior: HitTestBehavior.translucent,
//           onTap: () {
//             FocusScope.of(context).unfocus();
//           },
//           child: Padding(
//             padding: EdgeInsets.all(edgeInset),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Change Password',
//                   onClose: () {
//                     context.pop();
//                   },
//                 ),
//                 Expanded(
//                   child: SingleChildScrollView(
//                     keyboardDismissBehavior:
//                         ScrollViewKeyboardDismissBehavior.onDrag,
//                     child: Column(
//                       children: [
//                         SizedBox(height: spacing),
//                         const _SecurityInfoCard(),
//                         SizedBox(height: spacingLg),
//                         Container(
//                           width: double.infinity,
//                           padding: EdgeInsets.all(edgeInset),
//                           decoration: BoxDecoration(
//                             color: context.theme.cardColor,
//                             borderRadius: BorderRadius.circular(radius),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: Colors.black.withValues(alpha: 0.05),
//                                 blurRadius: ScreenScalingService.scaleSize(
//                                   context,
//                                   20,
//                                 ),
//                                 offset: const Offset(0, 10),
//                               ),
//                             ],
//                           ),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 'Password',
//                                 style: Theme.of(context).textTheme.titleMedium
//                                     ?.copyWith(fontWeight: FontWeight.w600),
//                               ),
//                               SizedBox(height: spacingLg),
//                               _PasswordField(
//                                 controller: currentPasswordCtrl,
//                                 label: 'Current Password',
//                                 obscureText: !showCurrentPassword,
//                                 onToggleVisibility: () {
//                                   setState(() {
//                                     showCurrentPassword = !showCurrentPassword;
//                                   });
//                                 },
//                                 onChanged: (_) {
//                                   setState(() {});
//                                 },
//                               ),
//                               SizedBox(height: spacing),
//                               _PasswordField(
//                                 controller: newPasswordCtrl,
//                                 label: 'New Password',
//                                 obscureText: !showNewPassword,
//                                 onToggleVisibility: () {
//                                   setState(() {
//                                     showNewPassword = !showNewPassword;
//                                   });
//                                 },
//                                 onChanged: (_) {
//                                   setState(() {});
//                                 },
//                               ),
//                               SizedBox(height: spacing),
//                               _PasswordStrengthHint(
//                                 password: newPasswordCtrl.text,
//                               ),
//                               SizedBox(height: spacing),
//                               _PasswordField(
//                                 controller: confirmPasswordCtrl,
//                                 label: 'Confirm New Password',
//                                 obscureText: !showConfirmPassword,
//                                 onToggleVisibility: () {
//                                   setState(() {
//                                     showConfirmPassword = !showConfirmPassword;
//                                   });
//                                 },
//                                 onChanged: (_) {
//                                   setState(() {});
//                                 },
//                               ),
//                               if (_showPasswordMismatch) ...[
//                                 SizedBox(height: spacing),
//                                 Text(
//                                   'Passwords do not match',
//                                   style: Theme.of(context).textTheme.bodySmall
//                                       ?.copyWith(
//                                         color: Theme.of(
//                                           context,
//                                         ).colorScheme.error,
//                                       ),
//                                 ),
//                               ],
//                               if (state.error != null) ...[
//                                 SizedBox(height: spacing),
//                                 Text(
//                                   state.error!,
//                                   style: Theme.of(context).textTheme.bodySmall
//                                       ?.copyWith(
//                                         color: Theme.of(
//                                           context,
//                                         ).colorScheme.error,
//                                       ),
//                                 ),
//                               ],
//                               SizedBox(height: spacingLg),
//                               Row(
//                                 children: [
//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Cancel',
//                                       isPrimary: false,
//                                       isDisabled: state.isLoading,
//                                       onPressed: () {
//                                         context.pop();
//                                       },
//                                     ),
//                                   ),
//                                   SizedBox(width: spacing),
//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Change Password',
//                                       isProcessing: state.isLoading,
//                                       isDisabled: !_isValid || state.isLoading,
//                                       onPressed: !_isValid || state.isLoading
//                                           ? null
//                                           : _handleChangePassword,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: spacingLg),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   bool get _showPasswordMismatch {
//     final confirmPassword = confirmPasswordCtrl.text;

//     if (confirmPassword.isEmpty) {
//       return false;
//     }

//     return newPasswordCtrl.text != confirmPassword;
//   }

//   bool get _isValid {
//     final currentPassword = currentPasswordCtrl.text;

//     final newPassword = newPasswordCtrl.text;

//     final confirmPassword = confirmPasswordCtrl.text;

//     return currentPassword.isNotEmpty &&
//         _isValidPassword(newPassword) &&
//         confirmPassword.isNotEmpty &&
//         newPassword == confirmPassword &&
//         currentPassword != newPassword;
//   }

//   bool _isValidPassword(String value) {
//     return value.length >= 8 &&
//         RegExp(r'[A-Z]').hasMatch(value) &&
//         RegExp(r'[a-z]').hasMatch(value) &&
//         RegExp(r'[0-9]').hasMatch(value) &&
//         RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(value);
//   }

//   Future<void> _handleChangePassword() async {
//     FocusScope.of(context).unfocus();

//     try {
//       final notifier = ref.read(userResetPasswordProvider.notifier);

//       await notifier.changePassword(
//         currentPassword: currentPasswordCtrl.text,
//         newPassword: newPasswordCtrl.text,
//         confirmPassword: confirmPasswordCtrl.text,
//       );

//       if (!mounted) {
//         return;
//       }

//       final state = ref.read(userResetPasswordProvider);

//       if (!state.isValid) {
//         return;
//       }

//       await DialogService.success(
//         context,
//         message: 'Password changed successfully',
//       );

//       if (!mounted) {
//         return;
//       }

//       context.pop();
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       await DialogService.error(context, message: error.toString());
//     }
//   }
// }

// class _PasswordField extends StatelessWidget {
//   const _PasswordField({
//     required this.controller,
//     required this.label,
//     required this.obscureText,
//     required this.onToggleVisibility,
//     this.onChanged,
//   });

//   final TextEditingController controller;
//   final String label;
//   final bool obscureText;
//   final VoidCallback onToggleVisibility;
//   final ValueChanged<String>? onChanged;

//   @override
//   Widget build(BuildContext context) {
//     final radius = ScreenScalingService.scaleSize(context, 12);

//     return TextFormField(
//       controller: controller,
//       obscureText: obscureText,
//       enableSuggestions: false,
//       autocorrect: false,
//       textInputAction: TextInputAction.next,
//       onChanged: onChanged,
//       decoration: InputDecoration(
//         labelText: label,
//         border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
//         suffixIcon: IconButton(
//           onPressed: onToggleVisibility,
//           icon: Icon(
//             obscureText
//                 ? Icons.visibility_outlined
//                 : Icons.visibility_off_outlined,
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _PasswordStrengthHint extends StatelessWidget {
//   const _PasswordStrengthHint({required this.password});

//   final String password;

//   @override
//   Widget build(BuildContext context) {
//     final checks = [
//       _PasswordCheck(
//         label: 'At least 8 characters',
//         passed: password.length >= 8,
//       ),
//       _PasswordCheck(
//         label: 'Uppercase letter',
//         passed: RegExp(r'[A-Z]').hasMatch(password),
//       ),
//       _PasswordCheck(
//         label: 'Lowercase letter',
//         passed: RegExp(r'[a-z]').hasMatch(password),
//       ),
//       _PasswordCheck(
//         label: 'Number',
//         passed: RegExp(r'[0-9]').hasMatch(password),
//       ),
//       _PasswordCheck(
//         label: 'Special character',
//         passed: RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(password),
//       ),
//     ];

//     return Column(
//       children: checks.map((check) {
//         return Padding(
//           padding: const EdgeInsets.only(bottom: 4),
//           child: Row(
//             children: [
//               Icon(
//                 check.passed
//                     ? Icons.check_circle_outline
//                     : Icons.radio_button_unchecked,
//                 size: 16,
//                 color: check.passed ? Colors.green : Colors.grey,
//               ),
//               const SizedBox(width: 6),
//               Text(
//                 check.label,
//                 style: Theme.of(context).textTheme.bodySmall?.copyWith(
//                   color: check.passed ? Colors.green : Colors.grey,
//                 ),
//               ),
//             ],
//           ),
//         );
//       }).toList(),
//     );
//   }
// }

// class _PasswordCheck {
//   const _PasswordCheck({required this.label, required this.passed});

//   final String label;
//   final bool passed;
// }

// class _SecurityInfoCard extends StatelessWidget {
//   const _SecurityInfoCard();

//   @override
//   Widget build(BuildContext context) {
//     final padding = ScreenScalingService.scaleSize(context, 15);

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(padding),
//       decoration: BoxDecoration(
//         color: context.theme.cardColor,
//         borderRadius: BorderRadius.circular(
//           ScreenScalingService.scaleSize(context, 12),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(Icons.lock_outline),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Text(
//               'Use a strong password that you do not use on other services.',
//               style: Theme.of(context).textTheme.bodyMedium,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
