import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/cache_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/image_cache_service.dart';
import '../models/message.dart';
import '../utils/message_parser.dart';
import '../widgets/message_tile.dart';
import '../pages/user_profile_page.dart';
import '../utils/url_helper.dart';
import '../utils/navigation.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String type;
  final String title;
  final bool embed;
  final VoidCallback? onMessageSent;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.type,
    required this.title,
    this.embed = false,
    this.onMessageSent,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with RouteAware, WidgetsBindingObserver {
  final List<Message> _messages = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  String? _nextBeforeCreatedAt;
  String? _nextBeforeId;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  Timer? _pollTimer;
  int? _pollGeneration;
  Message? _quotedMessage;
  final Map<String, GlobalKey> _messageKeys = {};
  bool _isFriend = false;
  bool _isCheckingFriend = true;
  Set<String> _claimedPackets = {};
  int? _firstUnreadIndex;
  bool _showUnreadButton = false;
  bool _isUserAtBottom = true;
  bool _cacheHydrated = false;
  bool _isVisible = true;
  bool _routeSubscribed = false;
  PageRoute<dynamic>? _observedRoute;
  int? _lastMessageCreatedAt;
  String? _lastMessageId;
  int _lastGroupSeq = 0;
  final Map<String, Message> _messageMap = {};
  bool _realtimeSyncInFlight = false;
  bool _initialLoadFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFriendStatus();
    final ws = WebSocketService();
    ws.addDirectListener(_onNewMessage);
    ws.addGroupListener(_onNewMessage);
    ws.connect();
    _scrollController.addListener(_onScroll);
    unawaited(_loadMessages(initial: true));
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      _observedRoute = route;
      routeObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  void _setVisible(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (visible) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void didPushNext() => _setVisible(false);

  @override
  void didPopNext() => _setVisible(true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setVisible(state == AppLifecycleState.resumed);
  }

  void _refreshUnreadButtonState() {
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50;
    final shouldShowUnread = !isAtBottom &&
        _firstUnreadIndex != null &&
        _firstUnreadIndex! >= 0 &&
        _firstUnreadIndex! < _messages.length;
    if (_isUserAtBottom != isAtBottom ||
        _showUnreadButton != shouldShowUnread) {
      setState(() {
        _isUserAtBottom = isAtBottom;
        _showUnreadButton = shouldShowUnread;
      });
    }
  }

  void _onScroll() {
    _refreshUnreadButtonState();
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <= 160 &&
        !_loading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMessages();
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed && _observedRoute != null) {
      routeObserver.unsubscribe(this);
    }
    WebSocketService().removeDirectListener(_onNewMessage);
    WebSocketService().removeGroupListener(_onNewMessage);
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFriendStatus() async {
    if (widget.type != 'direct') {
      setState(() => _isCheckingFriend = false);
      return;
    }
    try {
      final api = ApiService();
      final friends = await api.getFriends();
      setState(() {
        _isFriend = friends.any((f) => f.id == widget.conversationId);
        _isCheckingFriend = false;
      });
    } catch (_) {
      setState(() => _isCheckingFriend = false);
    }
  }

  int _compareMessages(Message a, Message b) {
    if (widget.type == 'group' &&
        a.groupSeq != null &&
        b.groupSeq != null &&
        a.groupSeq != b.groupSeq) {
      return a.groupSeq!.compareTo(b.groupSeq!);
    }
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  }

  void _updatePollCursor(Message msg, {bool fromWebSocket = false}) {
    if (widget.type == 'group') {
      if (msg.groupSeq != null) {
        _lastGroupSeq =
            _lastGroupSeq < msg.groupSeq! ? msg.groupSeq! : _lastGroupSeq;
      }
      return;
    }
    if (_lastMessageCreatedAt == null ||
        msg.createdAt > _lastMessageCreatedAt! ||
        (msg.createdAt == _lastMessageCreatedAt! &&
            (msg.id.compareTo(_lastMessageId ?? '') > 0))) {
      _lastMessageCreatedAt = msg.createdAt;
      _lastMessageId = msg.id;
    }
  }

  void _rebuildMessageMap() {
    _messageMap
      ..clear()
      ..addEntries(_messages.map((message) => MapEntry(message.id, message)));
  }

  void _addLocalMessage(Message message) {
    if (_messageMap.containsKey(message.id)) return;
    _messageMap[message.id] = message;
    _updatePollCursor(message);
    _messages.add(message);
    _messageKeys[message.id] = GlobalKey();
  }

  void _onNewMessage(Message msg) {
    if (!mounted || !_isVisible) return;
    if (widget.type == 'direct' &&
        msg.fromUid != widget.conversationId &&
        msg.threadId != widget.conversationId &&
        msg.threadId != null) return;
    if (widget.type == 'group' && msg.groupId != widget.conversationId) return;
    if (_messageMap.containsKey(msg.id)) return;
    if (widget.type == 'direct' &&
        msg.fromUid == context.read<AuthService>().userId &&
        msg.threadId != widget.conversationId) return;
    final wasAtBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            80;
    _isUserAtBottom = wasAtBottom;
    _messageMap[msg.id] = msg;
    _updatePollCursor(msg, fromWebSocket: true);
    final insertAt = _messages.indexWhere((existing) => _compareMessages(existing, msg) > 0);
    setState(() {
      if (insertAt < 0) {
        _messages.add(msg);
      } else {
        _messages.insert(insertAt, msg);
      }
      _messageKeys[msg.id] = GlobalKey();
    });
    unawaited(_saveCachedMessages());
    if (wasAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isVisible) unawaited(_scheduleScrollToBottom());
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_isVisible) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isVisible || _isLoadingMore || _loading) return;
      unawaited(_syncIncrementalMessages());
    });
  }

  Future<void> _syncIncrementalMessages() async {
    if (_realtimeSyncInFlight || !_isVisible || !mounted) return;
    if (!_initialLoadFinished && _messages.isEmpty) return;
    _realtimeSyncInFlight = true;
    try {
      final api = ApiService();
      final result = widget.type == 'group'
          ? await api.getGroupMessagesAfter(widget.conversationId, _lastGroupSeq)
          : (_lastMessageCreatedAt == null
              ? <String, dynamic>{'messages': const <Message>[]}
              : await api.getDirectMessages(
                  withUid: widget.conversationId,
                  limit: 100,
                  afterCreatedAt: _lastMessageCreatedAt,
                  afterId: _lastMessageId,
                ));
      if (!mounted || !_isVisible) return;
      final newMessages = (result['messages'] as List<Message>?) ?? const <Message>[];
      final relevantMessages = newMessages.where((message) {
        if (widget.type == 'group') return message.groupId == widget.conversationId;
        return message.fromUid == widget.conversationId ||
            message.threadId == widget.conversationId ||
            message.fromUid == context.read<AuthService>().userId;
      }).toList();
      if (widget.type == 'group') {
        final nextSeq = int.tryParse('${result['next_group_seq'] ?? _lastGroupSeq}') ?? _lastGroupSeq;
        if (nextSeq > _lastGroupSeq) _lastGroupSeq = nextSeq;
      }
      final wasAtBottom = _isUserAtBottom;
      _insertRealtimeMessages(relevantMessages);
      if (relevantMessages.isNotEmpty && wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isVisible) unawaited(_scheduleScrollToBottom(animate: false));
        });
      }
    } catch (error) {
      debugPrint('[实时同步慢] $error');
    } finally {
      _realtimeSyncInFlight = false;
    }
  }

  void _insertRealtimeMessages(List<Message> messages) {
    final newOnes = <Message>[];
    for (final message in messages) {
      if (_messageMap.containsKey(message.id)) continue;
      _messageMap[message.id] = message;
      _updatePollCursor(message);
      newOnes.add(message);
    }
    if (newOnes.isEmpty) return;
    setState(() {
      _messages.addAll(newOnes);
      _messages.sort(_compareMessages);
      for (final message in newOnes) {
        _messageKeys[message.id] = GlobalKey();
      }
    });
    unawaited(_saveCachedMessages());
  }

  Future<void> _loadMessages({bool initial = false}) async {
    if (!_isVisible || _loading || (!_hasMore && !initial)) return;
    if (initial && !_cacheHydrated) await _restoreCachedMessages();
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final result = widget.type == 'direct'
          ? await api.getDirectMessages(
              withUid: widget.conversationId,
              limit: initial ? 15 : 30,
              offset: _offset,
              beforeCreatedAt: !initial &&
                      _nextBeforeCreatedAt != null &&
                      _nextBeforeCreatedAt!.isNotEmpty
                  ? _nextBeforeCreatedAt
                  : null,
              beforeId:
                  !initial && _nextBeforeId != null && _nextBeforeId!.isNotEmpty
                      ? _nextBeforeId
                      : null,
            )
          : await api.getGroupMessages(
              groupId: widget.conversationId,
              limit: initial ? 15 : 30,
              offset: _offset,
              beforeCreatedAt: !initial &&
                      _nextBeforeCreatedAt != null &&
                      _nextBeforeCreatedAt!.isNotEmpty
                  ? _nextBeforeCreatedAt
                  : null,
              beforeId:
                  !initial && _nextBeforeId != null && _nextBeforeId!.isNotEmpty
                      ? _nextBeforeId
                      : null,
            );
      final newMessages = (result['messages'] as List<Message>?) ?? [];

      if (initial) {
        setState(() {
          final byId = <String, Message>{
            for (final message in _messages) message.id: message,
          };
          for (final message in newMessages) byId[message.id] = message;
          final sorted = byId.values.toList()..sort(_compareMessages);
          _messages
            ..clear()
            ..addAll(sorted);
          _messageMap.clear();
          _messageKeys.clear();
          for (var m in sorted) {
            _messageMap[m.id] = m;
            _updatePollCursor(m);
            _messageKeys[m.id] = GlobalKey();
          }
          _firstUnreadIndex = _messages.indexWhere(
            (m) =>
                m.fromUid != context.read<AuthService>().userId &&
                (m.readAt == null || m.readAt == 0),
          );
          if (_firstUnreadIndex == -1) {
            _firstUnreadIndex = null;
          }
          _hasMore = result['has_more'] ?? false;
          _nextBeforeCreatedAt = result['next_before_created_at']?.toString();
          _nextBeforeId = result['next_before_id']?.toString();
          _offset = result['effective_offset'] ?? _offset + newMessages.length;
          _loading = false;
          _initialLoadFinished = true;
        });
        await _saveCachedMessages();
        if (_messages.any((m) =>
            m.fromUid != context.read<AuthService>().userId &&
            (m.readAt == null || m.readAt == 0))) {
          unawaited(_markConversationRead());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleScrollToBottom();
        });
      } else {
        final oldFirstId = _messages.isEmpty ? null : _messages.first.id;
        final oldFirstKey =
            oldFirstId == null ? null : _messageKeys[oldFirstId];
        final oldFirstDy = oldFirstKey?.currentContext == null
            ? null
            : (oldFirstKey!.currentContext!.findRenderObject() as RenderBox)
                .localToGlobal(Offset.zero)
                .dy;

        final olderMessages = newMessages.toList()..sort(_compareMessages);
        final toAdd = olderMessages
            .where((m) => !_messageMap.containsKey(m.id))
            .toList();
        final combined = [...toAdd, ..._messages]..sort(_compareMessages);

        setState(() {
          _messages.clear();
          _messageMap.clear();
          _messages.addAll(combined);
          for (var m in combined) {
            _messageMap[m.id] = m;
            _updatePollCursor(m);
          }
          for (var m in toAdd) {
            if (!_messageKeys.containsKey(m.id)) {
              _messageKeys[m.id] = GlobalKey();
            }
          }
          _hasMore = result['has_more'] ?? false;
          _nextBeforeCreatedAt = result['next_before_created_at']?.toString();
          _nextBeforeId = result['next_before_id']?.toString();
          _offset = result['effective_offset'] ?? _offset + newMessages.length;
          _loading = false;
          _isLoadingMore = false;
        });
        await _saveCachedMessages();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newFirstKey =
                oldFirstId == null ? null : _messageKeys[oldFirstId];
            final newFirstDy = newFirstKey?.currentContext == null
                ? null
                : (newFirstKey!.currentContext!.findRenderObject() as RenderBox)
                    .localToGlobal(Offset.zero)
                    .dy;
            if (oldFirstDy != null && newFirstDy != null) {
              final target =
                  (_scrollController.offset + oldFirstDy - newFirstDy)
                      .clamp(0.0, _scrollController.position.maxScrollExtent);
              _scrollController.jumpTo(target);
            }
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载消息失败: $e')));
    }
  }

  Future<void> _scheduleScrollToBottom(
      {bool animate = true, int retries = 0}) async {
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0 && retries < 8) {
      await Future.delayed(const Duration(milliseconds: 60));
      return _scheduleScrollToBottom(animate: animate, retries: retries + 1);
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animate && (target - _scrollController.position.pixels).abs() > 1) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else if (!animate && (target - _scrollController.position.pixels).abs() > 1) {
      _scrollController.jumpTo(target);
    }
    if (mounted) {
      _isUserAtBottom = true;
      _refreshUnreadButtonState();
    }
  }

  String get _cacheKey => CacheService().scoped(
        context.read<AuthService>().userId ?? 'guest',
        'messages:${widget.type}:${widget.conversationId}',
      );

  Future<void> _restoreCachedMessages() async {
    _cacheHydrated = true;
    final cached = await CacheService().readJson(_cacheKey);
    if (cached is! List || cached.isEmpty || !mounted) return;
    final restored = cached
        .whereType<Map>()
        .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final visible = restored.length > 15
        ? restored.sublist(restored.length - 15)
        : restored;
    setState(() {
      _messages
        ..clear()
        ..addAll(visible);
      _rebuildMessageMap();
      for (final message in visible) {
        _updatePollCursor(message);
      }
      _messageKeys
        ..clear()
        ..addEntries(visible.map((m) => MapEntry(m.id, GlobalKey())));
    });
  }

  Future<void> _saveCachedMessages() async {
    await CacheService().writeJson(
      _cacheKey,
      _messages.map((m) => m.toJson()).toList(),
    );
  }

  Future<void> _markConversationRead() async {
    final api = ApiService();
    if (widget.type == 'direct') {
      await api.markDirectRead(widget.conversationId);
    } else {
      await api.markGroupRead(widget.conversationId);
    }
  }

  Future<void> _refreshConversation() async {
    _offset = 0;
    _nextBeforeCreatedAt = null;
    _nextBeforeId = null;
    _hasMore = true;
    _messages.clear();
    _messageMap.clear();
    _messageKeys.clear();
    await _loadMessages(initial: true);
    await _scheduleScrollToBottom();
  }

  void _scrollToBottom() {
    _scheduleScrollToBottom();
  }

  Future<void> _scrollToMessage(String messageId,
      {int retry = 0, bool searchOlder = true}) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final key = _messageKeys[messageId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        return;
      }

      if (_scrollController.hasClients) {
        final itemHeight = 96.0;
        final targetOffset = index * itemHeight;
        final maxOffset = _scrollController.position.maxScrollExtent;
        if (targetOffset < maxOffset) {
          _scrollController.animateTo(
            targetOffset.clamp(0.0, maxOffset),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        } else {
          _scrollController.animateTo(
            maxOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        if (retry < 4) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToMessage(messageId, retry: retry + 1));
        }
      }
      return;
    }

    if (searchOlder && _hasMore && !_loading) {
      final previousCount = _messages.length;
      await _loadMessages(initial: false);
      if (!mounted) return;
      if (_messages.length > previousCount) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _scrollToMessage(messageId, retry: retry, searchOlder: _hasMore);
      }
    }
  }

  Future<void> _showSearchMessages() async {
    final searchController = TextEditingController();
    List<Message> results = [];
    String? errorMessage;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('搜索聊天记录'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '关键词',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) async {
                      if (loading) return;
                      final query = searchController.text.trim();
                      if (query.isEmpty) return;
                      setState(() {
                        loading = true;
                        errorMessage = null;
                      });
                      try {
                        final api = ApiService();
                        final response = widget.type == 'direct'
                            ? await api.searchDirectMessages(
                                widget.conversationId, query)
                            : await api.searchGroupMessages(
                                widget.conversationId, query);
                        results = _parseSearchMessages(response);
                      } catch (e) {
                        errorMessage = '搜索失败: $e';
                      } finally {
                        if (mounted) setState(() => loading = false);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (loading) const CircularProgressIndicator(),
                  if (errorMessage != null)
                    Text(errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                  if (!loading && results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('输入关键词后搜索聊天记录'),
                    ),
                  if (results.isNotEmpty)
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final result = results[index];
                          return ListTile(
                            title: Text(
                              _getMessageDisplayText(result),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_formatDateTime(result.createdAt)),
                            onTap: () {
                              Navigator.of(context).pop();
                              if (!_messages
                                  .any((message) => message.id == result.id)) {
                                setState(() {
                                  _addLocalMessage(result);
                                  _messages.sort(_compareMessages);
                                });
                              }
                              _scrollToMessage(result.id);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        final query = searchController.text.trim();
                        if (query.isEmpty) return;
                        setState(() {
                          loading = true;
                          errorMessage = null;
                        });
                        try {
                          final api = ApiService();
                          final response = widget.type == 'direct'
                              ? await api.searchDirectMessages(
                                  widget.conversationId, query)
                              : await api.searchGroupMessages(
                                  widget.conversationId, query);
                          final raw = response['messages'] ??
                              response['results'] ??
                              response['items'] ??
                              response['records'] ??
                              response['data'];
                          final list = raw is List ? raw : const <dynamic>[];
                          results = list
                              .whereType<Map>()
                              .map((item) => Message.fromJson(
                                  Map<String, dynamic>.from(item)))
                              .toList();
                        } catch (e) {
                          errorMessage = '搜索失败: $e';
                        } finally {
                          if (mounted) setState(() => loading = false);
                        }
                      },
                child: const Text('搜索'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _showGroupTools() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.groups_2),
              title: const Text('群成员'),
              subtitle: const Text('查看成员、身份与资料'),
              onTap: () {
                Navigator.pop(context);
                _showGroupMembers();
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('搜索历史消息'),
              subtitle: const Text('按关键词定位历史内容'),
              onTap: () {
                Navigator.pop(context);
                _showSearchMessages();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupMembers() async {
    try {
      final api = ApiService();
      final response = await api.getGroupMembers(widget.conversationId);
      final list = (response['members'] as List?) ?? [];
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('群成员'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: list.isEmpty
                  ? const Center(child: Text('暂无成员'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final member = Map<String, dynamic>.from(list[index]);
                        final uid = (member['uid'] ??
                                member['user_uid'] ??
                                member['id'] ??
                                '')
                            .toString();
                        final name = (member['display_name'] ??
                                member['nickname'] ??
                                member['name'] ??
                                uid)
                            .toString();
                        final rawAvatar = member['avatar_url'] ??
                            member['avatar'] ??
                            member['photo_url'];
                        final avatarUrl =
                            resolveMediaUrl(rawAvatar?.toString());
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarUrl.isNotEmpty
                                ? ImageCacheService.instance.provider(avatarUrl, cacheWidth: 96)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    name.isEmpty ? '?' : name.substring(0, 1))
                                : null,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            member['role']?.toString() ??
                                member['title']?.toString() ??
                                uid,
                          ),
                          onTap: uid.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  Navigator.of(this.context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfilePage(uid: uid)),
                                  );
                                },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载群成员失败: $e')),
      );
    }
  }

  String _formatDateTime(int timestamp) {
    final milliseconds = timestamp > 1000000000000
        ? timestamp
        : timestamp > 1000000000
            ? timestamp * 1000
            : timestamp;
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }

  List<Message> _parseSearchMessages(dynamic response) {
    dynamic value = response;
    for (var i = 0; i < 3 && value is Map; i++) {
      final map = Map<String, dynamic>.from(value as Map);
      final candidate = map['messages'] ?? map['results'] ?? map['items'];
      if (candidate is List) {
        value = candidate;
        break;
      }
      if (map['data'] is List) {
        value = map['data'];
        break;
      }
      if (map['data'] is Map) {
        value = map['data'];
        continue;
      }
      value = const <dynamic>[];
    }
    if (value is! List) return const <Message>[];
    return value
        .whereType<Map>()
        .map((item) {
          final json = Map<String, dynamic>.from(item);
          json['id'] ??= json['message_id'] ?? json['msg_id'];
          json['from_uid'] ??= json['sender_uid'] ?? json['uid'] ?? '';
          json['body'] ??= json['text'] ?? '';
          json['msg_type'] ??= json['type'] ?? 'text';
          json['created_at'] ??= json['timestamp'] ?? 0;
          return Message.fromJson(json);
        })
        .where((message) => message.id.isNotEmpty)
        .toList();
  }

  String _getMessageDisplayText(Message msg) {
    if (msg.msgType == 'text') {
      final parsed = MessageParser.parseV2(msg.body);
      final text = parsed['text']?.toString() ?? '';
      return text.isEmpty ? MessageParser.extractPlainText(msg.body) : text;
    }
    if (msg.msgType == 'image') return '[图片]';
    if (msg.msgType == 'voice') return '[语音]';
    if (msg.msgType == 'video') return '[视频]';
    if (msg.msgType == 'file' || msg.msgType == 'resource') return '[文件]';
    if (msg.msgType == 'red_packet') return '[红包]';
    return msg.body.isEmpty ? '[原消息内容不可用]' : msg.body;
  }

  // ★ 日期格式化
  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy/MM/dd').format(dt);
  }

  bool _isSameDay(int timestamp1, int timestamp2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(timestamp1 * 1000);
    final d2 = DateTime.fromMillisecondsSinceEpoch(timestamp2 * 1000);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  Future<bool> _showFriendRequestDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('不是好友'),
            content: const Text('您还不是对方的好友，需要先发送好友申请才能聊天。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('发送申请')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendFriendRequest(String toUid) async {
    try {
      final friends = await ApiService().getFriends();
      if (friends.any((f) => f.id == toUid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('你们已经是好友了')),
        );
        return;
      }
      final requests = await ApiService().getFriendRequests();
      final sent =
          (requests['sent'] as List?)?.any((r) => r['to_uid'] == toUid) ??
              false;
      final received =
          (requests['requests'] as List?)?.any((r) => r['from_uid'] == toUid) ??
              false;
      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('您已发送过好友申请，请等待对方通过')),
        );
        return;
      }
      if (received) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('对方已向您发送好友申请，请检查通知')),
        );
        return;
      }
      await ApiService().sendFriendRequest(toUid);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('好友申请已发送，等待对方通过')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送申请失败: $e')),
      );
    }
  }

  Future<void> _sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) {
        await _sendFriendRequest(widget.conversationId);
      }
      return;
    }

    Map<String, dynamic> payload = {'v': 2, 'text': text};
    if (_quotedMessage != null) {
      payload['quote'] = {
        'id': _quotedMessage!.id,
        'from_uid': _quotedMessage!.fromUid,
        'from_name': _quotedMessage!.fromUid,
        'type': _quotedMessage!.msgType,
        'text': _getMessageDisplayText(_quotedMessage!),
        if (_quotedMessage!.mediaUrl != null)
          'media_url': _quotedMessage!.mediaUrl,
        if (_quotedMessage!.thumbUrl != null)
          'thumb_url': _quotedMessage!.thumbUrl,
      };
      setState(() => _quotedMessage = null);
    }
    final bodyJson = jsonEncode(payload);

    try {
      final api = ApiService();
      final sent = widget.type == 'direct'
          ? await api.sendDirectMessage(
              toUid: widget.conversationId, body: bodyJson)
          : await api.sendGroupMessage(
              groupId: widget.conversationId, body: bodyJson);
      setState(() {
        _addLocalMessage(sent);
      });
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
      });
      if (widget.onMessageSent != null) widget.onMessageSent!();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  Future<void> _sendMediaFile(File file, String type) async {
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) {
        await _sendFriendRequest(widget.conversationId);
      }
      return;
    }
    if (type == 'file') return;
    try {
      final api = ApiService();
      final formData =
          FormData.fromMap({'file': await MultipartFile.fromFile(file.path)});
      final uploadResult = await api.uploadFile(formData);
      final mediaUrl = uploadResult['url'];
      if (mediaUrl == null) throw Exception('上传失败');
      final msgType = type == 'image'
          ? 'image'
          : type == 'video'
              ? 'video'
              : 'file';
      final sent = widget.type == 'direct'
          ? await api.sendDirectMessage(
              toUid: widget.conversationId,
              body: '',
              msgType: msgType,
              mediaUrl: mediaUrl,
            )
          : await api.sendGroupMessage(
              groupId: widget.conversationId,
              body: '',
              msgType: msgType,
              mediaUrl: mediaUrl,
            );
      setState(() {
        _addLocalMessage(sent);
      });
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
        if (mounted) _inputFocus.requestFocus();
      });
      if (widget.onMessageSent != null) widget.onMessageSent!();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  // ★ 发红包
  Future<void> _sendRedPacket() async {
    if (widget.type == 'direct' && !_isFriend) {
      final shouldSend = await _showFriendRequestDialog();
      if (shouldSend) {
        await _sendFriendRequest(widget.conversationId);
      }
      return;
    }

    final amountC = TextEditingController();
    final countC = TextEditingController();
    final titleC = TextEditingController(text: '恭喜发财');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发红包'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '金额 (旧币)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.type == 'group') const SizedBox(height: 8),
              if (widget.type == 'group')
                TextField(
                  controller: countC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '个数',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: titleC,
                decoration: const InputDecoration(
                  hintText: '红包标题',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final amount = int.tryParse(amountC.text);
              final count = int.tryParse(countC.text) ?? 1;
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效金额')),
                );
                return;
              }
              if (widget.type == 'group' && count <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效个数')),
                );
                return;
              }
              Navigator.pop(context, {
                'amount': amount.toString(),
                'count': count,
                'title': titleC.text.trim(),
              });
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (result == null) return;

    try {
      final api = ApiService();
      final amount = int.tryParse(result['amount']) ?? 0;

      final data = await api.createRedPacket(
        targetId: widget.conversationId,
        amount: amount.toString(),
        type: widget.type,
        count: result['count'],
        title: result['title']?.toString() ?? '恭喜发财',
      );

      final packetId = data['packet_id'] ??
          data['packetId'] ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final bodyJson = jsonEncode({
        'packet_id': packetId,
        'total_amount': amount,
        'total_count': result['count'],
        'text': result['title']?.toString().trim().isNotEmpty == true
            ? result['title']
            : '恭喜发财',
        'v': 1,
      });

      final msg = Message(
        id: packetId,
        fromUid: context.read<AuthService>().userId ?? '',
        body: bodyJson,
        msgType: 'red_packet',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        groupId: widget.type == 'group' ? widget.conversationId : null,
        threadId: widget.type == 'direct' ? widget.conversationId : null,
      );

      setState(() {
        _addLocalMessage(msg);
      });
      await _saveCachedMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToBottom();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('红包已发送')));
      if (widget.onMessageSent != null) widget.onMessageSent!();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('红包发送失败: $e')));
    }
  }

  Future<void> _claimRedPacket(String packetId) async {
    try {
      final api = ApiService();
      final data = await api.claimRedPacket(packetId);
      final amount = data['amount'] ?? data['claimed_amount'] ?? 0;
      _claimedPackets.add(packetId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('领取成功：$amount 旧币')),
      );
      _offset = 0;
      _hasMore = true;
      _messages.clear();
      _messageKeys.clear();
      await _loadMessages(initial: true);
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('already claimed') || msg.contains('已领取')) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('该红包已被领取')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('领取失败: $e')));
      }
    }
  }

  void _showMessageMenu(Message msg) {
    final displayText = _getMessageDisplayText(msg);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('引用'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _quotedMessage = msg);
                _inputFocus.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: displayText));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制')));
              },
            ),
            if (msg.fromUid == context.read<AuthService>().userId &&
                DateTime.now().millisecondsSinceEpoch - msg.createdAt * 1000 <
                    120000)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('撤回', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _recallMessage(msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _recallMessage(Message msg) async {
    try {
      final api = ApiService();
      if (widget.type == 'direct') {
        await api.recallDirectMessage(msg.id);
      } else {
        await api.recallGroupMessage(msg.id);
      }
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _messageMap.remove(msg.id);
        _messageKeys.remove(msg.id);
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('撤回失败: $e')));
    }
  }

  Widget _buildQuotePreview() {
    if (_quotedMessage == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
          color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('引用: ${_quotedMessage!.fromUid}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
                Text(_getMessageDisplayText(_quotedMessage!),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _quotedMessage = null)),
        ],
      ),
    );
  }

  void _showSendOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('图片'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final result =
                    await picker.pickImage(source: ImageSource.gallery);
                if (result != null) _sendMediaFile(File(result.path), 'image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_collection, color: Colors.green),
              title: const Text('视频'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final result =
                    await picker.pickVideo(source: ImageSource.gallery);
                if (result != null) _sendMediaFile(File(result.path), 'video');
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.red),
              title: const Text('红包'),
              onTap: () {
                Navigator.pop(context);
                _sendRedPacket();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ★ 头像右键菜单（仅群聊有效）
  void _insertMention(String name) {
    final text = _inputController.text;
    final rawPosition = _inputController.selection.baseOffset;
    final position = rawPosition < 0 || rawPosition > text.length
        ? text.length
        : rawPosition;
    final before = text.substring(0, position);
    final after = text.substring(position);
    final mention = '@$name ';
    final next = '$before$mention$after';
    if (next.length > 400) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('消息最多 400 字')));
      return;
    }
    _inputController.value = TextEditingValue(
      text: next,
      selection:
          TextSelection.collapsed(offset: before.length + mention.length),
    );
    _inputFocus.requestFocus();
  }

  void _showAvatarMenu(String uid, String name, Offset position) {
    if (widget.type != 'group') return;

    final items = <PopupMenuEntry<String>>[];

    items.add(
      const PopupMenuItem(
        value: 'mention',
        child: Row(
          children: [
            Icon(Icons.alternate_email, size: 18),
            SizedBox(width: 8),
            Text('@提及'),
          ],
        ),
      ),
    );

    items.add(
      const PopupMenuItem(
        value: 'profile',
        child: Row(
          children: [
            Icon(Icons.person, size: 18),
            SizedBox(width: 8),
            Text('查看资料'),
          ],
        ),
      ),
    );

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'mention':
          _insertMention(name);
          break;
        case 'friend':
          _sendFriendRequest(uid);
          break;
        case 'chat':
          Navigator.pushNamed(
            context,
            '/chat',
            arguments: {'uid': uid, 'title': name},
          );
          break;
        case 'profile':
          Navigator.pushNamed(
            context,
            '/user_profile',
            arguments: uid,
          );
          break;
      }
    });
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _sendTextMessage(_inputController.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthService>().userId;
    if (_isCheckingFriend && widget.type == 'direct') {
      return const Center(child: CircularProgressIndicator());
    }

    final body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _loading && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollEndNotification &&
                              _scrollController.position.pixels <= 0 &&
                              _hasMore &&
                              !_isLoadingMore &&
                              !_loading) {
                            _isLoadingMore = true;
                            _loadMessages(initial: false).then((_) {
                              _isLoadingMore = false;
                            });
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: false,
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = _messages[i];
                            final parsed = MessageParser.parseMessageBody(
                                msg.body, msg.msgType);
                            final isRedPacket = msg.msgType == 'red_packet' ||
                                (msg.msgType == 'text' &&
                                    parsed['redPacket'] != null);
                            final isClaimed = _claimedPackets.contains(
                              parsed['redPacket']?['packet_id'] ??
                                  parsed['redPacket']?['packetId'],
                            );

                            final bool showDateDivider = i == 0 ||
                                !_isSameDay(
                                    _messages[i - 1].createdAt, msg.createdAt);

                            return RepaintBoundary(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateDivider)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Center(
                                        child: Text(
                                          _formatDate(msg.createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  MessageTile(
                                    key: _messageKeys[msg.id],
                                    message: msg,
                                    isMe: msg.fromUid == userId,
                                    onLongPress: () => _showMessageMenu(msg),
                                    onSecondaryTap: () => _showMessageMenu(msg),
                                    onQuoteTap: (quotedId) =>
                                        _scrollToMessage(quotedId),
                                    onAvatarLongPress: widget.type == 'group'
                                        ? (uid, name) => _insertMention(name)
                                        : null,
                                    onAvatarSecondaryTap: widget.type == 'group'
                                        ? _showAvatarMenu
                                        : null,
                                    isRedPacket: isRedPacket,
                                    isClaimed: isClaimed,
                                    onClaimRedPacket: isRedPacket
                                        ? () => _claimRedPacket(
                                              parsed['redPacket']
                                                      ?['packet_id'] ??
                                                  parsed['redPacket']
                                                      ?['packetId'] ??
                                                  '',
                                            )
                                        : null,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
              _buildQuotePreview(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withOpacity(.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.add_circle_outline,
                                color: Theme.of(context).primaryColor),
                            onPressed: _showSendOptions,
                            tooltip: '发送图片/视频/红包',
                          ),
                          Expanded(
                            child: Focus(
                              onKeyEvent: _handleComposerKeyEvent,
                              child: TextField(
                                controller: _inputController,
                                focusNode: _inputFocus,
                                scrollController: _composerScrollController,
                                minLines: 1,
                                maxLines: 6,
                                maxLength: 400,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(400)
                                ],
                                buildCounter: (context,
                                        {required currentLength,
                                        required isFocused,
                                        maxLength}) =>
                                    Padding(
                                  padding: const EdgeInsets.only(
                                      right: 8, bottom: 2),
                                  child: Text('$currentLength/400',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context).hintColor)),
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      widget.type == 'direct' && !_isFriend
                                          ? '发送好友申请后才能聊天'
                                          : '输入消息…（Enter 发送，Shift+Enter 换行）',
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.send,
                                color: Theme.of(context).primaryColor),
                            onPressed: () =>
                                _sendTextMessage(_inputController.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 80,
            right: 16,
            child: Column(
              children: [
                if (_showUnreadButton &&
                    _firstUnreadIndex != null &&
                    _firstUnreadIndex! < _messages.length)
                  FloatingActionButton.small(
                    heroTag: 'unread',
                    onPressed: () {
                      _scrollToMessage(_messages[_firstUnreadIndex!].id);
                      setState(() {
                        _firstUnreadIndex = null;
                        _showUnreadButton = false;
                      });
                    },
                    child: const Icon(Icons.mark_unread_chat_alt, size: 20),
                    tooltip: '查看未读消息',
                    backgroundColor: Colors.orange,
                  ),
                const SizedBox(height: 8),
                if (_showUnreadButton)
                  FloatingActionButton.small(
                    heroTag: 'bottom',
                    onPressed: _scrollToBottom,
                    child: const Icon(Icons.arrow_downward, size: 20),
                    tooltip: '回到底部',
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.embed) {
      return Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        _refreshConversation();
                        break;
                      case 'bottom':
                        _scrollToBottom();
                        break;
                      case 'clear':
                        _inputController.clear();
                        _inputFocus.unfocus();
                        break;
                      case 'copy_id':
                        Clipboard.setData(ClipboardData(
                            text: '${widget.type}:${widget.conversationId}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制会话ID')),
                        );
                        break;
                      case 'group_tools':
                        _showGroupTools();
                        break;
                      case 'search_history':
                        _showSearchMessages();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'refresh', child: Text('刷新消息')),
                    const PopupMenuItem(value: 'bottom', child: Text('回到底部')),
                    const PopupMenuItem(value: 'clear', child: Text('清空输入框')),
                    const PopupMenuItem(
                        value: 'copy_id', child: Text('复制会话ID')),
                    if (widget.type == 'group')
                      const PopupMenuItem(
                          value: 'group_tools', child: Text('群成员与群工具')),
                    const PopupMenuItem(
                        value: 'search_history', child: Text('搜索历史消息')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.type == 'group')
            IconButton(
              icon: const Icon(Icons.group, color: Colors.white),
              tooltip: '查看群成员',
              onPressed: _showGroupTools,
            ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: '搜索历史消息',
            onPressed: _showSearchMessages,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.white,
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refreshConversation();
                  break;
                case 'bottom':
                  _scrollToBottom();
                  break;
                case 'clear':
                  _inputController.clear();
                  _inputFocus.unfocus();
                  break;
                case 'copy_id':
                  Clipboard.setData(ClipboardData(
                      text: '${widget.type}:${widget.conversationId}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制会话ID')),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新消息')),
              const PopupMenuItem(value: 'bottom', child: Text('回到底部')),
              const PopupMenuItem(value: 'clear', child: Text('清空输入框')),
              const PopupMenuItem(value: 'copy_id', child: Text('复制会话ID')),
              if (widget.type == 'group')
                const PopupMenuItem(
                    value: 'group_tools', child: Text('群成员与群工具')),
              const PopupMenuItem(
                  value: 'search_history', child: Text('搜索历史消息')),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}
