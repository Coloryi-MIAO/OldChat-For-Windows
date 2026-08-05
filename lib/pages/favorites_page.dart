import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';
import '../utils/url_helper.dart';
import '../widgets/image_viewer.dart';
import '../pages/music_plaza_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFavorites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_loading)
      _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final data = await api.getFavorites();
      setState(() {
        _favorites = (data['items'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载收藏失败: $e')),
        );
      }
    }
  }

  Future<void> _removeFavorite(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除收藏'),
        content: const Text('确定要移除该收藏吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ApiService();
      await api.removeFavorite(item['target_id'], item['type']);
      setState(() {
        _favorites.removeWhere((f) => f['target_id'] == item['target_id']);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移除收藏')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  void _openDetail(Map<String, dynamic> item) {
    final type = item['type'] ?? 'unknown';
    final rawTarget = item['target'];
    final target = rawTarget is Map
        ? Map<String, dynamic>.from(rawTarget)
        : <String, dynamic>{};
    final rawUrl = target['url'] ??
        target['media_url'] ??
        target['image_url'] ??
        target['video_url'] ??
        target['link'] ??
        target['web_url'];
    final url = rawUrl?.toString().trim() ?? '';

    if (type == 'image' || type == 'emoji') {
      if (url.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewer(imageUrl: resolveMediaUrl(url)),
          ),
        );
        return;
      }
    }

    if (type == 'video') {
      if (url.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WebViewPage(url: resolveMediaUrl(url)),
          ),
        );
        return;
      }
    }

    if (type == 'music') {
      Navigator.pushNamed(context, '/music_plaza');
      return;
    }

    if (url.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebViewPage(url: resolveMediaUrl(url)),
        ),
      );
      return;
    }

    _showDetailDialog(item);
  }

  void _showDetailDialog(Map<String, dynamic> item) {
    final type = item['type'] ?? 'unknown';
    final target = item['target'] ?? {};
    final title = target['title'] ?? target['name'] ?? target['body'] ?? '未命名';
    final description =
        target['description'] ?? target['artist'] ?? target['text'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty) Text(description),
            const SizedBox(height: 8),
            Text('类型: $type',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (target['created_at'] != null)
              Text(
                '收藏时间: ${DateTime.fromMillisecondsSinceEpoch(target['created_at'] * 1000).toString().substring(0, 16)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteItem(Map<String, dynamic> item) {
    final target = item['target'] ?? {};
    final title = target['title'] ?? target['name'] ?? target['body'] ?? '未命名';
    final imageUrl = resolveMediaUrl(
        target['cover_url'] ?? target['image_url'] ?? target['avatar_url']);

    return ListTile(
      leading: imageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[200],
                  child: const Icon(Icons.favorite, color: Colors.grey),
                ),
              ),
            )
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite, color: Colors.grey),
            ),
      title: Text(title),
      subtitle: Text(
          '类型: ${item['type'] ?? 'unknown'} · ${item['created_at'] != null ? DateTime.fromMillisecondsSinceEpoch(item['created_at'] * 1000).toString().substring(0, 10) : ''}'),
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.red),
        onPressed: () => _removeFavorite(item),
      ),
      onTap: () => _openDetail(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFavorites,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('暂无收藏', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: _buildFavoriteItem(_favorites[index]),
                    );
                  },
                ),
    );
  }
}

// ===== WebView 页面 =====
class WebViewPage extends StatefulWidget {
  final String url;
  const WebViewPage({super.key, required this.url});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
