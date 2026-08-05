import 'dart:convert';

class MessageParser {
  static Map<String, dynamic> parseMessageBody(String body, String msgType) {
    if (body.isEmpty) return {'text': '', 'quote': null, 'redPacket': null};
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      try {
        final obj = jsonDecode(body);
        if (obj is Map) {
          if (obj.containsKey('packet_id') && obj.containsKey('v')) {
            return {'text': obj['text'] ?? '', 'quote': null, 'redPacket': obj};
          }
          if (obj.containsKey('v') && obj['v'] == 2) {
            return {
              'text': obj['text'] ?? '',
              'quote': _normalizeQuote(obj['quote']),
              'redPacket': null
            };
          }
          return {
            'text': obj['text'] ?? body,
            'quote': _normalizeQuote(obj['quote']),
            'redPacket': null
          };
        }
      } catch (_) {}
    }
    return {'text': body, 'quote': null, 'redPacket': null};
  }

  static Map<String, dynamic> parseV2(String body) {
    return parseMessageBody(body, 'text');
  }

  static Map<String, dynamic>? _normalizeQuote(dynamic value) {
    if (value is! Map) return null;
    final quote = Map<String, dynamic>.from(value);
    final rawText = quote['text'] ?? quote['body'] ?? quote['content'] ?? '';
    quote['text'] = rawText is String ? rawText : rawText.toString();
    quote['type'] = quote['type'] ?? quote['msg_type'] ?? 'text';
    quote['id'] = quote['id'] ?? quote['message_id'] ?? '';
    quote['from_uid'] = quote['from_uid'] ?? quote['uid'] ?? '';
    quote['from_name'] =
        quote['from_name'] ?? quote['sender'] ?? quote['from_uid'] ?? '';
    return quote;
  }

  static bool isV2(String body) {
    try {
      final obj = jsonDecode(body);
      return obj is Map && obj['v'] == 2;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> buildQuote(Map<String, dynamic> msg) {
    return {
      'id': msg['id'] ?? '',
      'from_uid': msg['from_uid'] ?? '',
      'from_name': msg['sender'] ?? msg['from_uid'] ?? '',
      'type': msg['msg_type'] ?? 'text',
      'text': _truncate((msg['body'] ?? '').toString(), 200),
    };
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  /// 从可能的 JSON 消息体中提取纯文本（用于显示引用内容）
  static String extractPlainText(String body) {
    if (body.trim().startsWith('{')) {
      try {
        final obj = jsonDecode(body);
        if (obj is Map) {
          // 如果是 v2 格式，取 text 字段
          if (obj.containsKey('v') && obj.containsKey('text')) {
            return obj['text']?.toString() ?? body;
          }
          // 如果是普通 JSON 且有 text 字段
          if (obj.containsKey('text')) {
            return obj['text']?.toString() ?? body;
          }
        }
      } catch (_) {}
    }
    return body;
  }
}
