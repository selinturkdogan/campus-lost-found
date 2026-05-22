import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Compress an image before upload.
///
/// Defaults are tuned to preserve visible quality (1280px on the long edge,
/// JPEG quality 85) while typically shrinking a 3-5 MB photo down to
/// ~150-400 KB. Returns the original file if compression fails.
class ImageUtils {
  static Future<File> compress(
    File file, {
    int maxWidth = 1280,
    int quality = 85,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/cmp_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxWidth,
        keepExif: false,
        format: CompressFormat.jpeg,
      );

      if (result == null) return file;
      return File(result.path);
    } catch (_) {
      // If anything goes wrong, fall back to the original file so the
      // upload still succeeds.
      return file;
    }
  }
}
