import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/services/transaction_qr_codec_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() {
    return _ScanQrScreenState();
  }
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  bool _isProcessing = false;

  void _handleDetection(BarcodeCapture capture) {
    if (_isProcessing || capture.barcodes.isEmpty) {
      return;
    }

    final rawValue = capture.barcodes.first.rawValue;

    if (rawValue == null || rawValue.trim().isEmpty) {
      return;
    }

    _isProcessing = true;

    _handleScan(rawValue);
  }

  void _handleScan(String rawValue) {
    try {
      final transaction = TransactionQrCodecService.decode(rawValue);

      if (!mounted) {
        return;
      }

      context.pop(transaction);
    } on FormatException {
      _handleInvalidQr();
    } catch (_) {
      _handleInvalidQr();
    }
  }

  void _handleInvalidQr() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = false;
    });

    SnackbarService.error(context, 'Failed to read QR code');
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _handleDetection),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(spacing.padding),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing.padding,
                        vertical: spacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(
                          context.radius.borderRadius,
                        ),
                      ),
                      child: Text(
                        'Scan QR Code',
                        style: AppTextStyles.small(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton.filled(
                      tooltip: 'Close',
                      onPressed: () {
                        context.pop();
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(Icons.close_rounded, size: iconSize.medium),
                    ),
                  ),

                  if (_isProcessing)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: spacing.lg),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: spacing.padding,
                            vertical: spacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(
                              context.radius.borderRadius,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: iconSize.small,
                                height: iconSize.small,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              ),

                              SizedBox(width: spacing.sm),

                              Text(
                                'Reading QR code…',
                                style: AppTextStyles.tiny(
                                  context,
                                ).copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
