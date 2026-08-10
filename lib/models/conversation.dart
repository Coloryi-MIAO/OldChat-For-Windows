import 'message.dart';

class Conversation {
  final String id;
  final String type;
  final String? name;
  final String? avatar;
  final Message? lastMessage;
  final int unreadCount;
  final bool pinned;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    this.lastMessage,
    this.unreadCount = 0,
    this.pinned = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] ?? json['uid'] ?? json['group_id'] ?? '',
      type: json['type'] ?? 'direct',
      name: json['name'] ?? json['display_name'] ?? json['username'],
      avatar: json['avatar'] ?? json['avatar_url'],
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'])
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true || json['is_pinned'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar': avatar,
        'last_message': lastMessage == null
            ? null
            : {
                'id': lastMessage!.id,
                'from_uid': lastMessage!.fromUid,
                'from_ncuid': lastMessage!.fromNcuid,
                'body': lastMessage!.body,
                'msg_type': lastMessage!.msgType,
                'media_url': lastMessage!.mediaUrl,
                'thumb_url': lastMessage!.thumbUrl,
                'duration_ms': lastMessage!.durationMs,
                'created_at': lastMessage!.createdAt,
                'read_at': lastMessage!.readAt,
              },
        'unread_count': unreadCount,
        'pinned': pinned,
      };
  Conversation copyWith({
    String? name,
    String? avatar,
    Message? lastMessage,
    int? unreadCount,
    bool? pinned,
  }) {
    return Conversation(
      id: id,
      type: type,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      pinned: pinned ?? this.pinned,
    );
  }

}
