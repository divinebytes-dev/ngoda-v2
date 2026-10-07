import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/core/providers/deep_link_service_provider.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/providers/permission_handler_service_provider.dart';
import 'package:ngoda/core/providers/share_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_icon_button.dart';
import 'package:ngoda/ui/widgets/referral_qr.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

class ShareNgodaReferralScreen extends ConsumerStatefulWidget {
  const ShareNgodaReferralScreen({super.key});

  @override
  ConsumerState<ShareNgodaReferralScreen> createState() =>
      _ShareNgodaReferralScreenState();
}

class _ShareNgodaReferralScreenState
    extends ConsumerState<ShareNgodaReferralScreen> {
  final GlobalKey qrKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final referralCode =
        ref
            .read(hiveServiceProvider)
            .getItem<String>(HiveBoxName.referralCode, 'referralCode')
            .result ??
        '';

    final referralLink = ref
        .read(deepLinkServiceProvider)
        .buildReferralLink(referralCode);

    final shareService = ref.read(shareServiceProvider);

    final permissionHandlerService = ref.read(permissionHandlerServiceProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.md),
              child: ViewHeader(title: 'Referral', onClose: context.pop),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.lg,
                  spacing.md,
                  spacing.lg,
                ),
                child: Column(
                  children: [
                    Text(
                      'Invite someone to Ngoda',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Share your referral QR code or referral link.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: spacing.lg),

                    RepaintBoundary(
                      key: qrKey,
                      child: ReferralQr(referralLink: referralLink, size: 220),
                    ),

                    SizedBox(height: spacing.lg),

                    Row(
                      children: [
                        Expanded(
                          child: AppIconButton(
                            title: 'Share QR',
                            icon: Icons.share_rounded,
                            iconSize: iconSize.medium,
                            color: colorScheme.primary,
                            layout: AppIconButtonLayout.horizontal,
                            onTap: () async {
                              final path = await generateQrFile();

                              if (!context.mounted) {
                                return;
                              }

                              if (path == null) {
                                SnackbarService.error(
                                  context,
                                  'Failed to generate referral QR',
                                );

                                return;
                              }

                              await shareService.shareFile(
                                path,
                                text:
                                    'Join Ngoda using my referral link:\n\n'
                                    '$referralLink',
                              );
                            },
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        Expanded(
                          child: AppIconButton(
                            title: 'Download QR',
                            icon: Icons.download_rounded,
                            iconSize: iconSize.medium,
                            color: colorScheme.primary,
                            layout: AppIconButtonLayout.horizontal,
                            onTap: () async {
                              final hasPermission =
                                  await permissionHandlerService
                                      .requestGalleryPermission();

                              if (!hasPermission) {
                                return;
                              }

                              final saved = await downloadQr();

                              if (!context.mounted) {
                                return;
                              }

                              if (saved) {
                                SnackbarService.success(
                                  context,
                                  'Referral QR saved to gallery',
                                );
                              } else {
                                SnackbarService.error(
                                  context,
                                  'Failed to save referral QR to gallery',
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: spacing.lg),

                    Divider(color: colorScheme.outlineVariant),

                    SizedBox(height: spacing.lg),

                    _ReferralLinkCard(referralLink: referralLink),

                    SizedBox(height: spacing.md),

                    Row(
                      children: [
                        Expanded(
                          child: AppIconButton(
                            title: 'Copy Link',
                            icon: Icons.copy_rounded,
                            iconSize: iconSize.medium,
                            color: colorScheme.primary,
                            layout: AppIconButtonLayout.horizontal,
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: referralLink),
                              );

                              if (!context.mounted) {
                                return;
                              }

                              SnackbarService.success(
                                context,
                                'Referral link copied',
                              );
                            },
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        Expanded(
                          child: AppIconButton(
                            title: 'Share Link',
                            icon: Icons.share_rounded,
                            iconSize: iconSize.large,
                            color: colorScheme.primary,
                            layout: AppIconButtonLayout.horizontal,
                            onTap: () async {
                              await shareService.shareReferralLink(
                                referralLink,
                              );
                            },
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
    );
  }

  Future<Uint8List?> _captureQr() async {
    try {
      final qrContext = qrKey.currentContext;

      if (qrContext == null) {
        return null;
      }

      final renderObject = qrContext.findRenderObject();

      if (renderObject is! RenderRepaintBoundary) {
        return null;
      }

      final image = await renderObject.toImage(pixelRatio: 3);

      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<bool> downloadQr() async {
    final pngBytes = await _captureQr();

    if (pngBytes == null) {
      return false;
    }

    try {
      await SaverGallery.saveImage(
        pngBytes,
        quality: 100,
        fileName: 'ngoda_referral',
        skipIfExists: false,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> generateQrFile() async {
    final pngBytes = await _captureQr();

    if (pngBytes == null) {
      return null;
    }

    try {
      final tempDir = await getTemporaryDirectory();

      final file = File('${tempDir.path}/ngoda_referral.png');

      await file.writeAsBytes(pngBytes);

      return file.path;
    } catch (_) {
      return null;
    }
  }
}

class _ReferralLinkCard extends StatelessWidget {
  const _ReferralLinkCard({required this.referralLink});

  final String referralLink;

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
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.link_rounded,
            size: iconSize.small,
            color: colorScheme.primary,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: SelectableText(
              referralLink,
              style: AppTextStyles.small(context),
            ),
          ),
        ],
      ),
    );
  }
}
