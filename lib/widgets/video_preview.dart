import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../utils/url_helper.dart';

class VideoPreview extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;

  const VideoPreview({super.key, required this.url, this.thumbnailUrl});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  String? _error;
  bool _visible = false;
  bool _loading = false;

  String get _resolvedUrl => resolveMediaUrl(widget.url);
  String get _resolvedThumbnail => resolveMediaUrl(widget.thumbnailUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryInitialize();
    });
  }

  void _checkVisibility() {
    if (!mounted || _visible || _loading) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
      return;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final screen = MediaQuery.sizeOf(context);
    final visible = rect.bottom > 0 && rect.top < screen.height;
    if (visible) {
      _visible = true;
      _tryInitialize();
    }
  }

  Future<void> _tryInitialize() async {
    if (_loading) return;
    _loading = true;
    final watch = Stopwatch()..start();
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _error = '视频链接无效');
      return;
    }

    try {
      final token = AuthService().token;
      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: token == null || token.isEmpty
            ? const {}
            : {'Authorization': 'Bearer $token'},
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.white38,
          bufferedColor: Colors.white70,
        ),
      );
      setState(() {
        _controller = controller;
        _chewieController = chewie;
      });
      watch.stop();
      print('[播放器慢] 视频初始化 ${watch.elapsedMilliseconds}ms ${widget.url}');
    } catch (error) {
      watch.stop();
      print('[播放器慢] 视频初始化失败 ${watch.elapsedMilliseconds}ms $error');
      if (mounted) setState(() => _error = '视频加载失败');
    } finally {
      _loading = false;
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSystemPlayer() async {
    final uri = Uri.tryParse(_resolvedUrl);
    if (uri == null) return;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd.exe', ['/c', 'start', '', uri.toString()]);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await _openBrowser();
    }
  }

  Widget _thumbnail() {
    if (_resolvedThumbnail.isEmpty) {
      return Container(color: Colors.black12);
    }
    return Image.network(
      _resolvedThumbnail,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.black12),
    );
  }

  Future<void> _saveVideo() async {
    if (_resolvedUrl.isEmpty) return;
    try {
      final result = await DownloadService.download(_resolvedUrl, fileName: 'oldchat_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.usedAria2 ? '已交给 aria2 下载' : '视频已保存：${result.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频下载失败：$e')));
    }
  }

  Widget _actions() {
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _openBrowser,
          icon: const Icon(Icons.open_in_browser, size: 16),
          label: const Text('浏览器打开'),
        ),
        OutlinedButton.icon(
          onPressed: _openSystemPlayer,
          icon: const Icon(Icons.ondemand_video, size: 16),
          label: const Text('系统播放器打开'),
        ),
        OutlinedButton.icon(
          onPressed: _saveVideo,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('下载视频'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _checkVisibility();
    final player = _chewieController == null
        ? Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              _thumbnail(),
              if (_error == null)
                const Center(child: CircularProgressIndicator())
              else
                Center(
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          )
        : AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Chewie(controller: _chewieController!),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: double.infinity, height: 190, child: player),
        const SizedBox(height: 8),
        _actions(),
      ],
    );
  }
}
