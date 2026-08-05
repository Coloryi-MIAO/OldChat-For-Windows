import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'video_preview.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../utils/message_parser.dart';
import '../utils/url_helper.dart';
import '../utils/image_saver.dart';
import 'image_viewer.dart';
import '../services/cache_service.dart';
import '../services/image_cache_service.dart';
import '../services/download_service.dart';

class MessageTile extends StatefulWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final void Function(String quotedId)? onQuoteTap;
  final void Function(String uid, String name)? onAvatarLongPress;
  final void Function(String uid, String name, Offset position)?
      onAvatarSecondaryTap; // ★ 新增
  final bool isRedPacket;
  final bool isClaimed;
  final VoidCallback? onClaimRedPacket;

  const MessageTile({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
    this.onSecondaryTap,
    this.onQuoteTap,
    this.onAvatarLongPress,
    this.onAvatarSecondaryTap,
    this.isRedPacket = false,
    this.isClaimed = false,
    this.onClaimRedPacket,
  });

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  static final Map<String, Map<String, dynamic>> _profileCache = {};
  String? _avatarUrl;
  String? _myAvatarUrl;
  String? _senderName;
  final Map<String, String> _mentionNameCache = {};

  final AudioService _audioService = AudioService();


  @override
  void initState() {
    super.initState();
    _loadSenderInfo();
    _loadMyAvatar();
    _audioService.addListener(_onAudioStateChanged);
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioStateChanged);
    super.dispose();
  }

  void _onAudioStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatVoiceTime(Duration d) {
    final totalSecs = d.inSeconds;
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _resolveVideoUrl() {
    final mediaUrl = widget.message.mediaUrl;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      return mediaUrl;
    }
    return '';
  }

  void _openVideo(String url) async {
    _launchVideoInBrowser(url);
  }

  void _launchVideoInBrowser(String url) async {
    final fullUrl = resolveMediaUrl(url);
    try {
      if (await canLaunchUrl(Uri.parse(fullUrl))) {
        await launchUrl(Uri.parse(fullUrl),
            mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开浏览器')),
        );
      }
    } catch (e) {}
  }

  Future<void> _loadSenderInfo() async {
    final msg = widget.message;
    final uid = msg.fromUid;
    if (uid.isEmpty) return;
    final auth = context.read<AuthService>();
    if (uid == auth.userId) {
      setState(() => _senderName = '我');
      return;
    }
    final cachedProfile = _profileCache[uid];
    if (cachedProfile != null) {
      if (mounted) {
        setState(() {
          _senderName =
              cachedProfile['display_name'] ?? cachedProfile['username'] ?? uid;
          _avatarUrl = cachedProfile['avatar_url'];
        });
      }
      return;
    }
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(uid);
      _profileCache[uid] = profile;
      final userId = context.read<AuthService>().userId ?? 'guest';
      await CacheService().writeJson(
        CacheService().scoped(userId, 'profile:$uid'),
        profile,
      );
      if (mounted) {
        setState(() {
          _senderName = profile['display_name'] ?? profile['username'] ?? uid;
          _avatarUrl = profile['avatar_url'];
        });
      }
    } catch (_) {
      final userId = context.read<AuthService>().userId ?? 'guest';
      final cached = await CacheService().readJson(
        CacheService().scoped(userId, 'profile:$uid'),
      );
      if (cached is Map && mounted) {
        setState(() {
          _senderName = cached['display_name'] ?? cached['username'] ?? uid;
          _avatarUrl = cached['avatar_url'];
        });
      } else if (mounted) {
        setState(() => _senderName = uid);
      }
    }
  }

  Future<String> _getMentionName(String uid) async {
    if (_mentionNameCache.containsKey(uid)) {
      return _mentionNameCache[uid]!;
    }
    final auth = context.read<AuthService>();
    if (uid == auth.userId) {
      _mentionNameCache[uid] = '我';
      return '我';
    }
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(uid);
      final name = profile['display_name'] ?? profile['username'] ?? uid;
      _mentionNameCache[uid] = name;
      return name;
    } catch (_) {
      _mentionNameCache[uid] = uid;
      return uid;
    }
  }

  Future<void> _loadMyAvatar() async {
    if (!widget.isMe) return;
    final auth = context.read<AuthService>();
    final userId = auth.userId;
    if (userId == null) return;
    final cachedProfile = _profileCache[userId];
    if (cachedProfile != null) {
      if (mounted) setState(() => _myAvatarUrl = cachedProfile['avatar_url']);
      return;
    }
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(userId);
      await CacheService().writeJson(
        CacheService().scoped(userId, 'profile:$userId'),
        profile,
      );
      _profileCache[userId] = profile;
      if (mounted) setState(() => _myAvatarUrl = profile['avatar_url']);
    } catch (_) {
      final cached = await CacheService().readJson(
        CacheService().scoped(userId, 'profile:$userId'),
      );
      if (cached is Map && mounted) {
        setState(() => _myAvatarUrl = cached['avatar_url']);
      }
    }
  }

  String _getDisplayText() {
    final msg = widget.message;
    if (msg.msgType == 'text') {
      final parsed = MessageParser.parseV2(msg.body);
      return parsed['text'] ?? '';
    }
    if (msg.msgType == 'image') return '[图片]';
    if (msg.msgType == 'voice') return '[语音]';
    if (msg.msgType == 'video') return '[视频]';
    if (msg.msgType == 'file' || msg.msgType == 'resource') return '[文件]';
    if (msg.msgType == 'red_packet') return '[红包]';
    return msg.body;
  }

  void _showImage(String url) {
    final fullUrl = resolveMediaUrl(url);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ImageViewer(imageUrl: fullUrl)));
  }

  Future<void> _saveImageToLocal(String url) async {
    final path = await ImageSaver.saveImage(url);
    if (path != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('图片已保存到: $path')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败')));
    }
  }

  void _showImageSaveMenu(String url) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('保存图片'),
              onTap: () {
                Navigator.pop(context);
                _saveImageToLocal(url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('查看原图'),
              onTap: () {
                Navigator.pop(context);
                _showImage(url);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getQuoteDisplayText(Map<String, dynamic> quote) {
    final quoteType = quote['type'] ?? 'text';
    final quoteText =
        (quote['text'] ?? quote['body'] ?? quote['content'] ?? '').toString();
    if (quoteType == 'image') return '[图片]';
    if (quoteType == 'video') return '[视频]';
    if (quoteType == 'voice') return '[语音]';
    if (quoteType == 'file' || quoteType == 'resource') return '[文件]';
    if (quoteType == 'red_packet') return '[红包]';
    if (quoteType == 'recall') return '[消息已撤回]';
    final result = MessageParser.extractPlainText(quoteText).trim();
    if (result.isNotEmpty) return result;
    final media = quote['media_url'] ?? quote['url'] ?? quote['mediaUrl'];
    if (media != null && media.toString().trim().isNotEmpty) {
      return quoteType == 'video' ? '[视频]' : '[媒体]';
    }
    return '[原消息内容不可用]';
  }

  Widget _buildMusicCard() {
    final msg = widget.message;
    String title = '未知歌曲';
    String artist = '未知歌手';
    String durationStr = '00:00';
    String coverUrl = '';
    String audioUrl = msg.mediaUrl ?? '';

    if (msg.body.isNotEmpty && msg.body.trim().startsWith('{')) {
      try {
        final json = jsonDecode(msg.body);
        if (json is Map) {
          final text = json['text'] ?? '';
          final lines = text.split('\n');
          for (var line in lines) {
            if (line.startsWith('歌曲:')) {
              title = line.replaceFirst('歌曲:', '').trim();
            } else if (line.startsWith('歌手:')) {
              artist = line.replaceFirst('歌手:', '').trim();
            } else if (line.startsWith('时长:')) {
              durationStr = line.replaceFirst('时长:', '').trim();
            }
          }
          coverUrl = msg.thumbUrl ?? '';
        }
      } catch (_) {}
    }

    final cover = resolveMediaUrl(coverUrl);
    final audio = resolveMediaUrl(audioUrl);
    final bool isPlaying =
        _audioService.currentUrl == audio && _audioService.isPlaying;
    final double progress = _audioService.duration.inMilliseconds > 0
        ? (_audioService.position.inMilliseconds /
                _audioService.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final String currentTimeStr = _formatVoiceTime(_audioService.position);
    final String totalTimeStr = _formatVoiceTime(_audioService.duration);

    return GestureDetector(
      onTap: () {
        if (audio.isNotEmpty) {
          _audioService.play(audio);
        }
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.3,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: cover.isNotEmpty
                      ? Image.network(cover,
                          width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48,
                          height: 48,
                          color: Colors.grey[600],
                          child: const Icon(Icons.music_note)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          maxLines: 1),
                      Text(artist,
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12),
                          maxLines: 1),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white),
                  onPressed: () {
                    if (audio.isNotEmpty) {
                      if (isPlaying) {
                        _audioService.pause();
                      } else {
                        _audioService.play(audio);
                      }
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (isPlaying)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: progress,
                          onChanged: (value) {
                            final seekTo = _audioService.duration * value;
                            _audioService.seek(seekTo);
                          },
                          activeColor: Theme.of(context).colorScheme.primary,
                          inactiveColor: Colors.grey[600],
                          min: 0,
                          max: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$currentTimeStr / $totalTimeStr',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              )
            else
              Text(
                durationStr,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceCard() {
    final msg = widget.message;
    final url = msg.mediaUrl ?? '';
    final durationMs = msg.durationMs;
    final durationStr = durationMs > 0
        ? _formatVoiceTime(Duration(milliseconds: durationMs))
        : '语音';

    final resolvedUrl = resolveMediaUrl(url);
    final isThisPlaying =
        _audioService.currentUrl == resolvedUrl && _audioService.isPlaying;
    final progress = _audioService.duration.inMilliseconds > 0
        ? _audioService.position.inMilliseconds /
            _audioService.duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () {
        if (resolvedUrl.isNotEmpty) {
          _audioService.play(resolvedUrl);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('语音链接无效')),
          );
        }
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isThisPlaying ? Icons.pause : Icons.play_arrow,
                  color: isThisPlaying ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isThisPlaying ? '正在播放...' : durationStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: isThisPlaying ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                    ),
                  ),
                ),
                if (isThisPlaying && _audioService.duration.inMilliseconds > 0)
                  Text(
                    _formatVoiceTime(_audioService.position),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
            if (isThisPlaying && _audioService.duration.inMilliseconds > 0)
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.grey[400],
                color: Theme.of(context).colorScheme.primary,
                minHeight: 3,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardChatCard(Map<String, dynamic> forwardData) {
    final title = forwardData['title'] ?? '聊天记录';
    final items = forwardData['items'] as List? ?? [];
    final count = items.length;

    return GestureDetector(
      onTap: () {
        _showForwardChatDetail(items, title);
      },
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.forward, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '共 $count 条消息',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...items.take(2).map((item) {
                final fromName = item['from_name'] ?? '未知';
                final text = item['text'] ?? '';
                final type = item['type'] ?? 'text';
                String displayText = text;
                if (type == 'image')
                  displayText = '[图片]';
                else if (type == 'video')
                  displayText = '[视频]';
                else if (type == 'voice')
                  displayText = '[语音]';
                else if (type == 'file') displayText = '📄 [文件]';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Text(
                        '$fromName: ',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Expanded(
                        child: Text(
                          displayText,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (items.length > 2)
                Text(
                  '... 等${items.length}条',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showForwardChatDetail(List items, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 500),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.forward, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 4),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final fromName = item['from_name'] ?? '未知';
                    final text = item['text'] ?? '';
                    final type = item['type'] ?? 'text';
                    String displayText = text;
                    if (type == 'image')
                      displayText = '[图片]';
                    else if (type == 'video')
                      displayText = '[视频]';
                    else if (type == 'voice')
                      displayText = '[语音]';
                    else if (type == 'file') displayText = '📄 [文件]';
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$fromName: ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Expanded(
                          child: Text(
                            displayText,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _parseForwardData() {
    final body = widget.message.body;
    if (body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map && json.containsKey('forward_v2')) {
        return json['forward_v2'];
      }
    } catch (_) {}
    return null;
  }

  bool _isForwardChat() {
    final body = widget.message.body;
    if (body.isEmpty) return false;
    try {
      final json = jsonDecode(body);
      if (json is Map && json.containsKey('forward_v2')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Widget _buildTextContent(BuildContext context) {
    final msg = widget.message;
    final userId = context.read<AuthService>().userId;
    final parsed = MessageParser.parseV2(msg.body);
    final text = parsed['text'] ?? '';
    final quote = parsed['quote'];
    final mentions = parsed['mentions'] as List? ?? [];

    if (_isForwardChat()) {
      final forwardData = _parseForwardData();
      if (forwardData != null) {
        return _buildForwardChatCard(forwardData);
      }
    }

    final trimmedText = text.trim();
    if (trimmedText == '[视频]' || trimmedText == '视频') {
      return VideoPreview(url: _resolveVideoUrl(), thumbnailUrl: msg.thumbUrl);
    }

    if (RegExp(r'^\[图片\]x\d+$').hasMatch(trimmedText) ||
        trimmedText.startsWith('[图片]')) {
      final url = resolveMediaUrl(msg.mediaUrl);
      return GestureDetector(
        onTap: () {
          if (url.isNotEmpty) {
            _showImage(url);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('图片链接无效')),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(trimmedText,
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.w500)),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
            ],
          ),
        ),
      );
    }

    String displayText = text;
    if (mentions.isNotEmpty) {
      for (var m in mentions) {
        final uid = m['uid'] ?? '';
        if (uid.isNotEmpty) {
          final name = _mentionNameCache[uid] ?? uid;
          final regex = RegExp('@${m['name'] ?? uid}', caseSensitive: false);
          displayText = displayText.replaceAllMapped(regex, (match) {
            final isMe = uid == userId;
            return '@${isMe ? '我' : name}';
          });
        }
      }
    }
    displayText = displayText.replaceAll('\\n', '\n');

    final children = <Widget>[];
    if (quote != null) {
      final quoteFrom = (quote['from_name'] ?? quote['sender'] ?? quote['from_uid'] ?? '未知').toString();
      final quoteDisplayText = _getQuoteDisplayText(quote);
      children.add(
        GestureDetector(
          onTap: () {
            final quotedId = quote['id'];
            if (quotedId != null && widget.onQuoteTap != null) {
              widget.onQuoteTap!(quotedId.toString());
            }
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(6)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('引用: $quoteFrom',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(quoteDisplayText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (displayText.isNotEmpty) {
      if (displayText.contains('[歌词]') || displayText.contains('歌词:')) {
        final lyricsText =
            displayText.replaceAll(RegExp(r'\[歌词\]|歌词:'), '').trim();
        if (lyricsText.isNotEmpty) {
          children.add(
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('歌词',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    lyricsText,
                    style: const TextStyle(fontSize: 13),
                    softWrap: true,
                  ),
                ],
              ),
            ),
          );
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }
      }
      children.add(Text(displayText,
          style: const TextStyle(fontSize: 14), softWrap: true));
    } else if (quote == null) {
      children.add(const Text('[空消息]',
          style: TextStyle(fontSize: 14, color: Colors.grey)));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  // ★ 红包卡片
  Widget _buildRedPacketContent() {
    Map<String, dynamic>? redPacket;

    if (widget.message.msgType == 'red_packet' ||
        (widget.message.msgType == 'text' &&
            widget.message.body.trim().startsWith('{'))) {
      try {
        redPacket = jsonDecode(widget.message.body);
      } catch (_) {}
    }

    if (redPacket == null) {
      final parsed = MessageParser.parseV2(widget.message.body);
      redPacket = parsed['redPacket'];
    }

    if (redPacket == null) {
      return Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
          gradient:
              const LinearGradient(colors: [Colors.red, Colors.redAccent]),
        ),
        child: const Text('红包',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      );
    }

    final packetId = redPacket['packet_id'] ?? redPacket['packetId'] ?? '';
    final title = redPacket['text'] ?? redPacket['title'] ?? '恭喜发财';
    final totalAmount =
        redPacket['total_amount'] ?? redPacket['totalAmount'] ?? 0;
    final totalCount = redPacket['total_count'] ?? redPacket['totalCount'] ?? 0;
    final remainingCount =
        redPacket['remaining_count'] ?? redPacket['remainingCount'] ?? 0;
    final coverUrl = redPacket['cover_url'] ?? redPacket['coverUrl'] ?? '';
    final status = redPacket['status'] ?? 'pending';

    final isOwn = widget.isMe;
    final isClaimed = widget.isClaimed || status == 'claimed';
    final bool showClaimButton = !isOwn &&
        !isClaimed &&
        widget.onClaimRedPacket != null &&
        packetId.isNotEmpty;
    final amountDisplay = totalAmount.toString();

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.3,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isClaimed || isOwn ? Colors.grey[700] : Colors.red,
        borderRadius: BorderRadius.circular(10),
        gradient: (isClaimed || isOwn)
            ? null
            : const LinearGradient(
                colors: [Colors.red, Colors.redAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: const Icon(Icons.card_giftcard, size: 24),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '红包',
                      style: TextStyle(
                        color: (isClaimed || isOwn)
                            ? Colors.white70
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: (isClaimed || isOwn)
                              ? Colors.white60
                              : Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        Text(
                          '$amountDisplay 旧币',
                          style: TextStyle(
                            color: (isClaimed || isOwn)
                                ? Colors.white60
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${totalCount}个',
                          style: TextStyle(
                            color: (isClaimed || isOwn)
                                ? Colors.white60
                                : Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        if (remainingCount > 0 && !isClaimed && !isOwn)
                          Text(
                            '· 剩${remainingCount}个',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isClaimed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '已领取',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                )
              else if (isOwn)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '已发送',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                )
              else if (showClaimButton)
                ElevatedButton(
                  onPressed: widget.onClaimRedPacket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('领取',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (coverUrl.isNotEmpty && !isClaimed && !isOwn)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  resolveMediaUrl(coverUrl),
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isMe = widget.isMe;
    final senderDisplayName = _senderName ?? msg.fromUid;

    if (widget.isRedPacket) {
      return GestureDetector(
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                GestureDetector(
                  onLongPress: () {
                    if (widget.onAvatarLongPress != null)
                      widget.onAvatarLongPress!(msg.fromUid, senderDisplayName);
                  },
                  onTap: () => Navigator.pushNamed(context, '/user_profile',
                      arguments: msg.fromUid),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        _avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? NetworkImage(resolveMediaUrl(_avatarUrl!))
                            : null,
                    child: _avatarUrl == null || _avatarUrl!.isEmpty
                        ? Text(senderDisplayName.isNotEmpty
                            ? senderDisplayName.substring(0, 1)
                            : '?')
                        : null,
                  ),
                ),
              const SizedBox(width: 8),
              Flexible(child: _buildRedPacketContent()),
              if (isMe)
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        _myAvatarUrl != null && _myAvatarUrl!.isNotEmpty
                            ? NetworkImage(resolveMediaUrl(_myAvatarUrl!))
                            : null,
                    child: _myAvatarUrl == null || _myAvatarUrl!.isEmpty
                        ? const Text('我')
                        : null,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget content;
    switch (msg.msgType) {
      case 'text':
        content = _buildTextContent(context);
        break;

      case 'image':
        final url = resolveMediaUrl(msg.mediaUrl ?? msg.thumbUrl ?? '');
        content = GestureDetector(
          onLongPress: () => _showImageSaveMenu(url),
          onTap: () => _showImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(image: ImageCacheService.instance.provider(url, cacheWidth: 600),
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                    width: 200,
                    height: 200,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()));
              },
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 50),
            ),
          ),
        );
        break;

      case 'video':
        final url = _resolveVideoUrl();
        content = _buildVideoPlayer(context, url);
        break;

      case 'voice':
        content = _buildVoiceCard();
        break;

      case 'file':
      case 'resource':
        final isMusic = msg.mediaUrl != null &&
            msg.mediaUrl!.isNotEmpty &&
            (msg.mediaUrl!.contains('.mp3') ||
                msg.mediaUrl!.contains('.m4a') ||
                msg.mediaUrl!.contains('.wav') ||
                (msg.body.contains('media_kind') &&
                    msg.body.contains('music')));
        if (isMusic) {
          content = _buildMusicCard();
        } else {
          final fileName = msg.body.isNotEmpty
              ? msg.body
              : (msg.mediaUrl?.split('/').last ?? '文件');
          content = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file),
              const SizedBox(width: 4),
              Expanded(child: Text(fileName, overflow: TextOverflow.ellipsis)),
              if (msg.mediaUrl != null)
                IconButton(
                  icon: const Icon(Icons.download, size: 18),
                  onPressed: () async {
                    final url = resolveMediaUrl(msg.mediaUrl!);
                    try {
                      final result = await DownloadService.download(
                        url,
                        fileName: fileName,
                      );
                      if (!mounted) return;
                      final message = result.usedAria2
                          ? '已交给 aria2 下载（任务 ${result.gid}）'
                          : '已使用默认下载方式保存到：${result.path}';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('下载失败：$e')),
                      );
                    }
                  },
                ),
            ],
          );
        }
        break;

      default:
        content = Text(msg.body);
    }

    final avatarUrl = _avatarUrl != null ? resolveMediaUrl(_avatarUrl!) : '';
    final myAvatar = _myAvatarUrl != null ? resolveMediaUrl(_myAvatarUrl!) : '';
    final double maxBubbleWidth = MediaQuery.of(context).size.width * 0.3;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(widget.isMe ? 12 * (1 - value) : -12 * (1 - value), 0),
          child: child,
        ),
      ),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ★ 头像（支持右键菜单）
              if (!isMe)
                GestureDetector(
                  onLongPress: () {
                    if (widget.onAvatarLongPress != null) {
                      widget.onAvatarLongPress!(msg.fromUid, senderDisplayName);
                    }
                  },
                  // ★ 右键点击头像
                  onSecondaryTapDown: (details) {
                    if (widget.onAvatarSecondaryTap != null) {
                      widget.onAvatarSecondaryTap!(msg.fromUid,
                          senderDisplayName, details.globalPosition);
                    }
                  },
                  onTap: () => Navigator.pushNamed(context, '/user_profile',
                      arguments: msg.fromUid),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(senderDisplayName.isNotEmpty
                            ? senderDisplayName.substring(0, 1)
                            : '?')
                        : null,
                  ),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 5),
                        bottomRight: Radius.circular(isMe ? 5 : 18),
                      ),
                      border: Border.all(
                        color: isMe
                            ? Theme.of(context).colorScheme.primary.withOpacity(.55)
                            : Theme.of(context).colorScheme.outline.withOpacity(.35),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(senderDisplayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        content,
                        const SizedBox(height: 4),
                        Text(_formatTime(msg.createdAt),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              if (isMe)
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        myAvatar.isNotEmpty ? NetworkImage(myAvatar) : null,
                    child: myAvatar.isEmpty ? const Text('我') : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildVideoPlayer(BuildContext context, String url) {
    return VideoPreview(url: url, thumbnailUrl: widget.message.thumbUrl);
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;

  const _InlineVideoPlayer({required this.url, this.thumbnailUrl});

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _error = '视频链接无效');
      return;
    }
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(resolveMediaUrl(widget.url)),
        httpHeaders: const {'Accept': '*/*'},
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final chewieController = ChewieController(
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
        _chewieController = chewieController;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '视频加载失败：$error');
    }
  }

  Future<void> _openBrowser() async {
    if (_opening || widget.url.isEmpty) return;
    setState(() => _opening = true);
    final uri = Uri.tryParse(resolveMediaUrl(widget.url));
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) setState(() => _opening = false);
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _VideoFallback(url: widget.url, message: _error!);
    }
    if (_chewieController == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.url.isNotEmpty)
            SizedBox(
              width: 280,
              height: 158,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.url.isNotEmpty)
                    Image.network(
                      resolveMediaUrl(widget.url),
                      width: 280,
                      height: 158,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          _VideoBrowserButton(url: widget.url),
        ],
      );
    }
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Chewie(controller: _chewieController!),
          ),
          _VideoBrowserButton(url: widget.url),
        ],
      ),
    );
  }
}

class _VideoFallback extends StatelessWidget {
  final String url;
  final String message;
  final String? thumbnailUrl;

  const _VideoFallback({required this.url, required this.message, this.thumbnailUrl});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(resolveMediaUrl(url));
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveMediaUrl(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
          Image.network(resolveMediaUrl(thumbnailUrl!), height: 100, fit: BoxFit.cover),
        Text(message, style: const TextStyle(color: Colors.red, fontSize: 12)),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('用浏览器打开'),
            ),
            TextButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(resolvedUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('系统播放器打开'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VideoBrowserButton extends StatelessWidget {
  final String url;
  const _VideoBrowserButton({required this.url});

  Future<void> _open() async {
    final fullUrl = resolveMediaUrl(url);
    final uri = Uri.tryParse(fullUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: url.isEmpty ? null : _open,
          icon: const Icon(Icons.open_in_browser, size: 16),
          label: const Text('用浏览器打开'),
        ),
      );
}
