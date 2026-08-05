import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../widgets/conversation_tile.dart';
import '../pages/chat_page.dart';
import '../pages/login_page.dart';
import '../pages/profile_page.dart';
import '../pages/moments_page.dart';
import '../pages/music_plaza_page.dart';
import '../pages/emoji_plaza_page.dart';
import '../pages/notifications_page.dart';
import '../pages/checkin_wall_page.dart';
import '../pages/ai_chat_page.dart';
import '../pages/favorites_page.dart';
import '../pages/about_page.dart';
import '../pages/settings_page.dart';
import '../utils/navigation.dart';
import '../utils/url_helper.dart';
import '../services/cache_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Conversation> _groups = [];
  List<Conversation> _friends = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  Map<String, int> _unreadCounts = {};
  final Map<String, bool> _pinnedMap = {};
  Conversation? _currentConversation;
  int _totalUnread = 0;
  int _friendRequestCount = 0; // ★ 好友申请未读数
  Timer? _searchTimer;
  Timer? _unreadReloadTimer;
  String? _avatarUrl;
  final Set<String> _realtimeMessageIds = <String>{};
  final Map<String, int> _realtimeUnreadPending = <String, int>{};

  @override
  void initState() {
    super.initState();
    _restoreCachedConversations();
    _ensureUserCacheDirectory();
    _loadConversations();
    _loadPinnedState();
    _loadUnreadCounts();
    _setupWebSocket();
    _loadUserAvatar();
  }

  Future<void> _ensureUserCacheDirectory() async {
    final uid = context.read<AuthService>().userId;
    if (uid != null) await CacheService().directory(userId: uid);
  }

  Future<void> _restoreCachedConversations() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    final cached = await CacheService().readJson(
      CacheService().scoped(uid, 'conversations'),
    );
    if (cached is! List || !mounted) return;
    final conversations = cached
        .whereType<Map>()
        .map((item) => Conversation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    if (!mounted) return;
    setState(() {
      _friends = conversations.where((c) => c.type == 'direct').toList();
      _groups = conversations.where((c) => c.type == 'group').toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    WebSocketService().removeDirectListener(_onNewMessage);
    WebSocketService().removeGroupListener(_onNewMessage);
    _searchTimer?.cancel();
    _unreadReloadTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAvatar() async {
    final auth = context.read<AuthService>();
    final uid = auth.userId;
    if (uid == null) return;
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(uid);
      await CacheService().writeJson(
        CacheService().scoped(uid, 'profile:$uid'),
        profile,
      );
      if (mounted) {
        setState(() {
          _avatarUrl = profile['avatar_url'];
        });
      }
    } catch (_) {
      final cached = await CacheService().readJson(
        CacheService().scoped(uid, 'profile:$uid'),
      );
      if (cached is Map && mounted) {
        setState(() => _avatarUrl = cached['avatar_url']);
      }
    }
  }

  void _setupWebSocket() {
    final ws = WebSocketService();
    ws.addDirectListener(_onNewMessage);
    ws.addGroupListener(_onNewMessage);
    ws.connect();
  }

  String _pinPreferenceKey(String userId, String conversationKey) =>
      'oldchat_pin:$userId:$conversationKey';

  Future<void> _loadPinnedState() async {
    final userId = context.read<AuthService>().userId;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final loaded = <String, bool>{};
    final newPrefix = 'oldchat_pin:$userId:';
    final legacyPrefix = 'oldchat:$userId:pinned:';
    for (final key in prefs.getKeys()) {
      String? conversationKey;
      if (key.startsWith(newPrefix)) {
        conversationKey = key.substring(newPrefix.length);
      } else if (key.startsWith(legacyPrefix)) {
        conversationKey = key.substring(legacyPrefix.length);
      }
      if (conversationKey == null || conversationKey.isEmpty) continue;
      final stored = prefs.getBool(key);
      if (stored != null) loaded[conversationKey] = stored;
    }
    if (!mounted) return;
    setState(() {
      _pinnedMap
        ..clear()
        ..addAll(loaded);
    });
  }

  void _onNewMessage(Message msg) {
    if (!mounted) return;
    if (!_realtimeMessageIds.add(msg.id)) return;
    if (_realtimeMessageIds.length > 5000) {
      _realtimeMessageIds.remove(_realtimeMessageIds.first);
    }
    final userId = context.read<AuthService>().userId;
    if (msg.fromUid == userId) return;

    final key = msg.groupId == null ? 'direct:${msg.fromUid}' : 'group:${msg.groupId}';
    final isCurrentConversation = _currentConversation != null &&
        _currentConversation!.id == (msg.groupId ?? msg.fromUid) &&
        _currentConversation!.type == (msg.groupId == null ? 'direct' : 'group');
    setState(() {
      if (!isCurrentConversation) {
        _unreadCounts[key] = (_unreadCounts[key] ?? 0) + 1;
      }
      _totalUnread = _unreadCounts.values.fold(0, (sum, count) => sum + count);
      final all = [..._groups, ..._friends];
      final index = all.indexWhere((conversation) =>
          conversation.id == (msg.groupId ?? msg.fromUid) &&
          conversation.type == (msg.groupId == null ? 'direct' : 'group'));
      if (index >= 0) {
        final conversation = all[index];
        final updated = Conversation(
          id: conversation.id,
          type: conversation.type,
          name: conversation.name,
          avatar: conversation.avatar,
          lastMessage: msg,
          unreadCount: isCurrentConversation
              ? conversation.unreadCount
              : conversation.unreadCount + 1,
          pinned: conversation.pinned,
        );
        if (conversation.type == 'group') {
          _groups[_groups.indexOf(conversation)] = updated;
        } else {
          _friends[_friends.indexOf(conversation)] = updated;
        }
      }
    });

    _unreadReloadTimer?.cancel();
    _unreadReloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) unawaited(_loadUnreadCounts(excludeKey: isCurrentConversation ? key : null));
    });
    NotificationService().showMessageNotification(
      fromName: msg.fromUid,
      message: msg.body,
      conversationId: msg.groupId ?? msg.fromUid,
      conversationType: msg.groupId != null ? 'group' : 'direct',
    );
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    final hadVisibleData = _friends.isNotEmpty || _groups.isNotEmpty;
    if (!hadVisibleData && mounted) setState(() => _loading = true);
    try {
      final api = ApiService();
      final results = await Future.wait<dynamic>([
        api.getFriends(),
        api.getGroups(),
      ]);
      final friends = results[0] as List<Conversation>;
      final groups = results[1] as List<Conversation>;
      if (mounted) {
        setState(() {
          _friends = friends;
          _groups = groups;
          _error = null;
          _loading = false;
          if (_currentConversation != null) {
            final all = [...groups, ...friends];
            if (!all.any((c) =>
                c.id == _currentConversation!.id &&
                c.type == _currentConversation!.type)) {
              _currentConversation = null;
            }
          }
        });
        final userId = context.read<AuthService>().userId;
        if (userId != null) {
          await CacheService().writeJson(
            CacheService().scoped(userId, 'conversations'),
            [...groups, ...friends].map((c) => c.toJson()).toList(),
          );
          await _loadPinnedState();
        }
      }
    } catch (e) {
      final userId = context.read<AuthService>().userId;
      final cached = userId == null
          ? null
          : await CacheService().readJson(
              CacheService().scoped(userId, 'conversations'),
            );
      if (cached is List && mounted) {
        final conversations = cached
            .whereType<Map>()
            .map((e) => Conversation.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList();
        setState(() {
          _friends = conversations.where((c) => c.type == 'direct').toList();
          _groups = conversations.where((c) => c.type == 'group').toList();
          _loading = false;
          _error = null;
        });
      } else if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _loadUnreadCounts({String? excludeKey}) async {
    try {
      final api = ApiService();
      final directUnread = await api.getDirectUnread();
      final groupUnread = await api.getGroupUnread();
      Map<String, int> counts = {};
      (directUnread['messages'] as List?)?.forEach((m) {
        final uid = m['from_uid'];
        final readAt = (m['read_at'] as num?)?.toInt();
        if (uid != null &&
            uid != context.read<AuthService>().userId &&
            (readAt == null || readAt == 0)) {
          final key = 'direct:$uid';
          counts[key] = (counts[key] ?? 0) + 1;
        }
      });
      (groupUnread['messages'] as List?)?.forEach((m) {
        final gid = m['group_id'];
        final readAt = (m['read_at'] as num?)?.toInt();
        if (gid != null && (readAt == null || readAt == 0)) {
          final key = 'group:$gid';
          counts[key] = (counts[key] ?? 0) + 1;
        }
      });

      // ★ 获取好友申请数
      int requestCount = 0;
      try {
        final requests = await api.getFriendRequests();
        final list = requests['requests'] as List?;
        if (list != null) {
          // 过滤：只计数 pending 的申请（未处理）
          requestCount = list.where((r) => r['status'] == 'pending').length;
        }
      } catch (_) {}

      for (final entry in _realtimeUnreadPending.entries) {
        final serverCount = counts[entry.key] ?? 0;
        if (entry.value > serverCount) counts[entry.key] = entry.value;
      }
      final activeKey = excludeKey ??
          (_currentConversation == null ? null : _conversationKey(_currentConversation!));
      if (activeKey != null) counts.remove(activeKey);
      if (mounted) {
        setState(() {
          _unreadCounts = counts;
          _totalUnread = counts.values.fold(0, (sum, count) => sum + count);
          _friendRequestCount = requestCount;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unreadCounts = {};
          _totalUnread = 0;
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      await Future.wait([
        _loadConversations(),
        _loadUnreadCounts(),
        _loadUserAvatar(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _conversationKey(Conversation conv) => '${conv.type}:${conv.id}';

  bool _isPinned(Conversation conv) =>
      _pinnedMap[_conversationKey(conv)] ?? conv.pinned;

  List<Conversation> _sortConversations(List<Conversation> conversations) {
    final list = List<Conversation>.from(conversations);
    list.sort((a, b) {
      final aPinned = _isPinned(a);
      final bPinned = _isPinned(b);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      final aLast = a.lastMessage;
      final bLast = b.lastMessage;
      if (aLast != null && bLast != null) {
        final last = bLast.createdAt.compareTo(aLast.createdAt);
        if (last != 0) return last;
        final id = bLast.id.compareTo(aLast.id);
        if (id != 0) return id;
      } else if (aLast != null || bLast != null) {
        return aLast != null ? -1 : 1;
      }
      final aUnread = _unreadCounts[_conversationKey(a)] ?? 0;
      final bUnread = _unreadCounts[_conversationKey(b)] ?? 0;
      if (aUnread != bUnread) return bUnread.compareTo(aUnread);
      final aName = (a.name ?? a.id).toLowerCase();
      final bName = (b.name ?? b.id).toLowerCase();
      return aName.compareTo(bName);
    });
    return list;
  }

  Future<void> _togglePinConversation(Conversation conv) async {
    final key = _conversationKey(conv);
    final value = !(_pinnedMap[key] ?? conv.pinned);
    setState(() {
      _pinnedMap[key] = value;
    });
    final userId = context.read<AuthService>().userId;
    if (userId != null && userId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pinPreferenceKey(userId, key), value);
      await prefs.remove('oldchat:$userId:pinned:$key');
    }
  }

  void _showConversationMenu(
      BuildContext context, Conversation conv, TapDownDetails details) {
    final key = _conversationKey(conv);
    final isPinned = _pinnedMap[key] ?? conv.pinned;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: isPinned ? 'unpin' : 'pin',
          child: Row(
            children: [
              Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  size: 18),
              const SizedBox(width: 8),
              Text(isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'pin' || value == 'unpin') {
        _togglePinConversation(conv);
      }
    });
  }

  void _selectConversation(Conversation conv) async {
    setState(() {
      _currentConversation = conv;
      _unreadCounts.remove(_conversationKey(conv));
      _realtimeUnreadPending.remove(_conversationKey(conv));
      _totalUnread = _unreadCounts.values.fold(0, (sum, count) => sum + count);
    });
    try {
      final api = ApiService();
      if (conv.type == 'direct') {
        await api.markDirectRead(conv.id);
      } else {
        await api.markGroupRead(conv.id);
      }
      await _loadUnreadCounts();
    } catch (_) {}
  }

  void _logout() async {
    await context.read<AuthService>().clear();
    WebSocketService().disconnect();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  int get displayUnread {
    // 总未读 = 消息未读 + 好友申请未读
    final raw = _totalUnread + _friendRequestCount;
    if (raw <= 4) return 0;
    return raw - 4;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('加载失败: $_error'),
                      TextButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          _buildToolbar(),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: '搜索好友或群聊...',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[200],
                              ),
                              onChanged: (q) {
                                _searchTimer?.cancel();
                                _searchTimer = Timer(
                                    const Duration(milliseconds: 300), () {
                                  setState(() {});
                                });
                              },
                            ),
                          ),
                          Expanded(child: _buildList()),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _currentConversation == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline,
                                      size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('选择一个会话开始聊天',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600])),
                                ],
                              ),
                            )
                          : ChatPage(
                              key: ValueKey(
                                  '${_currentConversation!.type}:${_currentConversation!.id}'),
                              conversationId: _currentConversation!.id,
                              type: _currentConversation!.type,
                              title: _currentConversation!.name ?? '聊天',
                              embed: true,
                              onMessageSent: () {
                                unawaited(_loadConversations());
                                unawaited(_loadUnreadCounts());
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildToolbar() {
    final primaryColor = Theme.of(context).primaryColor;
    final avatarUrl = _avatarUrl != null ? resolveMediaUrl(_avatarUrl) : null;
    final displayTotal = displayUnread;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: primaryColor),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? const Icon(Icons.person, size: 20, color: Colors.pink)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          if (displayTotal > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text(
                displayTotal > 99 ? '99+' : '$displayTotal',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          const Spacer(),
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _refresh,
            tooltip: '刷新会话列表',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          _buildMusicButton(),
          _buildToolbarButton(Icons.photo_album, '/moments', '动态'),
          _buildEmojiButton(),
          // ★ 通知按钮显示好友申请红点
          IconButton(
            icon:
                const Icon(Icons.notifications, color: Colors.white, size: 20),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
            tooltip: '通知',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.white,
            onSelected: (value) {
              if (value == 'logout')
                _logout();
              else
                Navigator.pushNamed(context, value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: '/favorites', child: Text('我的收藏')),
              const PopupMenuItem(value: '/checkin_wall', child: Text('签到墙')),
              const PopupMenuItem(value: '/ai_chat', child: Text('AI助手')),
              const PopupMenuItem(value: '/settings', child: Text('设置')),
              const PopupMenuItem(value: '/about', child: Text('关于 OldChat')),
              const PopupMenuItem(
                  value: 'logout',
                  child: Text('退出登录', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMusicButton() {
    return IconButton(
      icon: const Icon(Icons.music_note, color: Colors.white, size: 20),
      onPressed: () async {
        final result = await Navigator.pushNamed(context, '/music_plaza');
        if (result != null &&
            result is Map<String, dynamic> &&
            _currentConversation != null) {
          final conv = _currentConversation!;
          final api = ApiService();
          final String audioUrl = result['song_url'] ?? result['url'] ?? '';
          final String coverUrl = result['cover'] ?? '';
          final String title = result['text'] ?? '未知歌曲';
          final String artist = result['artist'] ?? '未知歌手';
          final String duration = result['duration'] ?? '00:00';

          final bodyJson = jsonEncode({
            'v': 2,
            'text': '歌曲: $title\n歌手: $artist\n时长: $duration\n点击播放',
            'media_kind': 'music',
          });

          try {
            if (conv.type == 'direct') {
              await api.sendDirectMessage(
                toUid: conv.id,
                body: bodyJson,
                msgType: 'resource',
                mediaUrl: audioUrl,
                thumbUrl: coverUrl,
              );
            } else {
              await api.sendGroupMessage(
                groupId: conv.id,
                body: bodyJson,
                msgType: 'resource',
                mediaUrl: audioUrl,
                thumbUrl: coverUrl,
              );
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('音乐已分享')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('分享失败: $e')),
            );
          }
        }
      },
      tooltip: '音乐广场',
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildEmojiButton() {
    return IconButton(
      icon: const Icon(Icons.emoji_emotions, color: Colors.white, size: 20),
      onPressed: () async {
        final url =
            await Navigator.pushNamed(context, '/emoji_plaza') as String?;
        if (url != null && url.isNotEmpty && _currentConversation != null) {
          final conv = _currentConversation!;
          final api = ApiService();
          try {
            if (conv.type == 'direct') {
              await api.sendDirectMessage(
                  toUid: conv.id, body: '', msgType: 'image', mediaUrl: url);
            } else {
              await api.sendGroupMessage(
                  groupId: conv.id, body: '', msgType: 'image', mediaUrl: url);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('表情已发送')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('发送失败: $e')),
            );
          }
        }
      },
      tooltip: '表情',
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildToolbarButton(IconData icon, String route, String tooltip) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: () => Navigator.pushNamed(context, route),
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildList() {
    final query = _searchController.text.trim().toLowerCase();
    final filteredFriends = _sortConversations(
      _friends
          .where((c) =>
              c.name?.toLowerCase().contains(query) == true ||
              c.id.toLowerCase().contains(query))
          .toList(),
    );
    final filteredGroups = _sortConversations(
      _groups
          .where((c) =>
              c.name?.toLowerCase().contains(query) == true ||
              c.id.toLowerCase().contains(query))
          .toList(),
    );

    if (filteredFriends.isEmpty && filteredGroups.isEmpty) {
      return const Center(child: Text('没有匹配的会话'));
    }

    return ListView(
      children: [
        if (filteredGroups.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('群聊',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey)),
          ),
          ...filteredGroups.map((conv) => ConversationTile(
                conversation: conv,
                unreadCount: _unreadCounts['group:${conv.id}'] ?? 0,
                onTap: () => _selectConversation(conv),
                onSecondaryTapDown: (details) =>
                    _showConversationMenu(context, conv, details),
                isActive: _currentConversation?.id == conv.id &&
                    _currentConversation?.type == 'group',
                isPinned: _isPinned(conv),
              )),
        ],
        if (filteredFriends.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('私聊',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey)),
          ),
          ...filteredFriends.map((conv) => ConversationTile(
                conversation: conv,
                unreadCount: _unreadCounts['direct:${conv.id}'] ?? 0,
                onTap: () => _selectConversation(conv),
                onSecondaryTapDown: (details) =>
                    _showConversationMenu(context, conv, details),
                isActive: _currentConversation?.id == conv.id &&
                    _currentConversation?.type == 'direct',
                isPinned: _isPinned(conv),
              )),
        ],
      ],
    );
  }
}
