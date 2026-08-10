import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../utils/url_helper.dart';
import '../services/image_cache_service.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final int unreadCount;
  final bool isActive;
  final bool isPinned;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onSecondaryTapDown,
    this.unreadCount = 0,
    this.isActive = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = resolveMediaUrl(conversation.avatar);
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: ListTile(
        tileColor: isActive ? Colors.blue.shade50 : null,
        leading: CircleAvatar(
          backgroundImage: avatarUrl.isNotEmpty
              ? ImageCacheService.instance.provider(avatarUrl, cacheWidth: 96)
              : null,
          child: avatarUrl.isEmpty
              ? Text(conversation.name?.substring(0, 1) ?? '?')
              : null,
        ),
        title: Row(
          children: [
            Expanded(child: Text(conversation.name ?? '未知')),
            if (isPinned)
              const Icon(Icons.push_pin, size: 14, color: Colors.orange),
          ],
        ),
        subtitle:
            Text(conversation.id, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: unreadCount > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: Colors.red,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
