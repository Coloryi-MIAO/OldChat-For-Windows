import 'package:flutter/painting.dart';

class ImageCacheService {
  static final ImageCacheService instance = ImageCacheService._();

  static void configure() {
    imageCache.maximumSize = 300;
    imageCache.maximumSizeBytes = 128 * 1024 * 1024;
  }
  ImageCacheService._();

  ImageProvider provider(String url, {int cacheWidth = 512}) {
    return ResizeImage(NetworkImage(url), width: cacheWidth);
  }

  void clear() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
