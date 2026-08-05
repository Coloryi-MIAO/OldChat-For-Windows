import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';

class CachedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final int cacheWidth;

  const CachedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
    this.cacheWidth = 768,
  });

  @override
  Widget build(BuildContext context) {
    final watch = Stopwatch()..start();
    final image = Image(
      image: ImageCacheService.instance.provider(url, cacheWidth: cacheWidth),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    watch.stop();
    if (watch.elapsedMilliseconds > 30) {
      debugPrint('[图片慢] 创建图片组件 ${watch.elapsedMilliseconds}ms $url');
    }
    return image;
  }
}
