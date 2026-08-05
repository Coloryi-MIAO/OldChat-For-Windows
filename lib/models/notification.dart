class NotificationModel {
  final String id;
  final String type; // friend_request, group_invite, system, like, comment
  final String? fromUid;
  final String? fromName;
  final String? fromAvatar;
  final String title;
  final String body;
  final String? targetId;
  final bool isRead;
  final int createdAt;

  NotificationModel({
    required this.id,
    required this.type,
    this.fromUid,
    this.fromName,
    this.fromAvatar,
    required this.title,
    required this.body,
    this.targetId,
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      fromUid: json['from_uid'],
      fromName: json['from_name'],
      fromAvatar: json['from_avatar'],
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      targetId: json['target_id'],
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] ?? 0,
    );
  }
}
