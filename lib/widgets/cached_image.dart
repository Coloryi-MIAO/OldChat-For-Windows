import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/image_cache_service.dart';

class CachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int cacheWidth;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const CachedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth = 768,
    this.errorBuilder,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _file;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      setState(() {
        _file = null;
        _failed = false;
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final url = widget.url.trim();
    if (url.isEmpty) return;
    final file = await ImageCacheService.instance.existingFile(url);
    if (mounted && file != null) {
      setState(() => _file = file);
      return;
    }
    unawaited(ImageCacheService.instance.cacheInBackground(url));
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url.trim();
    if (url.isEmpty || _failed) {
      return widget.errorBuilder?.call(context, Exception('图片链接无效'), StackTrace.current) ??
          SizedBox(width: widget.width, height: widget.height);
    }
    final provider = _file == null
        ? ImageCacheService.instance.provider(url, cacheWidth: widget.cacheWidth)
        : ResizeImage(FileImage(_file!), width: widget.cacheWidth);
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, error, stack) {
        if (mounted) setState(() => _failed = true);
        return widget.errorBuilder?.call(context, error, stack) ??
            SizedBox(width: widget.width, height: widget.height);
      },
    );
  }
}
