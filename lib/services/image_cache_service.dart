import 'package:flutter/painting.dart';

import 'auth_service.dart';

class ImageCacheService {
  static final ImageCacheService instance = ImageCacheService._();

  static void configure() {
    imageCache.maximumSize = 300;
    imageCache.maximumSizeBytes = 128 * 1024 * 1024;
  }

  ImageCacheService._();

  ImageProvider provider(String url, {int cacheWidth = 512}) {
    final token = AuthService().token;
    final headers = token == null || token.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    final image = NetworkImage(url, headers: headers);
    return ResizeImage(image, width: cacheWidth);
  }

  void clear() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
