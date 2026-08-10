import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/emoji.dart';
import '../utils/url_helper.dart';

class EmojiPlazaPage extends StatefulWidget {
  const EmojiPlazaPage({super.key});

  @override
  State<EmojiPlazaPage> createState() => _EmojiPlazaPageState();
}

class _EmojiPlazaPageState extends State<EmojiPlazaPage> {
  List<Emoji> _emojis = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEmojis();
  }

  Future<void> _loadEmojis({bool initial = true}) async {
    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
        _errorMessage = null;
      });
    }

    try {
      final api = ApiService();
      final data = await api.getEmojiPlaza(offset: _offset, limit: _limit);
      final items = data['items'] ?? data['data'] ?? data['list'];
      if (items == null) throw Exception('返回数据格式错误');
      if (data['error'] != null) throw Exception(data['error']);
      final newEmojis = (items as List).map((e) => Emoji.fromJson(e)).toList();
      final hasMore = data['has_more'] ?? false;

      setState(() {
        if (initial)
          _emojis = newEmojis;
        else
          _emojis.addAll(newEmojis);
        _hasMore = hasMore;
        _offset += newEmojis.length;
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载表情失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('表情广场'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadEmojis(initial: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('加载失败: $_errorMessage',
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _loadEmojis(initial: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _emojis.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emoji_emotions,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('暂无表情',
                              style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _emojis.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _emojis.length) {
                          if (_isLoadingMore) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          return GestureDetector(
                            onTap: () => _loadEmojis(initial: false),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(child: Text('加载更多')),
                            ),
                          );
                        }
                        final emoji = _emojis[index];
                        final imageUrl =
                            resolveMediaUrl(emoji.thumbUrl ?? emoji.mediaUrl);

                        return GestureDetector(
                          onTap: () {
                            // ★★★ 关键：点击返回媒体 URL ★★★
                            Navigator.pop(context, emoji.mediaUrl);
                          },
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[200]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: Colors.grey[200],
                                        child: const Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[200],
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '喜欢 ${emoji.likes}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('上传功能请使用网页端或App内文件选择')),
          );
        },
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
