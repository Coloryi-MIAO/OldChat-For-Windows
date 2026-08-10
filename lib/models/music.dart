class Music {
  final String id;
  final String uid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String title;
  final String? artist;
  final String? coverUrl;
  final String? audioUrl;
  final String? lyrics;
  final int duration;
  final int plays;
  final int likes;
  final bool isLiked;
  final int createdAt;

  Music({
    required this.id,
    required this.uid,
    this.username,
    this.displayName,
    this.avatarUrl,
    required this.title,
    this.artist,
    this.coverUrl,
    this.audioUrl,
    this.lyrics,
    this.duration = 0,
    this.plays = 0,
    this.likes = 0,
    this.isLiked = false,
    required this.createdAt,
  });

  factory Music.fromJson(Map<String, dynamic> json) {
    // ★ 优先使用 song_url（后端实际字段），其次 media_url
    final audioUrl = json['song_url'] ??
        json['media_url'] ??
        json['audio_url'] ??
        json['url'];
    final coverUrl =
        json['cover_url'] ?? json['image_url'] ?? json['avatar_url'];
    final displayName = json['display_name'] ?? json['owner_display_name'];
    final avatarUrl = json['avatar_url'] ?? json['owner_avatar'];
    final username = json['username'] ?? json['owner_name'];

    return Music(
      id: json['id'] ?? json['music_id'] ?? '',
      uid: json['uid'] ?? json['owner_uid'] ?? '',
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      title: json['name'] ?? json['title'] ?? '未知歌曲',
      artist: json['artist'] ?? json['singer'] ?? json['owner_name'] ?? '未知歌手',
      coverUrl: coverUrl,
      audioUrl: audioUrl,
      lyrics: json['lyrics'],
      duration: json['duration_ms'] ?? json['duration'] ?? 0,
      plays: json['play_count'] ?? json['plays'] ?? 0,
      likes: json['likes'] ?? 0,
      isLiked: json['liked'] ?? json['is_liked'] ?? false,
      createdAt: json['created_at'] ?? 0,
    );
  }
}
