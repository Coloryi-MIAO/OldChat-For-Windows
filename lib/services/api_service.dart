import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/moment.dart';
import '../models/music.dart';
import '../models/emoji.dart';
import '../models/notification.dart';
import 'auth_service.dart';
import '../utils/navigation.dart';
import '../pages/login_page.dart';
import 'cache_service.dart';
import '../services/ai_settings_service.dart';

class ApiService {
  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {'data': value};
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: Constants.baseUrl,
      headers: {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final AuthService _auth = AuthService();
  bool _isRefreshing = false;
  final List<Completer<bool>> _queue = [];

  ApiService() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['_startedAt'] = DateTime.now();
          final token = _auth.token;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            final result = await _handleUnauthorized();
            if (result) {
              final retry = await _retryRequest(e);
              return handler.resolve(retry);
            }
          }
          final started = e.requestOptions.extra['_startedAt'];
          if (started is DateTime) {
            print(
              '[API慢] ${e.requestOptions.method} ${e.requestOptions.path} ${DateTime.now().difference(started).inMilliseconds}ms',
            );
          }
          return handler.next(e);
        },
        onResponse: (response, handler) {
          final started = response.requestOptions.extra['_startedAt'];
          if (started is DateTime) {
            print(
              '[API] ${response.requestOptions.method} ${response.requestOptions.path} ${DateTime.now().difference(started).inMilliseconds}ms',
            );
          }
          return handler.next(response);
        },
      ),
    );
  }

  static String? extractUploadUrl(dynamic raw) {
    if (raw is String) {
      final value = raw.trim();
      return value.isEmpty ? null : value;
    }
    if (raw is List) {
      for (final item in raw) {
        final result = extractUploadUrl(item);
        if (result != null) return result;
      }
      return null;
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in const [
        'url',
        'download_url',
        'download_path',
        'media_url',
        'file_url',
        'path',
        'src',
      ]) {
        final result = extractUploadUrl(map[key]);
        if (result != null) return result;
      }
      for (final key in const ['data', 'file', 'media', 'result', 'payload']) {
        final result = extractUploadUrl(map[key]);
        if (result != null) return result;
      }
    }
    return null;
  }

  Map<String, dynamic> _normalizeSearchResponse(dynamic raw) {
    if (raw is List) return {'messages': raw};
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in const ['messages', 'results', 'items', 'records']) {
        if (map[key] is List) return {'messages': map[key], ...map};
      }
      final nested = map['data'];
      if (nested is List) return {'messages': nested, ...map};
      if (nested is Map) return _normalizeSearchResponse(nested);
    }
    return {'messages': const <dynamic>[]};
  }

  Exception _apiError(String prefix, DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['error'] ?? data['message'] ?? data['code'];
      if (detail != null) {
        final status = error.response?.statusCode;
        return Exception(
          '$prefix${status == null ? '' : ' ($status)'}: $detail',
        );
      }
    }
    final status = error.response?.statusCode;
    return Exception(
      '$prefix${status == null ? '' : ' ($status)'}: ${error.message ?? '网络错误'}',
    );
  }

  // 鈽?澶勭悊 401锛氬埛鏂?token 鎴栬嚜鍔ㄧ櫥褰?
  Future<bool> _handleUnauthorized() async {
    if (_isRefreshing) {
      final completer = Completer<bool>();
      _queue.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    try {
      // 1. 浼樺厛浣跨敤 refresh_token
      final refreshToken = await _auth.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final data = await this.refreshToken(refreshToken);
          if (data['access_token'] != null) {
            await _auth.saveToken(
              data['access_token'],
              userId: data['user_id'],
              refreshToken: data['refresh_token'] ?? refreshToken,
            );
            print('Token 鍒锋柊鎴愬姛');
            return true;
          }
        } catch (e) {
          print('Refresh token 澶辫败: $e');
        }
      }

      // 2. 濡傛灉 refresh_token 澶辫敗锛屽皾璇曚娇鐢ㄤ繚瀛樼殑璐﹀彿瀵嗙爜鑷姩鐧诲綍
      final username = _auth.savedUsername;
      final password = _auth.savedPassword;
      if (username != null &&
          username.isNotEmpty &&
          password != null &&
          password.isNotEmpty) {
        try {
          print('馃攧 灏濊瘯浣跨敤淇濆瓨鐨勮处鍙峰瘑鐮佽嚜鍔ㄧ櫥褰?..');
          final data = await login(username, password);
          if (data['token'] != null) {
            await _auth.saveToken(
              data['token'],
              userId: data['userId'],
              refreshToken: data['refresh_token'],
            );
            print('鑷姩鐧诲綍鎴愬姛');
            return true;
          }
        } catch (e) {
          print('鑷姩鐧诲綍澶辫触: $e');
        }
      }

      // 3. 鎵€鏈夋柟寮忛兘澶辫触锛屾竻闄?token 骞惰烦杞櫥褰?
      await _auth.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false,
        );
      });
      return false;
    } finally {
      _isRefreshing = false;
      for (final item in _queue) {
        item.complete(true);
      }
      _queue.clear();
    }
  }

  // 鈽?閲嶈瘯鍘熻姹?
  Future<Response> _retryRequest(DioException e) async {
    final options = e.requestOptions;
    final token = _auth.token;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return _dio.fetch(options);
  }

  // ==================== 璁よ瘉 ====================

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post(
        Constants.loginPath,
        data: {'username': username, 'password': password},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final token = data['access_token'] ?? data['token'];
        final userId = data['user_id'] ?? data['uid'] ?? data['user']?['uid'];
        final refreshToken = data['refresh_token'];
        return {
          'token': token,
          'userId': userId,
          'refresh_token': refreshToken,
        };
      } else {
        throw Exception('Login failed: ${response.data}');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String emailCode,
    required String captchaId,
    required String captchaCode,
    required String deviceId,
    required String deviceName,
    String platform = 'windows',
    String appVersion = '1.3.6',
    Map<String, dynamic>? captchaResult,
  }) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/web/register'),
        data: {
          'email': email,
          'username': username,
          'password': password,
          'email_code': emailCode,
          'platform': platform,
          'app_version': appVersion,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        throw Exception('Register failed');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Map<String, dynamic> _geetestFields(Map<String, dynamic> result) {
    return {
      'geetest_lot_number': result['lot_number'],
      'geetest_captcha_output': result['captcha_output'],
      'geetest_pass_token': result['pass_token'],
      'geetest_gen_time': result['gen_time'],
    };
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/refresh'),
        data: {'refresh_token': refreshToken},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(Constants.apiPath('/v1/auth/logout'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 楠岃瘉鐮?====================

  Future<Map<String, dynamic>> getCaptcha() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/auth/captcha'),
        options: Options(responseType: ResponseType.bytes),
      );
      final captchaId = response.headers.value('x-captcha-id') ?? '';
      final body = response.data;
      if (body is List<int>) {
        return {'captcha_id': captchaId, 'image_bytes': body};
      }
      if (body is Map) return Map<String, dynamic>.from(body);
      return {'captcha_id': captchaId};
    } on DioException catch (e) {
      throw Exception('获取验证码失败: ${e.message}');
    }
  }

  Future<void> sendEmailCode(
    String email,
    Map<String, dynamic> captchaResult,
  ) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/auth/email/send'),
        data: {'email': email, ..._geetestFields(captchaResult)},
      );
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('鍙戦€侀獙璇佺爜澶辫触: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/auth/password/reset'),
        data: {'email': email, 'code': code, 'new_password': newPassword},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 濂藉弸 ====================

  Future<List<Conversation>> getFriends() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/friends'));
      if (response.statusCode == 200) {
        final data = response.data;
        final list = data['friends'] as List? ?? [];
        return list
            .map(
              (e) => Conversation.fromJson({
                ...Map<String, dynamic>.from(e as Map),
                'id': e['uid'],
                'type': 'direct',
              }),
            )
            .toList();
      } else {
        throw Exception('Failed to load friends');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getFriendRequests() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/friends/requests'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> sendFriendRequest(String toUid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/friends/request'),
        data: {'to_uid': toUid.trim(), 'message': '你好'},
      );
    } on DioException catch (e) {
      throw _apiError('发送好友申请失败', e);
    }
  }

  Future<void> respondFriendRequest(String requestId, bool accept) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/friends/respond'),
        data: {'request_id': requestId, 'accept': accept},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> remarkFriend(String uid, String remark) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/friends/remark'),
        data: {'uid': uid, 'remark': remark},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteFriend(String uid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/friends/delete'),
        data: {'uid': uid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 缇よ亰 ====================

  Future<List<Conversation>> getGroups() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/groups/list'));
      if (response.statusCode == 200) {
        final data = response.data;
        final list = data['groups'] as List? ?? [];
        return list
            .map(
              (e) => Conversation.fromJson({
                ...Map<String, dynamic>.from(e as Map),
                'id': e['group_id'],
                'type': 'group',
              }),
            )
            .toList();
      } else {
        throw Exception('Failed to load groups');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createGroup(
    String name,
    List<String> members,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/groups/create'),
        data: {'name': name, 'members': members},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> joinGroup(String groupId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/join'),
        data: {'group_id': groupId.trim()},
      );
    } on DioException catch (e) {
      throw _apiError('加入群聊失败', e);
    }
  }

  Future<void> approveGroupRequest(String requestId, bool accept) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/approve'),
        data: {'request_id': requestId, 'accept': accept},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupMembers(String groupId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/groups/members'),
        queryParameters: {'group_id': groupId.trim()},
      );
      final raw = response.data;
      if (raw is Map && raw['members'] is List)
        return Map<String, dynamic>.from(raw);
      if (raw is Map && raw['data'] is Map) {
        return Map<String, dynamic>.from(raw['data'] as Map);
      }
      if (raw is Map && raw['data'] is List) {
        return {'members': raw['data']};
      }
      return {'members': const <dynamic>[]};
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupRequests(String groupId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/groups/requests?group_id=$groupId'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> inviteToGroup(String groupId, String uid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/invite'),
        data: {'group_id': groupId, 'user_uid': uid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> setGroupAdmin(String groupId, String uid, bool isAdmin) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/admin'),
        data: {'group_id': groupId, 'uid': uid, 'is_admin': isAdmin},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupAvatar(String groupId, FormData formData) async {
    try {
      await _dio.post(Constants.apiPath('/v1/groups/avatar'), data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> kickGroupMember(String groupId, String uid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/kick'),
        data: {'group_id': groupId, 'uid': uid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupName(String groupId, String name) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/name'),
        data: {'group_id': groupId, 'name': name},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateGroupSettings(
    String groupId,
    Map<String, dynamic> settings,
  ) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/settings'),
        data: {'group_id': groupId, ...settings},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> setGroupAnnouncement(String groupId, String announcement) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/announcement'),
        data: {'group_id': groupId, 'announcement': announcement},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> markAnnouncementRead(
    String groupId,
    String announcementId,
  ) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/announcement/read'),
        data: {'group_id': groupId, 'announcement_id': announcementId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/leave'),
        data: {'group_id': groupId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> dissolveGroup(String groupId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/dissolve'),
        data: {'group_id': groupId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绉佽亰 ====================

  Future<Map<String, dynamic>> getDirectMessages({
    required String withUid,
    int limit = 100,
    int offset = 0,
    String? beforeCreatedAt,
    String? beforeId,
    int? afterCreatedAt,
    String? afterId,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'with_uid': withUid,
        'limit': limit,
      };
      if (beforeCreatedAt != null) {
        queryParameters['before_created_at'] = beforeCreatedAt;
      }
      if (beforeId != null) {
        queryParameters['before_id'] = beforeId;
      }
      if (afterCreatedAt != null) {
        queryParameters['after_created_at'] = afterCreatedAt;
      }
      if (afterId != null && afterId.isNotEmpty) {
        queryParameters['after_id'] = afterId;
      }
      if (beforeCreatedAt == null && beforeId == null && afterCreatedAt == null) {
        queryParameters['offset'] = offset;
      }

      final response = await _dio.get(
        Constants.directMessagesPath,
        queryParameters: queryParameters,
      );
      if (response.statusCode == 200) {
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        final messages = (data['messages'] as List?)
                ?.whereType<Map>()
                .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
                .toList() ??
            const <Message>[];
        return {
          'messages': messages,
          'has_more': data['has_more'] ?? false,
          'effective_offset': data['effective_offset'] ?? 0,
          'next_before_created_at': data['next_before_created_at'],
          'next_before_id': data['next_before_id'],
        };
      } else {
        throw Exception('Failed to load direct messages');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        try {
          final fallbackQuery = <String, dynamic>{
            'with_uid': withUid,
            'limit': limit,
            if (afterCreatedAt == null) 'offset': offset,
            if (afterCreatedAt != null) 'after_created_at': afterCreatedAt,
            if (afterId != null && afterId.isNotEmpty) 'after_id': afterId,
          };
          final response = await _dio.get(
            Constants.apiPath('/v1/direct/messages'),
            queryParameters: fallbackQuery,
          );
          final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
          final messages = (data['messages'] as List?)?.whereType<Map>().map((item) => Message.fromJson(Map<String, dynamic>.from(item))).toList() ?? const <Message>[];
          return {
            'messages': messages,
            'has_more': data['has_more'] ?? false,
            'effective_offset': data['effective_offset'] ?? offset,
            'next_before_created_at': data['next_before_created_at'],
            'next_before_id': data['next_before_id'],
          };
        } on DioException catch (fallbackError) {
          throw Exception('Network error: ${fallbackError.message}');
        }
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> searchDirectMessages(
    String withUid,
    String query,
  ) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/direct/messages/search'),
        queryParameters: {'with_uid': withUid, 'keyword': query, 'limit': 100},
      );
      return _normalizeSearchResponse(response.data);
    } on DioException catch (e) {
      throw _apiError('搜索私聊记录失败', e);
    }
  }

  Future<Message> sendDirectMessage({
    required String toUid,
    required String body,
    String msgType = 'text',
    String? mediaUrl,
    String? thumbUrl,
    int durationMs = 0,
    int burnAfterSeconds = 0,
  }) async {
    try {
      final payload = {
        'to_uid': toUid,
        'body': body,
        'msg_type': msgType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
        'duration_ms': durationMs,
        'burn_after_seconds': burnAfterSeconds,
      };
      final response = await _dio.post(
        Constants.apiPath('/v1/direct/send'),
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(response.data);
      } else {
        throw Exception('Send direct message failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> sendTyping(
    String targetId,
    bool typing, {
    String type = 'direct',
  }) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/chats/typing'),
        data: {'target_id': targetId, 'typing': typing, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getDirectUnread() async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/direct/unread'),
        data: {'limit': 200},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> markDirectRead(String withUid) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/direct/read'),
        data: {'with_uid': withUid},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> openBurnMessage(String messageId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/direct/burn/open'),
        data: {'message_id': messageId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> recallDirectMessage(String messageId) async {
    try {
      await _dio.delete(Constants.apiPath('/v1/direct/messages/$messageId'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 缇よ亰娑堟伅 ====================

  Future<Map<String, dynamic>> getGroupMessages({
    required String groupId,
    int limit = 100,
    int offset = 0,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'group_id': groupId,
        'limit': limit,
      };
      if (beforeCreatedAt != null) {
        queryParameters['before_created_at'] = beforeCreatedAt;
      }
      if (beforeId != null) {
        queryParameters['before_id'] = beforeId;
      }
      if (beforeCreatedAt == null && beforeId == null) {
        queryParameters['offset'] = offset;
      }

      final response = await _dio.get(
        Constants.groupMessagesPath,
        queryParameters: queryParameters,
      );
      if (response.statusCode == 200) {
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        final messages =
            (data['messages'] as List?)
                ?.whereType<Map>()
                .map((e) => Message.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const <Message>[];
        return {
          'messages': messages,
          'has_more': data['has_more'] ?? false,
          'effective_offset': data['effective_offset'] ?? 0,
          'next_before_created_at': data['next_before_created_at'],
          'next_before_id': data['next_before_id'],
        };
      } else {
        throw Exception('Failed to load group messages');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupMessagesAfter(
    String groupId,
    int afterSeq, {
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/groups/messages/after'),
        queryParameters: {
          'group_id': groupId,
          'after_seq': afterSeq,
          'limit': limit,
        },
      );
      final raw = response.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final rawMessages = data['messages'] is List
          ? data['messages'] as List
          : const [];
      final messages = rawMessages
          .whereType<Map>()
          .map((item) => Message.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      return {
        'messages': messages,
        'has_more': data['has_more'] ?? false,
        'next_group_seq':
            data['next_group_seq'] ?? data['server_group_seq'] ?? afterSeq,
        'server_group_seq': data['server_group_seq'],
      };
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> searchGroupMessages(
    String groupId,
    String query,
  ) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/groups/messages/search'),
        queryParameters: {'group_id': groupId, 'keyword': query, 'limit': 100},
      );
      return _normalizeSearchResponse(response.data);
    } on DioException catch (e) {
      throw _apiError('搜索群聊记录失败', e);
    }
  }

  Future<Message> sendGroupMessage({
    required String groupId,
    required String body,
    String msgType = 'text',
    String? mediaUrl,
    String? thumbUrl,
    int durationMs = 0,
    int burnAfterSeconds = 0,
  }) async {
    try {
      final payload = {
        'group_id': groupId,
        'body': body,
        'msg_type': msgType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
        'duration_ms': durationMs,
        'burn_after_seconds': burnAfterSeconds,
      };
      final response = await _dio.post(
        Constants.apiPath('/v1/groups/message/send'),
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(response.data);
      } else {
        throw Exception('Send group message failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> sendGroupTyping(String groupId, bool typing) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/typing'),
        data: {'group_id': groupId, 'typing': typing},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getGroupUnread() async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/groups/unread'),
        data: {'limit': 200},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> markGroupRead(String groupId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/read'),
        data: {'group_id': groupId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> openGroupBurnMessage(String messageId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/groups/burn/open'),
        data: {'message_id': messageId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> recallGroupMessage(String messageId) async {
    try {
      await _dio.delete(Constants.apiPath('/v1/groups/messages/$messageId'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鐢ㄦ埛璧勬枡 ====================

  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/users/profile'),
        queryParameters: {'uid': uid.trim()},
      );
      final raw = response.data;
      if (raw is Map && raw['data'] is Map) {
        return Map<String, dynamic>.from(raw['data'] as Map);
      }
      return Map<String, dynamic>.from(raw as Map);
    } on DioException catch (e) {
      throw _apiError('加载用户资料失败', e);
    }
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/profile'), data: data);
    } on DioException catch (e) {
      throw _apiError('更新个人资料失败', e);
    }
  }

  Future<void> updateUid(String newUid) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/uid'), data: {'uid': newUid});
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updatePassword(String oldPassword, String newPassword) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/password'),
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateAvatar(FormData formData) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/avatar'), data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> updateCover(FormData formData) async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/cover'), data: formData);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/delete'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绾㈠寘锛堜慨澶嶏細娣诲姞鏃ュ織銆佹竻鐞嗙壒娈婂瓧绗︼級 ====================

  Future<Map<String, dynamic>> createRedPacket({
    required String targetId,
    required String amount,
    required String type,
    int count = 1,
    String title = '鎭枩鍙戣储',
    String? coverUrl,
  }) async {
    try {
      final amountInt = int.tryParse(amount) ?? 0;
      final payload = <String, dynamic>{
        'title': title.trim().isEmpty ? '鎭枩鍙戣储' : title.trim(),
        'total_amount': amountInt,
        'total_count': count > 0 ? count : 1,
        if (type == 'group') 'group_id': targetId else 'to_uid': targetId,
        if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
      };

      final response = await _dio.post(
        Constants.apiPath('/v1/redpackets/send'),
        data: payload,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        final nested = data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : const <String, dynamic>{};
        final packetId =
            data['packet_id'] ??
            data['packetId'] ??
            data['id'] ??
            nested['packet_id'] ??
            nested['packetId'] ??
            nested['id'];
        if (packetId == null || packetId.toString().isEmpty) {
          throw Exception('服务器未返回红包 ID');
        }
        return {...data, 'packet_id': packetId.toString()};
      } else {
        throw Exception('绾㈠寘鍒涘缓澶辫触');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      if (error is String && error.isNotEmpty) {
        throw Exception(error);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> claimRedPacket(String packetId) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/redpackets/claim'),
        data: {'packet_id': packetId},
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('棰嗗彇绾㈠寘澶辫触');
      }
    } on DioException catch (e) {
      final error = e.response?.data;
      if (error is Map && error.containsKey('error')) {
        throw Exception(error['error']);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getRedPacketInfo(String packetId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/redpackets/$packetId'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 涓婁紶鏂囦欢 ====================

  Future<Map<String, dynamic>> uploadFile(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/media'),
        data: formData,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        throw Exception('Upload failed');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> voiceASR(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/voice/asr'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鍔ㄦ€?====================

  Future<Map<String, dynamic>> createMoment({
    required String body,
    String? imageUrl,
    List<String>? imageUrls,
  }) async {
    try {
      final urls =
          <String>[
                ...?imageUrls,
                if (imageUrl != null && imageUrl.isNotEmpty) imageUrl,
              ]
              .map((url) => url.trim())
              .where((url) => url.isNotEmpty)
              .toSet()
              .toList();
      final response = await _dio.post(
        Constants.apiPath('/v1/moments'),
        data: {
          'body': body,
          if (urls.length == 1) 'image_url': urls.first,
          if (urls.length > 1) 'image_url': jsonEncode(urls),
          if (urls.isNotEmpty) 'image_urls': urls,
          if (urls.isNotEmpty) 'images': urls,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMoments({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.momentsPath,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Failed to get moments');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getUserMoments(
    String uid, {
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/moments/user'),
        queryParameters: {'uid': uid, 'limit': limit, 'offset': offset},
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Failed to get user moments');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/like'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/unlike'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMoment(String momentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/delete'),
        data: {'moment_id': momentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentMoment(
    String momentId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/moments/comment'),
        data: {'moment_id': momentId, 'body': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMomentComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/moments/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMomentComments(
    String momentId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/moments/comments'),
        queryParameters: {
          'moment_id': momentId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getPublicCourtCases({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases'),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getPublicCourtCase(String caseId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases/$caseId'),
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> votePublicCourtCase(
    String caseId,
    String vote,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/vote'),
        data: {'vote': vote},
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> submitPublicCourtStatement(
    String caseId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/public-court/cases/$caseId/statement'),
        data: {'content_text': text, 'text': text},
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getPublicCourtDiscussions(String caseId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/public-court/cases/$caseId/discussions'),
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 闊充箰骞垮満 ====================

  Future<Map<String, dynamic>> getMusicPlaza({
    int limit = 20,
    int offset = 0,
    String? endpoint,
    String? query,
  }) async {
    final path = endpoint ?? Constants.apiPath('/v1/music/plaza');
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMyMusic() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/mine'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadMusic(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> updateMusic(
    String musicId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/update'),
        data: {'music_id': musicId, ...data},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<String> getExternalText(String url) async {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        headers: const {'Accept': 'text/plain, text/*;q=0.9, */*;q=0.1'},
      ),
    ).get<String>(url);
    return response.data ?? '';
  }

  Future<Map<String, dynamic>> getMusicLyrics(String musicId) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/lyrics'),
        queryParameters: {'item_id': musicId},
      );
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 ||
          e.response?.statusCode == 405 ||
          e.response?.statusCode == 400) {
        final response = await _dio.post(
          Constants.apiPath('/v1/music/plaza/lyrics'),
          data: {'music_id': musicId},
        );
        final data = response.data;
        return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<String> getMusicLyricsText(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/delete'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMultipleMusic(List<String> musicIds) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/mine/delete-batch'),
        data: {'music_ids': musicIds},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/like'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/unlike'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentMusic(String musicId, String text) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/music/plaza/comment'),
        data: {'music_id': musicId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteMusicComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMusicComments(
    String musicId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/comments'),
        queryParameters: {
          'music_id': musicId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMusicRanking() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/music/plaza/ranking'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> playMusic(String musicId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/music/plaza/play'),
        data: {'music_id': musicId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 琛ㄦ儏骞垮満 ====================

  Future<Map<String, dynamic>> getEmojiPlaza({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/emoji/plaza'),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getMyEmojis() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/emoji/plaza/mine'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadEmoji(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> saveEmoji(String emojiId) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/save'),
        data: {'emoji_id': emojiId},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteEmoji(String emojiId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/emoji/plaza/delete'),
        data: {'emoji_id': emojiId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鏀惰棌 ====================

  Future<Map<String, dynamic>> getFavorites() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/favorites'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> addFavorite(String targetId, String type) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/favorites/add'),
        data: {'target_id': targetId, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> removeFavorite(String targetId, String type) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/favorites/remove'),
        data: {'target_id': targetId, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 閫氱煡 ====================

  Future<Map<String, dynamic>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/notifications'),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/notifications/read'),
        data: {'notification_id': notificationId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 涓炬姤 ====================

  Future<Map<String, dynamic>> reportUser(String uid, String reason) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/reports/user'),
        data: {'uid': uid, 'reason': reason},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> reportGroup(
    String groupId,
    String reason,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/reports/group'),
        data: {'group_id': groupId, 'reason': reason},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 绛惧埌澧?====================

  Future<Map<String, dynamic>> getCheckinWall() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me/checkin/wall'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> postCheckinWall(
    String text, {
    List<String>? mediaUrls,
  }) async {
    try {
      final urls = (mediaUrls ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final response = await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall'),
        data: {
          'text': text,
          if (urls.isNotEmpty) ...{
            'image_urls': urls,
            'images': urls,
            'image_url': urls.length == 1 ? urls.first : jsonEncode(urls),
          },
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeCheckinWall(String postId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/like'),
        data: {'post_id': postId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeCheckinWall(String postId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/unlike'),
        data: {'post_id': postId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentCheckinWall(
    String postId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/me/checkin/wall/comment'),
        data: {'post_id': postId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getCheckinWallComments(
    String postId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/me/checkin/wall/comments'),
        queryParameters: {'post_id': postId, 'limit': limit, 'offset': offset},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== AI ====================

  Future<Map<String, dynamic>> getAIQuota() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/ai/quota'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> chatWithAI(
    String message, {
    String? model,
    AISettings? settings,
  }) async {
    if (settings != null &&
        settings.apiKey.trim().isNotEmpty &&
        settings.baseUrl.trim().isNotEmpty) {
      final base = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final endpoint = base.endsWith('/chat/completions')
          ? base
          : '$base/chat/completions';
      final response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Authorization': 'Bearer ${settings.apiKey.trim()}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          ).post(
            endpoint,
            data: {
              'messages': [
                {'role': 'user', 'content': message},
              ],
              if (model != null) 'model': model,
            },
          );
      return Map<String, dynamic>.from(response.data as Map);
    }
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/ai/chat/completions'),
        data: {
          'messages': [
            {'role': 'user', 'content': message},
          ],
          if (model != null) 'model': model,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<({String baseUrl, String apiKey})?> _customAIOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('ai_api_key')?.trim() ?? '';
    final baseUrl = prefs.getString('ai_base_url')?.trim() ?? '';
    if (apiKey.isEmpty || baseUrl.isEmpty) return null;
    return (baseUrl: baseUrl, apiKey: apiKey);
  }

  // ==================== 绛惧埌 ====================

  Future<Map<String, dynamic>> dailyCheckin() async {
    try {
      final response = await _dio.post(Constants.apiPath('/v1/me/checkin'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 璁惧绠＄悊 ====================

  Future<Map<String, dynamic>> getDevices() async {
    try {
      final response = await _dio.get(Constants.apiPath('/v1/me/devices'));
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> cleanupDevices() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/devices/cleanup'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> cleanupOtherDevices() async {
    try {
      await _dio.post(Constants.apiPath('/v1/me/devices/cleanup-others'));
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 鍙嶉 ====================

  Future<Map<String, dynamic>> submitFeedback(
    String type,
    String content, {
    List<String>? images,
  }) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/feedback'),
        data: {
          'type': type,
          'content': content,
          if (images != null) 'images': images,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  // ==================== 璧勬簮鍖?====================

  Future<Map<String, dynamic>> getResourceSections() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/sections'),
        queryParameters: {'limit': 200, 'offset': 0},
      );
      final data = response.data;
      debugPrint('[资源广场] sections-json=${jsonEncode(data)}');
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] sections error ${e.response?.statusCode}: ${e.response?.data}',
      );
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createResourceSection(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/sections'),
        data: data,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResourceSection(String sectionId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/sections/delete'),
        data: {'section_id': sectionId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> uploadResource(FormData formData) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/upload'),
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceQuota() async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/me/resources/quota'),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceItems({
    int limit = 20,
    int offset = 0,
    String? sectionId,
  }) async {
    try {
      final normalizedSectionId = sectionId?.trim();
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/items'),
        queryParameters: {
          if (normalizedSectionId != null && normalizedSectionId.isNotEmpty)
            'section_id': normalizedSectionId,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = response.data;
      debugPrint(
        '[资源广场] items-json=${jsonEncode(<String, dynamic>{'section_id': normalizedSectionId, 'limit': limit, 'offset': offset, 'response': data})}',
      );
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] items error ${e.response?.statusCode}: ${e.response?.data}',
      );
      final data = e.response?.data;
      final detail = data is Map
          ? (data['error'] ?? data['message'] ?? data['code'])
          : null;
      throw Exception('资源列表请求失败${detail == null ? '' : '：$detail'}');
    }
  }

  Future<Map<String, dynamic>> searchResources(String query) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/search'),
        queryParameters: {'q': query.trim()},
      );
      final data = response.data;
      debugPrint(
        '[资源广场] search-json=${jsonEncode(<String, dynamic>{'query': query.trim(), 'response': data})}',
      );
      return data is Map ? Map<String, dynamic>.from(data) : {'data': data};
    } on DioException catch (e) {
      debugPrint(
        '[资源广场] search error ${e.response?.statusCode}: ${e.response?.data}',
      );
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/items/delete'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> likeResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/like'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> unlikeResource(String resourceId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/unlike'),
        data: {'resource_id': resourceId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> commentResource(
    String resourceId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        Constants.apiPath('/v1/resources/comment'),
        data: {'resource_id': resourceId, 'text': text},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getResourceComments(
    String resourceId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        Constants.apiPath('/v1/resources/comments'),
        queryParameters: {
          'resource_id': resourceId,
          'limit': limit,
          'offset': offset,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> deleteResourceComment(String commentId) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/comment/delete'),
        data: {'comment_id': commentId},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  Future<void> reportResource(String resourceId, String reason) async {
    try {
      await _dio.post(
        Constants.apiPath('/v1/resources/report'),
        data: {'resource_id': resourceId, 'reason': reason},
      );
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

}
