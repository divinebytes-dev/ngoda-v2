import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/input_field.dart';

class ApproveCreditAgentScreen extends ConsumerStatefulWidget {
  const ApproveCreditAgentScreen({super.key});

  @override
  ConsumerState<ApproveCreditAgentScreen> createState() =>
      _ApproveCreditAgentScreenState();
}

class _ApproveCreditAgentScreenState
    extends ConsumerState<ApproveCreditAgentScreen> {
  final emailCtrl = TextEditingController();

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final state = ref.watch(treasuryTransactionProvider);

    final notifier = ref.read(treasuryTransactionProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              children: [
                SizedBox(height: spacing.xl),
                Text(
                  'Agent Funding',
                  style: AppTextStyles.large(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  'Approve Credit Agent',
                  style: AppTextStyles.small(context).copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: spacing.xl),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        InputField(
                          controller: emailCtrl,
                          placeholder: 'Credit agent email',
                          keyboardType: TextInputType.emailAddress,
                          onChanged: notifier.updateCreditAgentEmail,
                        ),
                        SizedBox(height: spacing.xl),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                text: 'Cancel',
                                isPrimary: false,
                                isDisabled: state.isLoading,
                                onPressed: () {
                                  if (!context.mounted) {
                                    return;
                                  }

                                  emailCtrl.clear();

                                  ref
                                      .read(
                                        treasuryTransactionProvider.notifier,
                                      )
                                      .reset();

                                  context.pop();
                                },
                              ),
                            ),
                            SizedBox(width: spacing.sm),
                            Expanded(
                              child: AppButton(
                                text: 'Approve Agent',
                                isProcessing: state.isLoading,
                                onPressed: !state.isValid || state.isLoading
                                    ? null
                                    : handleAgentApproval,
                              ),
                            ),
                          ],
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

  Future<void> handleAgentApproval() async {
    try {
      final confirmed = await confirmApproval(ref);

      if (confirmed != true) {
        return;
      }

      if (!context.mounted) {
        return;
      }

      final notifier = ref.read(treasuryTransactionProvider.notifier);

      await notifier.approveCreditAgent();

      ref.invalidate(treasuryDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Credit Agent Approval Successful',
      );

      if (!mounted) {
        return;
      }

      emailCtrl.clear();

      ref.read(treasuryTransactionProvider.notifier).reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> confirmApproval(WidgetRef ref) {
    final state = ref.read(treasuryTransactionProvider);

    return DialogService.confirm(
      context,
      title: 'Credit Agent Approval',
      message: 'Approve credit agent ${state.email}',
    );
  }
}
