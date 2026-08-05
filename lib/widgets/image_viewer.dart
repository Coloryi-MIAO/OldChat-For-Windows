import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../utils/url_helper.dart';
import '../utils/image_saver.dart';
import '../services/aria2_service.dart';

class ImageViewer extends StatefulWidget {
  final String imageUrl;
  const ImageViewer({super.key, required this.imageUrl});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  bool _isSaving = false;

  Future<void> _saveImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final url = resolveMediaUrl(widget.imageUrl);
      try {
        final gid = await Aria2Service().addUri(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已交给 aria2 下载（任务 $gid）')),
          );
        }
        return;
      } catch (_) {
        final path = await ImageSaver.saveImage(widget.imageUrl);
        if (path == null) throw Exception('保存失败');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片已保存到: $path')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullUrl = resolveMediaUrl(widget.imageUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download, color: Colors.white),
            onPressed: _isSaving ? null : _saveImage,
            tooltip: '保存图片',
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: PhotoView(
            imageProvider: NetworkImage(fullUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            initialScale: PhotoViewComputedScale.contained,
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
