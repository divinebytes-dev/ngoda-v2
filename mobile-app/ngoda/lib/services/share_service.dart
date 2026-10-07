import 'package:share_plus/share_plus.dart';

class ShareService {
  Future<ShareResult> shareText(String text) {
    final value = text.trim();

    if (value.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Share text cannot be empty.');
    }

    return _share(text: value);
  }

  Future<ShareResult> shareReferralLink(String referralLink) {
    final link = referralLink.trim();

    if (link.isEmpty) {
      throw ArgumentError.value(
        referralLink,
        'referralLink',
        'Referral link cannot be empty.',
      );
    }

    return _share(text: 'Join Ngoda using my referral link:\n\n$link');
  }

  Future<ShareResult> shareFile(String path, {String? text}) {
    final filePath = path.trim();

    if (filePath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'File path cannot be empty.');
    }

    return _share(text: _normalizeOptionalText(text), files: [XFile(filePath)]);
  }

  Future<ShareResult> shareFiles(List<String> paths, {String? text}) {
    final files = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .map(XFile.new)
        .toList(growable: false);

    if (files.isEmpty) {
      throw ArgumentError.value(
        paths,
        'paths',
        'At least one file path is required.',
      );
    }

    return _share(text: _normalizeOptionalText(text), files: files);
  }

  Future<ShareResult> _share({String? text, List<XFile>? files}) {
    return SharePlus.instance.share(ShareParams(text: text, files: files));
  }

  String? _normalizeOptionalText(String? text) {
    final value = text?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }
}
