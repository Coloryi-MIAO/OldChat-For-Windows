import 'dart:convert';

class MessageParser {
  static Map<String, dynamic> parseMessageBody(String body, String msgType) {
    if (body.trim().isEmpty) {
      return {
        'text': '',
        'quote': null,
        'mentions': const <Map<String, dynamic>>[],
        'buttons': const <Map<String, dynamic>>[],
        'recall': false,
        'redPacket': null,
      };
    }

    final obj = _decodeObject(body);
    if (obj != null) {
      final redPacket = obj.containsKey('packet_id') && obj.containsKey('v')
          ? obj
          : null;
      return {
        'text': obj['text'] ?? obj['content'] ?? (redPacket == null ? body : ''),
        'quote': _normalizeQuote(obj['quote']),
        'mentions': _normalizeMentions(obj['mentions']),
        'buttons': _normalizeButtons(obj['buttons'] ?? obj['keyboard']),
        'recall': obj['recall'] == true || obj['msg_type'] == 'recall',
        'redPacket': redPacket,
      };
    }

    return {
      'text': body,
      'quote': null,
      'mentions': const <Map<String, dynamic>>[],
      'buttons': const <Map<String, dynamic>>[],
      'recall': false,
      'redPacket': null,
    };
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    var candidate = body.trim();
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        if (decoded is String) {
          candidate = decoded.trim();
          continue;
        }
      } catch (_) {
        final repaired = candidate
            .replaceAll(r'\"', '"')
            .replaceAll(r'\[', '[')
            .replaceAll(r'\]', ']')
            .replaceAll(r'\{', '{')
            .replaceAll(r'\}', '}')
            .replaceAll(r'\_', '_')
            .replaceAll(r'\n', '\n');
        if (repaired == candidate) break;
        candidate = repaired;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _normalizeButtons(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map>().map((item) {
      final button = Map<String, dynamic>.from(item);
      return {
        'text': (button['text'] ?? button['label'] ?? '').toString(),
        'action': (button['action'] ?? 'send_text').toString(),
        'data': (button['data'] ?? button['value'] ?? '').toString(),
      };
    }).where((button) {
      return (button['text'] ?? '').toString().trim().isNotEmpty;
    }).toList();
  }

  static List<Map<String, dynamic>> _normalizeMentions(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map>().map((item) {
      final mention = Map<String, dynamic>.from(item);
      return {
        'uid': (mention['uid'] ?? mention['user_uid'] ?? '').toString(),
        'name': (mention['name'] ?? mention['display_name'] ?? mention['uid'] ?? '')
            .toString(),
      };
    }).where((item) {
      return item['uid']!.toString().isNotEmpty;
    }).toList();
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

  static String extractPlainText(String body) {
    final obj = _decodeObject(body);
    if (obj != null) {
      if (obj.containsKey('v') && obj.containsKey('text')) {
        return obj['text']?.toString() ?? body;
      }
      if (obj.containsKey('text')) {
        return obj['text']?.toString() ?? body;
      }
    }
    return body;
  }
}
