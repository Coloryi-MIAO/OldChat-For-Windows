import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/notification.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationModel> _notifications = [];
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  bool _isLoadingMore = false;

  // ★ 好友申请列表
  List<Map<String, dynamic>> _friendRequests = [];
  // ★ 已处理过的申请ID集合（用于去重）
  Set<String> _processedRequestIds = {};

  @override
  void initState() {
    super.initState();
    _loadFriendRequests();
    _loadNotifications();
  }

  // ★ 加载好友申请，过滤掉已是好友的申请
  Future<void> _loadFriendRequests() async {
    try {
      final api = ApiService();
      // 获取好友列表
      final friends = await api.getFriends();
      final friendUids = friends.map((f) => f.id).toSet();

      // 获取好友申请
      final data = await api.getFriendRequests();
      final allRequests = (data['requests'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      // 过滤：只保留 pending 状态，且对方还不是好友的申请
      final filtered = allRequests.where((r) {
        if (r['status'] != 'pending') return false;
        if (friendUids.contains(r['from_uid'])) return false;
        if (_processedRequestIds.contains(r['id'])) return false;
        return true;
      }).toList();

      setState(() {
        _friendRequests = filtered;
      });
    } catch (e) {
      print('加载好友申请失败: $e');
    }
  }

  Future<void> _loadNotifications({bool initial = true}) async {
    if (!initial) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
      });
    }

    try {
      final api = ApiService();
      final data = await api.getNotifications(offset: _offset, limit: _limit);
      final newNotifs = (data['items'] as List?)
              ?.map((e) => NotificationModel.fromJson(e))
              .toList() ??
          [];
      final hasMore = data['has_more'] ?? false;

      setState(() {
        if (initial) {
          _notifications = newNotifs;
        } else {
          _notifications.addAll(newNotifs);
        }
        _hasMore = hasMore;
        _offset += newNotifs.length;
        _loading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载通知失败: $e')),
        );
      }
    }
  }

  Future<void> _markRead(NotificationModel notification) async {
    if (notification.isRead) return;
    try {
      final api = ApiService();
      await api.markNotificationRead(notification.id);
      setState(() {
        final index = _notifications.indexOf(notification);
        if (index != -1) {
          _notifications[index] = NotificationModel(
            id: notification.id,
            type: notification.type,
            fromUid: notification.fromUid,
            fromName: notification.fromName,
            fromAvatar: notification.fromAvatar,
            title: notification.title,
            body: notification.body,
            targetId: notification.targetId,
            isRead: true,
            createdAt: notification.createdAt,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  // ★ 响应好友申请（接受/拒绝）
  Future<void> _respondFriendRequest(String requestId, bool accept) async {
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请求ID无效')),
      );
      return;
    }
    try {
      final api = ApiService();
      await api.respondFriendRequest(requestId, accept);

      setState(() {
        _processedRequestIds.add(requestId);
        _friendRequests.removeWhere((r) => r['id'] == requestId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? '已接受好友申请' : '已拒绝')),
      );

      await _loadNotifications(initial: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 7) {
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    List<Widget> allItems = [];

    // ★ 好友申请部分（放在最顶部，相当于 Tab 效果）
    if (_friendRequests.isNotEmpty) {
      allItems.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.blue[50],
          child: Row(
            children: [
              const Icon(Icons.person_add, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                '好友申请 (${_friendRequests.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue),
              ),
              const Spacer(),
              const Text('点击操作',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
      for (var req in _friendRequests) {
        final fromName = req['from_display_name'] ??
            req['from_username'] ??
            req['from_uid'] ??
            '未知用户';
        final fromUid = req['from_uid'] ?? '';
        final requestId = req['id'] ?? '';
        final avatarUrl = req['avatar_url'];
        final createdAt = req['created_at'] ?? 0;

        allItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.blue[50],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(fromName.isNotEmpty ? fromName.substring(0, 1) : '?')
                    : null,
              ),
              title: Text(
                fromName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('请求添加您为好友 · ${_formatTime(createdAt)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _respondFriendRequest(requestId, true),
                    tooltip: '接受',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _respondFriendRequest(requestId, false),
                    tooltip: '拒绝',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // ★ 系统通知部分
    allItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '系统通知 (${_notifications.length})',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
        ),
      ),
    );

    if (_notifications.isEmpty) {
      allItems.add(
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('暂无通知')),
        ),
      );
    } else {
      for (var notification in _notifications) {
        allItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: notification.isRead ? null : Colors.blue[50],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: notification.fromAvatar != null
                    ? NetworkImage(notification.fromAvatar!)
                    : null,
                child: notification.fromAvatar == null
                    ? Text(notification.fromName?.isNotEmpty == true
                        ? notification.fromName!.substring(0, 1)
                        : '?')
                    : null,
              ),
              title: Text(
                notification.title,
                style: TextStyle(
                  fontWeight:
                      notification.isRead ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              subtitle: Text(notification.body),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(notification.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  if (!notification.isRead)
                    const Icon(Icons.circle, color: Colors.blue, size: 8),
                ],
              ),
              onTap: () => _markRead(notification),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知中心'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all, color: Colors.white),
            onPressed: () async {
              for (var n in _notifications.where((n) => !n.isRead)) {
                await _markRead(n);
              }
            },
            tooltip: '全部已读',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadNotifications(initial: true);
              _loadFriendRequests();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: allItems.length,
              itemBuilder: (context, index) => allItems[index],
            ),
    );
  }
}
