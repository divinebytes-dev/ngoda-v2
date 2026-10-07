import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/compliance/providers/kyc_review_decision_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycDecisionScreen extends ConsumerStatefulWidget {
  final UserDetails review;

  const KycDecisionScreen({super.key, required this.review});

  @override
  ConsumerState<KycDecisionScreen> createState() => _KycDecisionScreenState();
}

class _KycDecisionScreenState extends ConsumerState<KycDecisionScreen> {
  final TextEditingController _commentsController = TextEditingController();

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final notifier = ref.read(kycReviewDecisionProvider.notifier);

    try {
      await notifier.submitDecision(userId: widget.review.userId);

      if (!mounted) {
        return;
      }

      final state = ref.read(kycReviewDecisionProvider);

      if (!state.isSuccess) {
        return;
      }

      await DialogService.success(
        context,
        message: 'KYC review submitted successfully',
      );

      if (!mounted) {
        return;
      }

      notifier.reset();

      context.pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  void _close() {
    ref.read(kycReviewDecisionProvider.notifier).reset();

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kycReviewDecisionProvider);

    final notifier = ref.read(kycReviewDecisionProvider.notifier);

    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final requiresReason =
        state.decision == KycReviewDecision.reject ||
        state.decision == KycReviewDecision.requestChanges;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.sm,
                  spacing.md,
                  0,
                ),
                child: ViewHeader(title: 'Review Decision', onClose: _close),
              ),

              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    spacing.md,
                    spacing.md,
                    spacing.md,
                    spacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReviewSummaryCard(review: widget.review),

                      SizedBox(height: spacing.lg),

                      Text(
                        'Decision',
                        style: AppTextStyles.medium(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),

                      SizedBox(height: spacing.sm),

                      _DecisionOption(
                        title: 'Approve',
                        description:
                            'Verify this customer and approve their KYC submission.',
                        icon: Icons.verified_outlined,
                        color: AppColors.success,
                        selected: state.decision == KycReviewDecision.approve,
                        enabled: !state.isLoading,
                        onTap: () {
                          notifier.selectDecision(KycReviewDecision.approve);
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      _DecisionOption(
                        title: 'Request Changes',
                        description:
                            'Return the submission to the customer for corrections.',
                        icon: Icons.edit_note_outlined,
                        color: AppColors.warning,
                        selected:
                            state.decision == KycReviewDecision.requestChanges,
                        enabled: !state.isLoading,
                        onTap: () {
                          notifier.selectDecision(
                            KycReviewDecision.requestChanges,
                          );
                        },
                      ),

                      SizedBox(height: spacing.sm),

                      _DecisionOption(
                        title: 'Reject',
                        description: 'Reject the customer KYC submission.',
                        icon: Icons.cancel_outlined,
                        color: AppColors.error,
                        selected: state.decision == KycReviewDecision.reject,
                        enabled: !state.isLoading,
                        onTap: () {
                          notifier.selectDecision(KycReviewDecision.reject);
                        },
                      ),

                      SizedBox(height: spacing.lg),

                      Text(
                        requiresReason ? 'Reason' : 'Comments',
                        style: AppTextStyles.medium(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),

                      SizedBox(height: spacing.xs),

                      Text(
                        requiresReason
                            ? 'A reason is required for this decision.'
                            : 'You can optionally add comments for this review.',
                        style: AppTextStyles.small(context),
                      ),

                      SizedBox(height: spacing.sm),

                      TextField(
                        controller: _commentsController,
                        enabled: !state.isLoading,
                        minLines: 4,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        onChanged: notifier.updateComments,
                        decoration: InputDecoration(
                          hintText: requiresReason
                              ? 'Enter the reason...'
                              : 'Add comments...',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(radius.md),
                          ),
                        ),
                      ),

                      if (state.error != null) ...[
                        SizedBox(height: spacing.sm),

                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.sm),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(radius.md),
                            border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: iconSize.medium,
                                color: colorScheme.error,
                              ),

                              SizedBox(width: spacing.sm),

                              Expanded(
                                child: Text(
                                  state.error!,
                                  style: AppTextStyles.small(
                                    context,
                                  ).copyWith(color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      SizedBox(height: spacing.lg),

                      AppButton(
                        text: 'Submit Decision',
                        isProcessing: state.isLoading,
                        isDisabled: !state.isValid || state.isLoading,
                        onPressed: !state.isValid || state.isLoading
                            ? null
                            : _submit,
                      ),
                    ],
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

class _ReviewSummaryCard extends StatelessWidget {
  final UserDetails review;

  const _ReviewSummaryCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final details = review.kycDetails;
    final documents = review.verificationDocuments;

    final kycStatus = details.status?.trim().isNotEmpty == true
        ? _formatValue(details.status!)
        : 'Unknown';

    final documentCount = documents.documents.length;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  size: iconSize.large,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KYC Review',
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      'Review the submission before making a decision.',
                      style: AppTextStyles.small(context),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.md),

          Divider(color: colorScheme.outlineVariant),

          SizedBox(height: spacing.sm),

          _SummaryRow(label: 'KYC Status', value: kycStatus),

          SizedBox(height: spacing.sm),

          _SummaryRow(label: 'Documents', value: documentCount.toString()),

          if (documents.verificationStatus?.trim().isNotEmpty == true) ...[
            SizedBox(height: spacing.sm),

            _SummaryRow(
              label: 'Document Status',
              value: _formatValue(documents.verificationStatus!),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),

        SizedBox(width: spacing.md),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _DecisionOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DecisionOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final borderColor = selected ? color : colorScheme.outlineVariant;

    final backgroundColor = selected
        ? color.withValues(alpha: 0.08)
        : context.theme.cardColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(radius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(radius.md),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(icon, size: iconSize.large, color: color),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(description, style: AppTextStyles.small(context)),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: iconSize.medium,
                color: selected ? color : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatValue(String value) {
  final formatted = value.trim().replaceAll('_', ' ');

  if (formatted.isEmpty) {
    return 'Unknown';
  }

  return formatted
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
