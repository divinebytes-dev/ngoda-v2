import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/admin/user_role.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ChangeUserRoleScreen extends ConsumerWidget {
  const ChangeUserRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.spacing.md,
                context.spacing.sm,
                context.spacing.md,
                0,
              ),
              child: ViewHeader(
                title: 'Change User Role',
                onClose: () {
                  context.pop();
                },
              ),
            ),

            Expanded(
              child: dashboardAsync.when(
                loading: () => const AppLoader(),

                error: (error, stackTrace) {
                  return AppErrorState(
                    message: error.toString(),
                    buttonText: 'Retry',
                    onAction: () {
                      ref.invalidate(adminDashboardProvider);
                    },
                  );
                },

                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      message: response.error!,
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final dashboard = response.result;

                  if (dashboard == null) {
                    return AppErrorState(
                      message: 'Failed to load user roles',
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final roles = dashboard.roles;

                  if (roles.isEmpty) {
                    return AppErrorState(
                      message: 'No user roles available',
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  return EditUserRole(roles: roles);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditUserRole extends ConsumerStatefulWidget {
  final List<UserRole> roles;

  const EditUserRole({super.key, required this.roles});

  @override
  ConsumerState<EditUserRole> createState() => _EditUserRoleState();
}

class _EditUserRoleState extends ConsumerState<EditUserRole> {
  final emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(adminTransactionsProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    emailCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(adminTransactionsProvider);

    final notifier = ref.read(adminTransactionsProvider.notifier);

    // final roleNames = widget.roles.map((role) => role.name).toList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.md,
          spacing.md,
          spacing.lg,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputField(
                controller: emailCtrl,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                onChanged: notifier.updateEmail,
              ),

              SizedBox(height: spacing.md),

              AppSearchDropdownField<UserRole>(
                selected: widget.roles
                    .where((role) => role.name == state.role)
                    .firstOrNull,
                values: widget.roles,
                hint: 'Search Role',
                displayText: (role) {
                  return role.name.toUpperCase();
                },
                filter: (role, query) {
                  return role.name.toLowerCase().contains(query);
                },
                onSelect: (role) {
                  notifier.updateRole(role.name);
                },
              ),

              if (state.error != null) ...[
                SizedBox(height: spacing.md),

                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(spacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(radius.borderRadius),
                  ),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
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
                      onPressed: _closeScreen,
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Expanded(
                    child: AppButton(
                      text: 'Update Role',
                      isProcessing: state.isLoading,
                      onPressed: !state.isValid || state.isLoading
                          ? null
                          : _handleChangeRole,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleChangeRole() async {
    try {
      FocusScope.of(context).unfocus();

      final state = ref.read(adminTransactionsProvider);

      final notifier = ref.read(adminTransactionsProvider.notifier);

      await notifier.changeRole(email: state.email!, role: state.role!);

      ref.invalidate(adminDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'User role updated successfully',
      );

      if (!mounted) {
        return;
      }

      emailCtrl.clear();
      notifier.reset();
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    emailCtrl.clear();

    ref.read(adminTransactionsProvider.notifier).reset();

    context.pop();
  }
}
