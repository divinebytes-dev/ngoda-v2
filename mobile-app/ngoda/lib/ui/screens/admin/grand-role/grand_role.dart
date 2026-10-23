import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/admin/admin_dashboard.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GrantUserRoleScreen extends ConsumerStatefulWidget {
  const GrantUserRoleScreen({super.key});

  @override
  ConsumerState<GrantUserRoleScreen> createState() {
    return _GrantUserRoleScreenState();
  }
}

class _GrantUserRoleScreenState extends ConsumerState<GrantUserRoleScreen> {
  static const List<String> _roles = ['MINTER_ROLE', 'BURNER_ROLE'];

  ActiveBlockchain? _selectedBlockchain;
  String? _selectedRole;

  bool _isReady = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(adminTransactionsProvider.notifier).reset();

      setState(() {
        _isReady = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final isLoading = ref.watch(
      adminTransactionsProvider.select((state) => state.isLoading),
    );

    final dashboardAsync = ref.watch(adminDashboardProvider);

    return PopScope(
      canPop: !isLoading,
      child: Scaffold(
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
                  title: 'Grant Token Role',
                  onClose: _closeScreen,
                ),
              ),
              Expanded(
                child: !_isReady
                    ? const Center(child: CircularProgressIndicator())
                    : dashboardAsync.when(
                        loading: () {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        error: (error, stackTrace) {
                          return _buildDashboardError();
                        },
                        data: (response) {
                          final dashboard = response.result;

                          if (dashboard == null) {
                            return _buildDashboardError();
                          }

                          return _buildForm(dashboard);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardError() {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unable to load active blockchains.',
              textAlign: TextAlign.center,
              style: AppTextStyles.small(
                context,
              ).copyWith(color: colorScheme.error),
            ),
            SizedBox(height: spacing.md),
            AppButton(
              text: 'Retry',
              onPressed: () {
                ref.invalidate(adminDashboardProvider);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AdminDashboard dashboard) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(adminTransactionsProvider);

    final blockchains = dashboard.sortedActiveBlockchains;

    // Resolve the selection against the current dashboard list.
    // A removed or changed network must be selected again.
    ActiveBlockchain? selectedBlockchain;

    for (final blockchain in blockchains) {
      if (blockchain == _selectedBlockchain) {
        selectedBlockchain = blockchain;
        break;
      }
    }

    final canSubmit =
        selectedBlockchain != null &&
        _roles.contains(_selectedRole) &&
        !state.isLoading;

    final blockchainForSubmission = selectedBlockchain;
    final roleForSubmission = _selectedRole;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.all(spacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(radius.cardRadius),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (blockchains.isEmpty) ...[
                  Text(
                    'No active blockchains are available.',
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(color: colorScheme.error),
                  ),
                  SizedBox(height: spacing.md),
                  AppButton(
                    text: 'Refresh Blockchains',
                    isDisabled: state.isLoading,
                    onPressed: () {
                      if (state.isLoading) {
                        return;
                      }

                      ref.invalidate(adminDashboardProvider);
                    },
                  ),
                ] else ...[
                  AbsorbPointer(
                    absorbing: state.isLoading,
                    child: AppSearchDropdownField<ActiveBlockchain>(
                      selected: selectedBlockchain,
                      values: blockchains,
                      hint: 'Blockchain',
                      displayText: (blockchain) {
                        return blockchain.displayName;
                      },
                      filter: (blockchain, query) {
                        return blockchain.name.toLowerCase().contains(query) ||
                            blockchain.code.toLowerCase().contains(query) ||
                            blockchain.networkName.toLowerCase().contains(
                              query,
                            );
                      },
                      onSelect: (blockchain) {
                        setState(() {
                          _selectedBlockchain = blockchain;
                        });
                      },
                    ),
                  ),
                ],
                SizedBox(height: spacing.md),
                AbsorbPointer(
                  absorbing: state.isLoading,
                  child: AppSearchDropdownField<String>(
                    selected: _selectedRole,
                    values: _roles,
                    hint: 'Blockchain Role',
                    displayText: (role) {
                      return role;
                    },
                    filter: (role, query) {
                      return role.toLowerCase().contains(query);
                    },
                    onSelect: (role) {
                      setState(() {
                        _selectedRole = role;
                      });
                    },
                  ),
                ),
                SizedBox(height: spacing.md),
                Text(
                  'The role will be granted to the treasury wallet '
                  'configured for the selected blockchain.',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
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

          // Actions remain outside the input container.
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
                  isDisabled: !canSubmit,
                  isProcessing: state.isLoading,
                  onPressed: !canSubmit
                      ? null
                      : () {
                          _handleGrantRole(
                            blockchain: blockchainForSubmission!,
                            role: roleForSubmission!,
                          );
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleGrantRole({
    required ActiveBlockchain blockchain,
    required String role,
  }) async {
    FocusScope.of(context).unfocus();

    if (ref.read(adminTransactionsProvider).isLoading) {
      return;
    }

    if (!_roles.contains(role)) {
      return;
    }

    try {
      await ref
          .read(adminTransactionsProvider.notifier)
          .grandRole(role: role, blockchainCode: blockchain.code);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message:
            '$role granted successfully on '
            '${blockchain.displayName}.',
      );

      if (!mounted) {
        return;
      }

      ref.read(adminTransactionsProvider.notifier).reset();

      setState(() {
        _selectedBlockchain = null;
        _selectedRole = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  void _closeScreen() {
    if (!mounted || ref.read(adminTransactionsProvider).isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    ref.read(adminTransactionsProvider.notifier).reset();

    context.pop();
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';

// import 'package:ngoda/services/dialog_service.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
// import 'package:ngoda/ui/widgets/app_button.dart';
// import 'package:ngoda/ui/widgets/app_dropdown_field.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class GrantUserRoleScreen extends ConsumerStatefulWidget {
//   const GrantUserRoleScreen({super.key});

//   @override
//   ConsumerState<GrantUserRoleScreen> createState() =>
//       _GrantUserRoleScreenState();
// }

// class _GrantUserRoleScreenState extends ConsumerState<GrantUserRoleScreen> {
//   static const List<String> _roles = ['MINTER_ROLE', 'BURNER_ROLE'];

//   @override
//   void initState() {
//     super.initState();

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) {
//         return;
//       }

//       ref.read(adminTransactionsProvider.notifier).reset();
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final state = ref.watch(adminTransactionsProvider);

//     final notifier = ref.read(adminTransactionsProvider.notifier);

//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             Padding(
//               padding: EdgeInsets.fromLTRB(
//                 spacing.md,
//                 spacing.sm,
//                 spacing.md,
//                 0,
//               ),
//               child: ViewHeader(
//                 title: 'Grant User Role',
//                 onClose: _closeScreen,
//               ),
//             ),

//             Expanded(
//               child: SingleChildScrollView(
//                 padding: EdgeInsets.fromLTRB(
//                   spacing.md,
//                   spacing.md,
//                   spacing.md,
//                   spacing.lg,
//                 ),
//                 keyboardDismissBehavior:
//                     ScrollViewKeyboardDismissBehavior.onDrag,
//                 child: Container(
//                   width: double.infinity,
//                   padding: EdgeInsets.all(spacing.md),
//                   decoration: BoxDecoration(
//                     color: colorScheme.surface,
//                     borderRadius: BorderRadius.circular(radius.cardRadius),
//                     border: Border.all(color: colorScheme.outlineVariant),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       AppDropdownField<String>(
//                         selected: state.role,
//                         values: _roles,
//                         hint: 'Blockchain Role',
//                         labelBuilder: (role) {
//                           return role;
//                         },
//                         onSelect: (role) {
//                           notifier.updateBlockchainRole(role);
//                         },
//                       ),

//                       if (state.error != null) ...[
//                         SizedBox(height: spacing.md),

//                         Container(
//                           width: double.infinity,
//                           padding: EdgeInsets.all(spacing.md),
//                           decoration: BoxDecoration(
//                             color: colorScheme.errorContainer,
//                             borderRadius: BorderRadius.circular(
//                               radius.borderRadius,
//                             ),
//                           ),
//                           child: Text(
//                             state.error!,
//                             style: TextStyle(
//                               color: colorScheme.onErrorContainer,
//                             ),
//                           ),
//                         ),
//                       ],

//                       SizedBox(height: spacing.lg),

//                       Row(
//                         children: [
//                           Expanded(
//                             child: AppButton(
//                               text: 'Cancel',
//                               isPrimary: false,
//                               isDisabled: state.isLoading,
//                               onPressed: _closeScreen,
//                             ),
//                           ),

//                           SizedBox(width: spacing.sm),

//                           Expanded(
//                             child: AppButton(
//                               text: 'Grant Role',
//                               isProcessing: state.isLoading,
//                               onPressed: !state.isValid || state.isLoading
//                                   ? null
//                                   : _handleGrantRole,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _handleGrantRole() async {
//     try {
//       FocusScope.of(context).unfocus();

//       final state = ref.read(adminTransactionsProvider);

//       final notifier = ref.read(adminTransactionsProvider.notifier);

//       await notifier.grandRole(role: state.role!);

//       if (!mounted) {
//         return;
//       }

//       await DialogService.success(
//         context,
//         message: 'Blockchain role granted successfully',
//       );

//       if (!mounted) {
//         return;
//       }

//       notifier.reset();
//     } catch (e) {
//       if (!mounted) {
//         return;
//       }

//       await DialogService.error(context, message: e.toString());
//     }
//   }

//   void _closeScreen() {
//     if (!mounted) {
//       return;
//     }

//     ref.read(adminTransactionsProvider.notifier).reset();

//     context.pop();
//   }
// }
