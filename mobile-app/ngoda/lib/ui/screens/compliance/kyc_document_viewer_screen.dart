import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/kyc/user_verification_document.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KycDocumentViewerScreen extends StatefulWidget {
  const KycDocumentViewerScreen({super.key, required this.document});

  final UserVerificationDocument document;

  @override
  State<KycDocumentViewerScreen> createState() =>
      _KycDocumentViewerScreenState();
}

class _KycDocumentViewerScreenState extends State<KycDocumentViewerScreen> {
  WebViewController? _controller;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _initializeViewer();
  }

  void _initializeViewer() {
    final url = widget.document.url?.trim();

    if (url == null || url.isEmpty) {
      setStateIfMounted(
        loading: false,
        error: 'Document is not available for viewing',
      );

      return;
    }

    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      setStateIfMounted(loading: false, error: 'Document URL is invalid');

      return;
    }

    _isLoading = true;
    _error = null;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = false;
              _error = 'Unable to display document';
            });
          },
        ),
      )
      ..loadRequest(uri);

    _controller = controller;
  }

  void setStateIfMounted({required bool loading, String? error}) {
    _isLoading = loading;
    _error = error;
  }

  void _retry() {
    setState(() {
      _controller = null;
      _error = null;
      _isLoading = false;
    });

    _initializeViewer();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Document', onClose: context.pop),

            Expanded(
              child: Column(
                children: [
                  _DocumentInformation(document: document),

                  Expanded(child: _buildViewer()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    final colorScheme = context.colorScheme;

    if (_error != null) {
      return _DocumentError(message: _error!, onRetry: _retry);
    }

    if (_controller == null) {
      return const _DocumentUnavailable();
    }

    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller!)),

        if (_isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: colorScheme.surface.withValues(alpha: 0.70),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _DocumentInformation extends StatelessWidget {
  const _DocumentInformation({required this.document});

  final UserVerificationDocument document;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final fileName = document.fileName?.trim() ?? '';

    final status = document.status?.trim() ?? '';

    final uploadedAt = document.uploadedAt;
    final verifiedAt = document.verifiedAt;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.sm,
      ),
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
                  Icons.description_outlined,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Text(
                  fileName.isEmpty ? 'Verification Document' : fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),

              if (status.isNotEmpty) ...[
                SizedBox(width: spacing.sm),

                _StatusBadge(status: status),
              ],
            ],
          ),

          if (uploadedAt != null || verifiedAt != null) ...[
            SizedBox(height: spacing.md),

            Divider(height: spacing.xs, color: colorScheme.outlineVariant),

            SizedBox(height: spacing.md),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (uploadedAt != null)
                  Expanded(
                    child: _InformationItem(
                      label: 'Uploaded',
                      value: _formatDateTime(uploadedAt),
                    ),
                  ),

                if (uploadedAt != null && verifiedAt != null)
                  SizedBox(width: spacing.md),

                if (verifiedAt != null)
                  Expanded(
                    child: _InformationItem(
                      label: 'Verified',
                      value: _formatDateTime(verifiedAt),
                      textAlign: TextAlign.right,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InformationItem extends StatelessWidget {
  const _InformationItem({
    required this.label,
    required this.value,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final String value;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: textAlign == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: textAlign,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: context.spacing.xs),

        Text(
          value,
          textAlign: textAlign,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final label = _formatStatus(status);

    final color = _statusColor(context, status);

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

class _DocumentError extends StatelessWidget {
  const _DocumentError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: iconSize.xl,
              color: colorScheme.error,
            ),

            SizedBox(height: spacing.md),

            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.small(context),
            ),

            SizedBox(height: spacing.md),

            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, size: iconSize.small),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentUnavailable extends StatelessWidget {
  const _DocumentUnavailable();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: iconSize.xl,
              color: colorScheme.onSurfaceVariant,
            ),

            SizedBox(height: spacing.md),

            Text(
              'Document is not available',
              textAlign: TextAlign.center,
              style: AppTextStyles.small(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');

  final month = date.month.toString().padLeft(2, '0');

  final hour = date.hour.toString().padLeft(2, '0');

  final minute = date.minute.toString().padLeft(2, '0');

  return '$day/$month/${date.year} '
      '$hour:$minute';
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

    case 'uploaded':
    case 'pending':
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
