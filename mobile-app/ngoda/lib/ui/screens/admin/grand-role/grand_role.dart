import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_dropdown_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GrantUserRoleScreen extends ConsumerStatefulWidget {
  const GrantUserRoleScreen({super.key});

  @override
  ConsumerState<GrantUserRoleScreen> createState() =>
      _GrantUserRoleScreenState();
}

class _GrantUserRoleScreenState extends ConsumerState<GrantUserRoleScreen> {
  static const List<String> _roles = ['MINTER_ROLE', 'BURNER_ROLE'];

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
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(adminTransactionsProvider);

    final notifier = ref.read(adminTransactionsProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                0,
              ),
              child: ViewHeader(
                title: 'Grant User Role',
                onClose: _closeScreen,
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.md,
                  spacing.md,
                  spacing.lg,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                      AppDropdownField<String>(
                        selected: state.role,
                        values: _roles,
                        hint: 'Blockchain Role',
                        labelBuilder: (role) {
                          return role;
                        },
                        onSelect: (role) {
                          notifier.updateBlockchainRole(role);
                        },
                      ),

                      if (state.error != null) ...[
                        SizedBox(height: spacing.md),

                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(
                              radius.borderRadius,
                            ),
                          ),
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                            ),
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
                              text: 'Grant Role',
                              isProcessing: state.isLoading,
                              onPressed: !state.isValid || state.isLoading
                                  ? null
                                  : _handleGrantRole,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGrantRole() async {
    try {
      FocusScope.of(context).unfocus();

      final state = ref.read(adminTransactionsProvider);

      final notifier = ref.read(adminTransactionsProvider.notifier);

      await notifier.grandRole(role: state.role!);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Blockchain role granted successfully',
      );

      if (!mounted) {
        return;
      }

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

    ref.read(adminTransactionsProvider.notifier).reset();

    context.pop();
  }
}
