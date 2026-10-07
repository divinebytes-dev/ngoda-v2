import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/core/providers/permission_handler_service_provider.dart';
import 'package:ngoda/core/providers/share_service_provider.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_icon_button.dart';
import 'package:ngoda/ui/widgets/qr_payment.dart';
import 'package:ngoda/ui/widgets/tap_2_pay.dart';
import 'package:ngoda/ui/widgets/user_transaction_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

abstract final class DialogService {
  static final Logger _log = Logger('DialogService');

  static const Duration _animationDuration = Duration(milliseconds: 140);

  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    ConfirmType type = ConfirmType.info,
  }) async {
    if (!context.mounted) {
      return false;
    }

    final dialogType = switch (type) {
      ConfirmType.destructive => DialogType.destructive,
      ConfirmType.success => DialogType.success,
      ConfirmType.info => DialogType.info,
    };

    return confirm(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      type: dialogType,
    );
  }

  static Future<void> success(
    BuildContext context, {
    String title = 'Success',
    required String message,
  }) async {
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildDialog(
          dialogContext,
          title: title,
          message: message,
          type: DialogType.success,
          confirmText: 'OK',
          onConfirm: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  static void loading(BuildContext context, {String message = 'Please wait'}) {
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildDialog(
          dialogContext,
          title: message,
          message: '',
          type: DialogType.loading,
          showActions: false,
        );
      },
    );
  }

  static void dismissLoading(BuildContext context) {
    if (!context.mounted) {
      return;
    }

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  static Future<void> error(
    BuildContext context, {
    required String message,
  }) async {
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildDialog(
          dialogContext,
          title: 'Error',
          message: message,
          type: DialogType.error,
          confirmText: 'OK',
          onConfirm: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    DialogType type = DialogType.info,
  }) async {
    if (!context.mounted) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildDialog(
          dialogContext,
          title: title,
          message: message,
          type: type,
          confirmText: confirmText,
          cancelText: cancelText,
          onConfirm: () {
            Navigator.of(dialogContext).pop(true);
          },
          onCancel: () {
            Navigator.of(dialogContext).pop(false);
          },
        );
      },
    );

    return result ?? false;
  }

  static void payment(
    BuildContext context, {
    String title = 'Pay',
    required TransactionData data,
    required VoidCallback onCancel,
  }) {
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildTransactionDialog(
          dialogContext,
          title: title,
          child: QrPayment(data: data),
          onCancel: onCancel,
        );
      },
    );
  }

  static void nfcPayment(
    BuildContext context, {
    String title = 'Tap to Pay',
    required TransactionData data,
    required VoidCallback onCancel,
  }) {
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, child) {
            final state = ref.watch(walletTransactionProvider);

            switch (state.transactionStatus) {
              case TransactionStatus.processing:
                return _buildDialog(
                  dialogContext,
                  title: 'Processing...',
                  message: 'Transaction detected',
                  type: DialogType.loading,
                  showActions: false,
                );

              case TransactionStatus.failed:
                return _buildDialog(
                  dialogContext,
                  title: 'Error',
                  message: 'Transaction failed',
                  type: DialogType.error,
                  confirmText: 'OK',
                  onConfirm: onCancel,
                );

              default:
                return _buildTransactionDialog(
                  dialogContext,
                  title: title,
                  child: Tap2Pay(data: data),
                  onCancel: onCancel,
                );
            }
          },
        );
      },
    );
  }

  static void transact(
    BuildContext context, {
    required String title,
    required GlobalKey qrKey,
    required TransactionData data,
    required VoidCallback onCancel,
    bool download = false,
    bool isDeposit = false,
  }) {
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, child) {
            final state = ref.watch(walletTransactionProvider);

            switch (state.transactionStatus) {
              case TransactionStatus.processing:
                return _buildDialog(
                  dialogContext,
                  title: 'Processing...',
                  message: 'Transaction detected',
                  type: DialogType.loading,
                  showActions: false,
                );

              case TransactionStatus.failed:
                return _buildDialog(
                  dialogContext,
                  title: 'Error',
                  message: 'Transaction failed',
                  type: DialogType.error,
                  confirmText: 'OK',
                  onConfirm: onCancel,
                );

              default:
                return _buildTransactionQrDialog(
                  dialogContext,
                  ref: ref,
                  title: title,
                  qrKey: qrKey,
                  data: data,
                  onCancel: onCancel,
                  download: download,
                  isDeposit: isDeposit,
                );
            }
          },
        );
      },
    );
  }

  static Widget _buildTransactionQrDialog(
    BuildContext context, {
    required WidgetRef ref,
    required String title,
    required GlobalKey qrKey,
    required TransactionData data,
    required VoidCallback onCancel,
    required bool download,
    required bool isDeposit,
  }) {
    return _dialogSurface(
      context,
      accentColor: context.colorScheme.primary,
      maxHeightFactor: 0.85,
      child: Padding(
        padding: EdgeInsets.all(context.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: context.spacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      key: qrKey,
                      child: UserTransactionScreen(
                        data: data,
                        isDeposit: isDeposit,
                      ),
                    ),
                    SizedBox(height: context.spacing.md),
                    const Divider(),
                    SizedBox(height: context.spacing.xs),
                  ],
                ),
              ),
            ),
            if (download)
              _buildTransactionActions(
                context,
                ref: ref,
                qrKey: qrKey,
                data: data,
                onCancel: onCancel,
              )
            else
              AppButton(text: 'Cancel', isPrimary: false, onPressed: onCancel),
          ],
        ),
      ),
    );
  }

  static Widget _buildTransactionActions(
    BuildContext context, {
    required WidgetRef ref,
    required GlobalKey qrKey,
    required TransactionData data,
    required VoidCallback onCancel,
  }) {
    return Column(
      children: [
        SizedBox(height: context.spacing.sm),
        Row(
          children: [
            Expanded(
              child: AppIconButton(
                title: 'Cancel',
                icon: Icons.close,
                iconSize: context.iconSize.medium,
                color: context.colorScheme.primary,
                onTap: onCancel,
              ),
            ),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: AppIconButton(
                title: 'Share',
                icon: Icons.share_outlined,
                iconSize: context.iconSize.medium,
                color: context.colorScheme.primary,
                onTap: () async {
                  final path = await generateQrFile(qrKey);

                  if (path == null) {
                    if (!context.mounted) {
                      return;
                    }

                    SnackbarService.error(
                      context,
                      'Failed to share QR voucher',
                    );

                    return;
                  }

                  await ref
                      .read(shareServiceProvider)
                      .shareFile(path, text: 'Spend with Ngoda');

                  if (!context.mounted) {
                    return;
                  }

                  onCancel();
                },
              ),
            ),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: AppIconButton(
                title: 'Download',
                icon: Icons.download_outlined,
                iconSize: context.iconSize.medium,
                color: context.colorScheme.primary,
                onTap: () async {
                  final permissionService = ref.read(
                    permissionHandlerServiceProvider,
                  );

                  final hasPermission = await permissionService
                      .requestGalleryPermission();

                  if (!hasPermission) {
                    return;
                  }

                  final saved = await downloadQr(qrKey, data.r);

                  if (!context.mounted) {
                    return;
                  }

                  if (saved) {
                    SnackbarService.success(
                      context,
                      'QR voucher saved to gallery',
                    );

                    onCancel();
                    return;
                  }

                  SnackbarService.error(
                    context,
                    'Failed to save QR voucher to gallery',
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildTransactionDialog(
    BuildContext context, {
    required String title,
    required Widget child,
    required VoidCallback onCancel,
  }) {
    return _dialogSurface(
      context,
      accentColor: context.colorScheme.primary,
      child: Padding(
        padding: EdgeInsets.all(context.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: context.spacing.sm),
            child,
            SizedBox(height: context.spacing.md),
            const Divider(),
            SizedBox(height: context.spacing.xs),
            AppButton(text: 'Cancel', isPrimary: false, onPressed: onCancel),
          ],
        ),
      ),
    );
  }

  static Future<bool> downloadQr(GlobalKey qrKey, String reference) async {
    try {
      final pngBytes = await _capturePng(qrKey);

      if (pngBytes == null) {
        return false;
      }

      await SaverGallery.saveImage(
        pngBytes,
        quality: 100,
        fileName: 'voucher_$reference',
        skipIfExists: false,
      );

      return true;
    } catch (error, stackTrace) {
      _log.warning('Failed to save QR image.', error, stackTrace);

      return false;
    }
  }

  static Future<String?> generateQrFile(GlobalKey qrKey) async {
    try {
      final pngBytes = await _capturePng(qrKey);

      if (pngBytes == null) {
        return null;
      }

      final tempDirectory = await getTemporaryDirectory();

      final file = File('${tempDirectory.path}/ngoda_qr.png');

      await file.writeAsBytes(pngBytes, flush: true);

      return file.path;
    } catch (error, stackTrace) {
      _log.warning('Failed to generate QR file.', error, stackTrace);

      return null;
    }
  }

  static Future<Uint8List?> _capturePng(GlobalKey qrKey) async {
    final context = qrKey.currentContext;

    if (context == null || !context.mounted) {
      return null;
    }

    final renderObject = context.findRenderObject();

    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }

    final image = await renderObject.toImage(pixelRatio: 3);

    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData?.buffer.asUint8List();
  }

  static Widget _buildDialog(
    BuildContext context, {
    required String title,
    required String message,
    required DialogType type,
    String? confirmText,
    String? cancelText,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    bool showActions = true,
  }) {
    final presentation = _dialogPresentation(context, type);

    return _dialogSurface(
      context,
      accentColor: presentation.color,
      maxHeightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.all(context.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (type == DialogType.loading)
                      CircularProgressIndicator(
                        color: presentation.color,
                        strokeWidth: 2.5,
                      )
                    else
                      _dialogIcon(
                        context,
                        icon: presentation.icon,
                        color: presentation.color,
                      ),
                    SizedBox(height: context.spacing.md),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.medium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (message.isNotEmpty) ...[
                      SizedBox(height: context.spacing.sm),
                      SelectableText(
                        message,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(color: context.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showActions && (confirmText != null || cancelText != null)) ...[
              SizedBox(height: context.spacing.lg),
              _buildDialogActions(
                context,
                confirmText: confirmText,
                cancelText: cancelText,
                onConfirm: onConfirm,
                onCancel: onCancel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildDialogActions(
    BuildContext context, {
    String? confirmText,
    String? cancelText,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) {
    return Row(
      children: [
        if (cancelText != null)
          Expanded(
            child: AppButton(
              text: cancelText,
              isPrimary: false,
              onPressed:
                  onCancel ??
                  () {
                    Navigator.of(context).pop();
                  },
            ),
          ),
        if (cancelText != null && confirmText != null)
          SizedBox(width: context.spacing.sm),
        if (confirmText != null)
          Expanded(
            child: AppButton(
              text: confirmText,
              isPrimary: true,
              onPressed:
                  onConfirm ??
                  () {
                    Navigator.of(context).pop();
                  },
            ),
          ),
      ],
    );
  }

  static Future<bool?> paymentConfirmation(
    BuildContext context, {
    required String title,
    required List<PaymentRow> rows,
  }) {
    if (!context.mounted) {
      return Future.value(false);
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildPaymentDetailsDialog(
          dialogContext,
          title: title,
          rows: rows,
          type: DialogType.question,
          actions: Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  isPrimary: false,
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                ),
              ),
              SizedBox(width: dialogContext.spacing.sm),
              Expanded(
                child: AppButton(
                  text: 'Confirm',
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> paymentReceipt(
    BuildContext context, {
    required String title,
    required List<PaymentRow> rows,
    required VoidCallback onDone,
  }) async {
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildPaymentDetailsDialog(
          dialogContext,
          title: title,
          rows: rows,
          type: DialogType.success,
          showDetailsCard: true,
          actions: AppButton(
            text: 'Done',
            onPressed: () {
              Navigator.of(dialogContext).pop();

              onDone();
            },
          ),
        );
      },
    );
  }

  static Widget _buildPaymentDetailsDialog(
    BuildContext context, {
    required String title,
    required List<PaymentRow> rows,
    required DialogType type,
    required Widget actions,
    bool showDetailsCard = false,
  }) {
    final presentation = _dialogPresentation(context, type);

    final details = Column(
      children: rows.map((row) => _row(context, row)).toList(),
    );

    return Dialog(
      constraints: _dialogWidthConstraints(context),
      backgroundColor: context.theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radius.dialogRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogIcon(
              context,
              icon: presentation.icon,
              color: presentation.color,
              large: type == DialogType.success,
            ),
            SizedBox(height: context.spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: context.spacing.md),
            if (showDetailsCard)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(context.spacing.md),
                decoration: BoxDecoration(
                  color: context.theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(
                    context.radius.cardRadius,
                  ),
                ),
                child: details,
              )
            else
              details,
            SizedBox(height: context.spacing.lg),
            actions,
          ],
        ),
      ),
    );
  }

  static Widget _row(BuildContext context, PaymentRow row) {
    final valueStyle = switch (row.type) {
      PaymentRowType.amount =>
        row.isBold
            ? AppTextStyles.mediumNumber(context)
            : AppTextStyles.smallNumber(context),
      PaymentRowType.text => AppTextStyles.small(context),
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              row.label,
              textAlign: TextAlign.left,
              style: AppTextStyles.small(
                context,
              ).copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),

          SizedBox(width: context.spacing.sm),

          Expanded(
            flex: 6,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: valueStyle.copyWith(
                fontWeight: row.isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static BoxConstraints _dialogWidthConstraints(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.75)
        .clamp(0.0, 480.0)
        .toDouble();

    return BoxConstraints.tightFor(width: width);
  }

  static Widget _dialogSurface(
    BuildContext context, {
    required Color accentColor,
    required Widget child,
    double? maxHeightFactor,
  }) {
    final screenSize = MediaQuery.sizeOf(context);

    final content = Container(
      decoration: BoxDecoration(
        color: context.theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(context.radius.dialogRadius),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: child,
    );

    return Dialog(
      constraints: _dialogWidthConstraints(context),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: TweenAnimationBuilder<double>(
        duration: _animationDuration,
        curve: Curves.easeOut,
        tween: Tween<double>(begin: 0.98, end: 1),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale, child: child),
          );
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxHeightFactor != null
                ? screenSize.height * maxHeightFactor
                : double.infinity,
          ),
          child: content,
        ),
      ),
    );
  }

  static Widget _dialogIcon(
    BuildContext context, {
    required IconData icon,
    required Color color,
    bool large = false,
  }) {
    return Container(
      padding: EdgeInsets.all(large ? context.spacing.md : context.spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: color,
        size: large ? context.iconSize.xl : context.iconSize.xl,
      ),
    );
  }

  static _DialogPresentation _dialogPresentation(
    BuildContext context,
    DialogType type,
  ) {
    final scheme = context.colorScheme;

    switch (type) {
      case DialogType.error:
        return _DialogPresentation(
          color: scheme.error,
          icon: Icons.error_outline,
        );

      case DialogType.success:
        return const _DialogPresentation(
          color: Color(0xFF16A34A),
          icon: Icons.check_circle_outline,
        );

      case DialogType.destructive:
        return _DialogPresentation(
          color: scheme.error,
          icon: Icons.warning_amber_rounded,
        );

      case DialogType.loading:
        return _DialogPresentation(
          color: scheme.primary,
          icon: Icons.hourglass_top,
        );

      case DialogType.question:
        return _DialogPresentation(
          color: Colors.blue,
          icon: Icons.question_mark_outlined,
        );

      case DialogType.info:
        return _DialogPresentation(
          color: scheme.primary,
          icon: Icons.info_outline,
        );
    }
  }
}

class _DialogPresentation {
  final Color color;
  final IconData icon;

  const _DialogPresentation({required this.color, required this.icon});
}
