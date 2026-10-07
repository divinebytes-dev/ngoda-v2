import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/kyc/user_verification_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_document.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycDocumentsScreen extends StatelessWidget {
  const KycDocumentsScreen({super.key, required this.documents});

  final UserVerificationDocuments documents;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Verification Documents', onClose: context.pop),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.md,
                  spacing.md,
                  spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _VerificationSummary(documents: documents),

                    SizedBox(height: spacing.lg),

                    Text(
                      'Submitted Documents',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.sm),

                    _DocumentCard(
                      title: 'ID Front',
                      icon: Icons.badge_outlined,
                      document: documents.idFront,
                    ),

                    SizedBox(height: spacing.sm),

                    _DocumentCard(
                      title: 'ID Back',
                      icon: Icons.badge_outlined,
                      document: documents.idBack,
                    ),

                    SizedBox(height: spacing.sm),

                    _DocumentCard(
                      title: 'Proof of Address',
                      icon: Icons.home_outlined,
                      document: documents.proofOfAddress,
                    ),

                    SizedBox(height: spacing.sm),

                    _DocumentCard(
                      title: 'Selfie',
                      icon: Icons.face_outlined,
                      document: documents.selfie,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationSummary extends StatelessWidget {
  const _VerificationSummary({required this.documents});

  final UserVerificationDocuments documents;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final submitted = documents.documents.length;

    const required = 4;

    final status = documents.verificationStatus?.trim() ?? '';

    final statusLabel = status.isEmpty
        ? 'Not available'
        : _formatStatus(status);

    final statusColor = _statusColor(context, status);

    return Container(
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
          Row(
            children: [
              Container(
                width: spacing.xxl,
                height: spacing.xxl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document Verification',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      '$submitted of $required '
                      'documents submitted',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.md),

          Divider(height: spacing.xs, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.md),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Overall Status',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),

              SizedBox(width: spacing.md),

              _StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.title,
    required this.icon,
    required this.document,
  });

  final String title;
  final IconData icon;
  final UserVerificationDocument? document;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final submitted = document != null;

    final fileName = document?.fileName?.trim() ?? '';

    final status = document?.status?.trim() ?? '';

    final uploadedAt = document?.uploadedAt;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        onTap: !submitted
            ? null
            : () {
                context.push('/compliance/kyc/document', extra: document);
              },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: spacing.xxl,
                height: spacing.xxl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: submitted
                      ? colorScheme.primary.withValues(alpha: 0.10)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(
                  icon,
                  size: iconSize.medium,
                  color: submitted
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.50),
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    if (submitted) ...[
                      Text(
                        fileName.isEmpty ? 'Document submitted' : fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),

                      SizedBox(height: spacing.sm),

                      Row(
                        children: [
                          _StatusBadge(
                            label: status.isEmpty
                                ? 'Unknown'
                                : _formatStatus(status),
                            color: _statusColor(context, status),
                          ),

                          if (uploadedAt != null) ...[
                            SizedBox(width: spacing.sm),

                            Expanded(
                              child: Text(
                                _formatDate(uploadedAt),
                                textAlign: TextAlign.right,
                                style: AppTextStyles.tiny(
                                  context,
                                ).copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ] else
                      Text(
                        'Not submitted',
                        style: AppTextStyles.tiny(context).copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.60,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              if (submitted) ...[
                SizedBox(width: spacing.sm),

                Icon(
                  Icons.chevron_right,
                  size: iconSize.medium,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Text(
        label,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');

  final month = date.month.toString().padLeft(2, '0');

  return '$day/$month/${date.year}';
}

String _formatStatus(String value) {
  var status = value.trim();

  if (status.contains('.')) {
    status = status.split('.').last;
  }

  status = status.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) =>
        '${match.group(1)} '
        '${match.group(2)}',
  );

  status = status.replaceAll('_', ' ');

  if (status.isEmpty) {
    return 'Unknown';
  }

  return status
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

Color _statusColor(BuildContext context, String value) {
  final status = value.trim().toLowerCase().replaceAll('_', ' ');

  switch (status) {
    case 'verified':
    case 'approved':
      return AppColors.success;

    case 'pending':
    case 'uploaded':
    case 'pending review':
    case 'under review':
      return AppColors.warning;

    case 'rejected':
    case 'failed':
    case 'expired':
      return AppColors.error;

    default:
      return context.colorScheme.primary;
  }
}
