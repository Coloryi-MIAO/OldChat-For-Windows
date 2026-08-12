class Emoji {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String mediaUrl;
  final String? thumbUrl;
  final int likes;
  final bool isLiked;
  final int createdAt;

  Emoji({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.mediaUrl,
    this.thumbUrl,
    this.likes = 0,
    this.isLiked = false,
    required this.createdAt,
  });

  factory Emoji.fromJson(Map<String, dynamic> json) {
    return Emoji(
      id: json['id'] ?? '',
      uid: json['uid'] ?? '',
      username: json['username'],
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      mediaUrl: json['media_url'] ?? '',
      thumbUrl: json['thumb_url'],
      likes: json['likes'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      createdAt: json['created_at'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'media_url': mediaUrl,
        'thumb_url': thumbUrl,
        'likes': likes,
        'is_liked': isLiked,
        'created_at': createdAt,
      };
}
