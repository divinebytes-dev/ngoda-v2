import 'package:flutter/material.dart';
import 'package:ngoda/services/screen_scaling_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AppQrCode extends StatelessWidget {
  final String data;

  /// Base QR size before responsive scaling.
  final double size;

  const AppQrCode({super.key, required this.data, this.size = 250});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final qrSize = ScreenScalingService.scaleSize(context, size);

    final logoWidth = ScreenScalingService.scaleSize(context, 90);

    final logoHeight = ScreenScalingService.scaleSize(context, 30);

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(radius.cardRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: qrSize,

          // QR contrast is intentionally fixed rather
          // than following the application theme.
          backgroundColor: Colors.white,

          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),

          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),

          embeddedImage: const AssetImage('assets/images/qr-logo-1.PNG'),

          embeddedImageStyle: QrEmbeddedImageStyle(
            size: Size(logoWidth, logoHeight),
          ),

          errorCorrectionLevel: QrErrorCorrectLevel.H,
        ),
      ),
    );
  }
}
