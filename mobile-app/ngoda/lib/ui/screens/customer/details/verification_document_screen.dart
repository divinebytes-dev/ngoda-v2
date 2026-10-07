import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ngoda/core/providers/image_picker_service_provider.dart';
import 'package:ngoda/data_models/kyc/user_verification_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_document.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_document_verification_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class VerificationDocumentsScreen extends ConsumerStatefulWidget {
  final UserVerificationDocuments? verificationDocuments;

  const VerificationDocumentsScreen({super.key, this.verificationDocuments});

  @override
  ConsumerState<VerificationDocumentsScreen> createState() =>
      _VerificationDocumentsScreenState();
}

class _VerificationDocumentsScreenState
    extends ConsumerState<VerificationDocumentsScreen> {
  late List<_VerificationDocumentItem> documents;

  final Map<VerificationDocumentType, XFile> _selectedFiles = {};

  @override
  void initState() {
    super.initState();

    _initialiseDocuments();
  }

  void _initialiseDocuments() {
    final verificationDocuments = widget.verificationDocuments;

    documents = [
      _VerificationDocumentItem(
        type: VerificationDocumentType.nationalIdFront,
        document: verificationDocuments?.idFront,
      ),
      _VerificationDocumentItem(
        type: VerificationDocumentType.nationalIdBack,
        document: verificationDocuments?.idBack,
      ),
      _VerificationDocumentItem(
        type: VerificationDocumentType.proofOfAddress,
        document: verificationDocuments?.proofOfAddress,
      ),
      _VerificationDocumentItem(
        type: VerificationDocumentType.selfie,
        document: verificationDocuments?.selfie,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userDocumentVerificationProvider);

    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.margin),
          child: Column(
            children: [
              ViewHeader(
                title: 'Verification Documents',
                onClose: () {
                  context.pop();
                },
              ),

              SizedBox(height: spacing.md),

              _VerificationInfoCard(
                status: widget.verificationDocuments?.verificationStatus,
              ),

              if (state.error != null) ...[
                SizedBox(height: spacing.md),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.error!,
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(color: colorScheme.error),
                  ),
                ),
              ],

              SizedBox(height: spacing.lg),

              Expanded(
                child: ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: documents.length,
                  separatorBuilder: (context, index) {
                    return SizedBox(height: spacing.md);
                  },
                  itemBuilder: (context, index) {
                    final item = documents[index];

                    final selectedFile = _selectedFiles[item.type];

                    final isLoading =
                        state.isLoading &&
                        state.verificationDocumentType == item.type;

                    return _DocumentCard(
                      document: item,
                      selectedFile: selectedFile,
                      isLoading: isLoading,
                      onCamera: () {
                        _takePhoto(item.type);
                      },
                      onGallery: () {
                        _pickFromGallery(item.type);
                      },
                      onSave: selectedFile == null
                          ? null
                          : () {
                              _saveDocument(index, selectedFile);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto(VerificationDocumentType type) async {
    try {
      final imagePickerService = ref.read(imagePickerServiceProvider);

      final selectedFile = await imagePickerService.takePhoto();

      if (selectedFile == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFiles[type] = selectedFile;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<void> _pickFromGallery(VerificationDocumentType type) async {
    try {
      final imagePickerService = ref.read(imagePickerServiceProvider);

      final selectedFile = await imagePickerService.pickFromGallery();

      if (selectedFile == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFiles[type] = selectedFile;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<void> _saveDocument(int index, XFile selectedFile) async {
    final item = documents[index];

    try {
      final notifier = ref.read(userDocumentVerificationProvider.notifier);

      await notifier.saveDocument(type: item.type, file: selectedFile);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFiles.remove(item.type);
      });

      ref.invalidate(userDetailsProvider);

      await DialogService.success(
        context,
        message: '${item.type.displayName} saved successfully',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }
}

class _VerificationInfoCard extends StatelessWidget {
  final String? status;

  const _VerificationInfoCard({this.status});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final verificationStatus = _parseStatus(status);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.edgeInsert),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(radius.cardRadius),
            ),
            child: Icon(
              Icons.verified_user_outlined,
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
                  'Verification Documents',
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  'Upload the documents required to verify your identity. '
                  'Documents may be reviewed before your KYC status is updated.',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),

                if (status != null && status!.trim().isNotEmpty) ...[
                  SizedBox(height: spacing.md),

                  _StatusBadge(status: verificationStatus),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static VerificationDocumentStatus _parseStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return VerificationDocumentStatus.notSubmitted;
    }

    return VerificationDocumentStatus.fromJson(value);
  }
}

class _DocumentCard extends StatelessWidget {
  final _VerificationDocumentItem document;

  final XFile? selectedFile;

  final bool isLoading;

  final VoidCallback onCamera;

  final VoidCallback onGallery;

  final VoidCallback? onSave;

  const _DocumentCard({
    required this.document,
    required this.selectedFile,
    required this.isLoading,
    required this.onCamera,
    required this.onGallery,
    required this.onSave,
  });

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
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.edgeInsert),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius.borderRadius),
                  color: colorScheme.primary.withValues(alpha: 0.08),
                ),
                child: Icon(
                  _documentIcon,
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
                      document.type.displayName,
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    _StatusBadge(status: document.status),
                  ],
                ),
              ),

              if (isLoading)
                SizedBox(
                  width: iconSize.medium,
                  height: iconSize.medium,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),

          if (selectedFile != null) ...[
            SizedBox(height: spacing.md),

            Divider(color: colorScheme.outlineVariant),

            SizedBox(height: spacing.md),

            _SelectedImagePreview(file: selectedFile!),

            SizedBox(height: spacing.md),

            _DetailRow(label: 'Selected', value: selectedFile!.name),
          ] else if (document.document != null) ...[
            SizedBox(height: spacing.md),

            Divider(color: colorScheme.outlineVariant),

            SizedBox(height: spacing.md),

            if (document.document!.fileName != null)
              _DetailRow(label: 'File', value: document.document!.fileName!),

            if (document.document!.uploadedAt != null) ...[
              SizedBox(height: spacing.md),

              _DetailRow(
                label: 'Uploaded',
                value: _formatDate(document.document!.uploadedAt!),
              ),
            ],

            if (document.document!.verifiedAt != null) ...[
              SizedBox(height: spacing.md),

              _DetailRow(
                label: 'Verified',
                value: _formatDate(document.document!.verifiedAt!),
              ),
            ],
          ],

          SizedBox(height: spacing.md),

          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onCamera,
            icon: Icon(Icons.camera_alt_outlined, size: iconSize.small),
            label: Text(
              'Camera',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onGallery,
            icon: Icon(Icons.photo_library_outlined, size: iconSize.small),
            label: Text(
              'Gallery',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: FilledButton.icon(
            onPressed: isLoading ? null : onSave,
            icon: Icon(Icons.save_outlined, size: iconSize.small),
            label: Text(
              'Save',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  IconData get _documentIcon {
    switch (document.type) {
      case VerificationDocumentType.nationalIdFront:
      case VerificationDocumentType.nationalIdBack:
      case VerificationDocumentType.driversLicenseFront:
      case VerificationDocumentType.driversLicenseBack:
        return Icons.badge_outlined;

      case VerificationDocumentType.passport:
        return Icons.menu_book_outlined;

      case VerificationDocumentType.proofOfAddress:
        return Icons.home_work_outlined;

      case VerificationDocumentType.selfie:
        return Icons.face_outlined;

      case VerificationDocumentType.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }
}

class _SelectedImagePreview extends StatelessWidget {
  final XFile file;

  const _SelectedImagePreview({required this.file});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: Image.file(
        File(file.path),
        width: double.infinity,
        height: spacing.xxxxl * 3,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: double.infinity,
            height: spacing.xxxxl * 2,
            alignment: Alignment.center,
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.insert_drive_file_outlined,
              size: iconSize.large,
              color: colorScheme.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final VerificationDocumentStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final color = _color(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        color: color.withValues(alpha: 0.10),
      ),
      child: Text(
        status.displayName,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _color(BuildContext context) {
    final colorScheme = context.colorScheme;

    switch (status) {
      case VerificationDocumentStatus.notSubmitted:
        return colorScheme.onSurfaceVariant;

      case VerificationDocumentStatus.uploaded:
        return colorScheme.primary;

      case VerificationDocumentStatus.pending:
        return colorScheme.tertiary;

      case VerificationDocumentStatus.verified:
        return colorScheme.primary;

      case VerificationDocumentStatus.rejected:
        return colorScheme.error;

      case VerificationDocumentStatus.expired:
        return colorScheme.error;

      case VerificationDocumentStatus.unknown:
        return colorScheme.onSurfaceVariant;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;

  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: spacing.xxxxl,
          child: Text(
            label,
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _VerificationDocumentItem {
  final VerificationDocumentType type;

  final UserVerificationDocument? document;

  const _VerificationDocumentItem({required this.type, required this.document});

  VerificationDocumentStatus get status {
    final value = document?.status;

    if (value == null || value.trim().isEmpty) {
      return VerificationDocumentStatus.notSubmitted;
    }

    return VerificationDocumentStatus.fromJson(value);
  }

  bool get hasFile {
    return document?.hasFile ?? false;
  }

  _VerificationDocumentItem copyWith({
    VerificationDocumentType? type,
    UserVerificationDocument? document,
  }) {
    return _VerificationDocumentItem(
      type: type ?? this.type,
      document: document ?? this.document,
    );
  }
}
