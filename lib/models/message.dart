import 'dart:convert';

import '../utils/message_parser.dart';

class Message {
  final String id;
  final String fromUid;
  final String? fromNcuid;
  final String body;
  final String msgType;
  final String? mediaUrl;
  final String? thumbUrl;
  final int durationMs;
  final int burnAfterSeconds;
  final int? burnStartAt;
  final int createdAt;
  final String? groupId;
  final int? groupSeq;
  final String? threadId;
  final int? deliveredAt;
  final int? readAt;
  final int readCount;

  Map<String, dynamic>? _parsedV2;

  Message({
    required this.id,
    required this.fromUid,
    this.fromNcuid,
    required this.body,
    required this.msgType,
    this.mediaUrl,
    this.thumbUrl,
    this.durationMs = 0,
    this.burnAfterSeconds = 0,
    this.burnStartAt,
    required this.createdAt,
    this.groupId,
    this.groupSeq,
    this.threadId,
    this.deliveredAt,
    this.readAt,
    this.readCount = 0,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawDurationMs = json['duration_ms'];
    final rawDuration = json['duration'];
    final durationMs = _parseDurationMs(rawDurationMs, rawDuration);
    final media = json['media'] ?? json['attachment'] ?? json['file'];
    String? mediaValue(dynamic value) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is Map) {
        for (final key in const ['url', 'media_url', 'download_url', 'file_url', 'src']) {
          final candidate = value[key];
          if (candidate is String && candidate.trim().isNotEmpty) return candidate.trim();
        }
      }
      return null;
    }
    Map<String, dynamic>? bodyMap;
    final rawBody = json['body'];
    if (rawBody is String) {
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map) bodyMap = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final mediaUrl = mediaValue(json['media_url']) ??
        mediaValue(json['download_url']) ?? mediaValue(json['file_url']) ?? mediaValue(media) ??
        mediaValue(bodyMap?['media_url']) ?? mediaValue(bodyMap?['url']);
    final thumbUrl = mediaValue(json['thumb_url']) ?? mediaValue(json['thumbnail_url']) ??
        (media is Map ? mediaValue(media['thumbnail']) : null) ??
        mediaValue(bodyMap?['thumb_url']) ?? mediaValue(bodyMap?['thumbnail_url']);
    return Message(
      id: json['id'] ?? '',
      fromUid: json['from_uid'] ?? json['from_ncuid'] ?? '',
      fromNcuid: json['from_ncuid'],
      body: json['body'] ?? '',
      msgType: json['msg_type'] ?? json['type'] ??
          (bodyMap?['media_kind'] == 'video' ? 'video' : bodyMap?['media_kind']) ?? 'text',
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      durationMs: durationMs,
      burnAfterSeconds: json['burn_after_seconds'] ?? 0,
      burnStartAt: json['burn_start_at'],
      createdAt: json['created_at'] ?? 0,
      groupId: json['group_id'],
      groupSeq: _toNullableInt(json['group_seq']),
      threadId: json['thread_id'],
      deliveredAt: json['delivered_at'],
      readAt: json['read_at'],
      readCount: json['read_count'] ?? 0,
    );
  }

  static int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static int _parseDurationMs(dynamic durationMs, dynamic duration) {
    if (durationMs is num) return durationMs.toInt();
    if (durationMs is String) {
      final parsed = double.tryParse(durationMs);
      if (parsed != null) return parsed.round();
    }
    if (duration is num) return (duration * 1000).round();
    if (duration is String) {
      final parsed = double.tryParse(duration);
      if (parsed != null) return (parsed * 1000).round();
    }
    return 0;
  }

  String get displayText {
    if (msgType != 'text') return '';
    if (_parsedV2 == null) _parsedV2 = MessageParser.parseV2(body);
    return _parsedV2!['text'] ?? body;
  }

  Map<String, dynamic>? get quote {
    if (msgType != 'text') return null;
    if (_parsedV2 == null) _parsedV2 = MessageParser.parseV2(body);
    return _parsedV2!['quote'];
  }

  List<Map<String, dynamic>> get mentions {
    if (msgType != 'text') return [];
    if (_parsedV2 == null) _parsedV2 = MessageParser.parseV2(body);
    return _parsedV2!['mentions']?.cast<Map<String, dynamic>>() ?? [];
  }

  bool get isV2 => MessageParser.isV2(body);

  bool get isRead => readAt != null && readAt! > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_uid': fromUid,
        'from_ncuid': fromNcuid,
        'body': body,
        'msg_type': msgType,
        'media_url': mediaUrl,
        'thumb_url': thumbUrl,
        'duration_ms': durationMs,
        'burn_after_seconds': burnAfterSeconds,
        'burn_start_at': burnStartAt,
        'created_at': createdAt,
        'group_id': groupId,
        'group_seq': groupSeq,
        'thread_id': threadId,
        'delivered_at': deliveredAt,
        'read_at': readAt,
        'read_count': readCount,
      };
}
