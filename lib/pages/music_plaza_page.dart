import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../models/music.dart';
import '../utils/url_helper.dart';

enum MusicTab { plaza, ranking, mine }

class MusicPlazaPage extends StatefulWidget {
  const MusicPlazaPage({super.key});

  @override
  State<MusicPlazaPage> createState() => _MusicPlazaPageState();
}

class _MusicPlazaPageState extends State<MusicPlazaPage> {
  List<Music> _musics = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;
  String? _errorMessage;
  MusicTab _currentTab = MusicTab.plaza;
  final ScrollController _listScrollController = ScrollController();
  final AudioService _audioService = AudioService();
  final TextEditingController _searchController = TextEditingController();
  Music? _currentMusic;
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadMusic();
    _audioService.addListener(_onAudioStateChanged);
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioStateChanged);
    _listScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAudioStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _getEndpoint() {
    switch (_currentTab) {
      case MusicTab.ranking:
        return '/v1/music/plaza/ranking';
      case MusicTab.mine:
        return '/v1/music/plaza/mine';
      default:
        return '/v1/music/plaza';
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _loadMusic({bool initial = true}) async {
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
      final data = await api.getMusicPlaza(
        offset: _offset,
        limit: _limit,
        endpoint: _getEndpoint(),
        query: _searchKeyword,
      );
      final items = data['items'] ?? data['data'] ?? data['list'];
      if (items == null) throw Exception('返回数据格式错误');
      if (data['error'] != null) throw Exception(data['error']);
      final newMusic = (items as List).map((e) => Music.fromJson(e)).toList();
      final hasMore = data['has_more'] ?? false;

      setState(() {
        if (initial)
          _musics = newMusic;
        else
          _musics.addAll(newMusic);
        _hasMore = hasMore;
        _offset += newMusic.length;
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = null;
        if (initial && _musics.isNotEmpty) {
          _currentMusic = _musics[0];
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载音乐失败: $e')),
        );
      }
    }
  }

  void _playMusic(Music music) {
    final url = resolveMediaUrl(music.audioUrl);
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音频链接无效')),
      );
      return;
    }
    setState(() {
      _currentMusic = music;
    });
    _audioService.play(url);
  }

  void _togglePlay() {
    if (_currentMusic == null) return;
    final url = resolveMediaUrl(_currentMusic!.audioUrl);
    if (url.isEmpty) return;
    if (_audioService.isPlaying && _audioService.currentUrl == url) {
      _audioService.pause();
    } else if (!_audioService.isPlaying && _audioService.currentUrl == url) {
      _audioService.resume();
    } else {
      _playMusic(_currentMusic!);
    }
  }

  void _shareMusic(Music music) {
    final shareData = {
      'v': 2,
      'text':
          '歌曲: ${music.title}\n歌手: ${music.artist ?? '未知'}\n时长: ${_formatDuration(music.duration)}',
      'media_kind': 'music',
      'song_url': music.audioUrl,
      'url': music.audioUrl,
      'cover': music.coverUrl,
      'artist': music.artist ?? '未知',
      'duration': _formatDuration(music.duration),
    };
    Navigator.pop(context, shareData);
  }

  Widget _buildMusicListItem(Music music, Color primaryColor) {
    final isPlaying = _currentMusic?.id == music.id && _audioService.isPlaying;
    final coverUrl = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
    final artist =
        music.artist ?? music.displayName ?? music.username ?? '未知歌手';

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          coverUrl.isNotEmpty ? coverUrl : 'https://via.placeholder.com/48',
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 48,
            height: 48,
            color: Colors.grey[300],
            child: const Icon(Icons.music_note, size: 24),
          ),
        ),
      ),
      title: Text(
        music.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? primaryColor : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$artist · ${music.plays}次播放',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlaying)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.play_arrow, size: 20, color: Colors.grey),
          IconButton(
            icon: const Icon(Icons.share, size: 18),
            onPressed: () => _shareMusic(music),
            tooltip: '分享',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      onTap: () => _playMusic(music),
      selected: _currentMusic?.id == music.id,
      selectedTileColor: primaryColor.withOpacity(0.08),
    );
  }

  Widget _buildPlayer() {
    if (_currentMusic == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('选择一首歌曲播放', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final music = _currentMusic!;
    final coverUrl = resolveMediaUrl(music.coverUrl ?? music.avatarUrl);
    final artist =
        music.artist ?? music.displayName ?? music.username ?? '未知歌手';
    final isPlaying =
        _audioService.currentUrl == resolveMediaUrl(music.audioUrl) &&
            _audioService.isPlaying;
    final progress = _audioService.duration.inMilliseconds > 0
        ? (_audioService.position.inMilliseconds /
                _audioService.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final currentTime = _audioService.position;
    final totalTime = _audioService.duration;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              coverUrl.isNotEmpty
                  ? coverUrl
                  : 'https://via.placeholder.com/200',
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 200,
                color: Colors.grey[300],
                child: const Icon(Icons.music_note, size: 60),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 歌曲信息
          Text(
            music.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            artist,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // 进度条
          Row(
            children: [
              Text(
                _formatDuration(currentTime.inSeconds),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Expanded(
                child: Slider(
                  value: progress,
                  onChanged: (value) {
                    final seekTo = totalTime * value;
                    _audioService.seek(seekTo);
                  },
                  activeColor: Theme.of(context).primaryColor,
                  inactiveColor: Colors.grey[300],
                  min: 0,
                  max: 1,
                ),
              ),
              Text(
                _formatDuration(totalTime.inSeconds),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 32),
                onPressed: () {
                  final index = _musics.indexOf(music);
                  if (index > 0) {
                    _playMusic(_musics[index - 1]);
                  }
                },
              ),
              const SizedBox(width: 16),
              CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(context).primaryColor,
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: _togglePlay,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 32),
                onPressed: () {
                  final index = _musics.indexOf(music);
                  if (index < _musics.length - 1) {
                    _playMusic(_musics[index + 1]);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 分享按钮
          OutlinedButton.icon(
            onPressed: () => _shareMusic(music),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('分享到聊天'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
              side: BorderSide(color: Theme.of(context).primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐广场'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadMusic(initial: true),
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧列表
          SizedBox(
            width: 320,
            child: Column(
              children: [
                // Tab切换
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _buildTabButton('广场', MusicTab.plaza),
                      _buildTabButton('排行榜', MusicTab.ranking),
                      _buildTabButton('我的', MusicTab.mine),
                    ],
                  ),
                ),
                if (_currentTab == MusicTab.plaza)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索音乐',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                const Divider(height: 1),
                // 列表
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(_errorMessage!,
                                      style:
                                          TextStyle(color: Colors.grey[600])),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () => _loadMusic(initial: true),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            )
                          : _musics.isEmpty
                              ? Center(
                                  child: Text(
                                    _currentTab == MusicTab.mine
                                        ? '暂无上传的音乐'
                                        : '暂无音乐',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _listScrollController,
                                  itemCount:
                                      _musics.length + (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _musics.length) {
                                      if (_isLoadingMore) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator()),
                                        );
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Center(
                                          child: TextButton(
                                            onPressed: () =>
                                                _loadMusic(initial: false),
                                            child: const Text('加载更多'),
                                          ),
                                        ),
                                      );
                                    }
                                    return _buildMusicListItem(
                                        _musics[index], primaryColor);
                                  },
                                ),
                ),
              ],
            ),
          ),
          // 右侧播放器
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: _buildPlayer(),
            ),
          ),
        ],
      ),
    );
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query == _searchKeyword) {
      _loadMusic(initial: true);
      return;
    }
    setState(() {
      _searchKeyword = query;
    });
    _loadMusic(initial: true);
  }

  Widget _buildTabButton(String label, MusicTab tab) {
    final isSelected = _currentTab == tab;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: () {
            if (_currentTab != tab) {
              setState(() {
                _currentTab = tab;
                _musics.clear();
                _offset = 0;
                _hasMore = true;
                _searchKeyword = '';
                _searchController.clear();
                _loadMusic(initial: true);
              });
            }
          },
          style: TextButton.styleFrom(
            backgroundColor: isSelected
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            foregroundColor: isSelected ? Colors.white : Colors.grey[700],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}
