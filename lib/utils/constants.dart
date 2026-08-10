import 'package:shared_preferences/shared_preferences.dart';

class Constants {
  static const String baseUrlKey = 'base_url';
  static const String defaultBaseUrl = 'http://60.205.94.101:8080';

  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl {
    return _baseUrl;
  }

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(baseUrlKey) ?? defaultBaseUrl;
  }

  static Future<void> saveBaseUrl(String url) async {
    _baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(baseUrlKey, url.trim());
  }

  static const String loginPath = '/v1/auth/login';
  static const String directMessagesPath = '/v1/direct/messages/v2';
  static const String groupMessagesPath = '/v1/groups/messages/v2';
  static const String wsPath = '/v1/ws';
  static const String tokenKey = 'access_token';
  static const String userIdKey = 'user_id';
  static const String refreshTokenKey = 'refresh_token';
  static const String savedUsernameKey = 'saved_username'; // ★ 新增
  static const String savedPasswordKey = 'saved_password';
  static const String desktopNotificationsKey = 'desktop_notifications_enabled';
  static const String aria2EndpointKey = 'aria2_rpc_endpoint';
  static const String aria2SecretKey = 'aria2_rpc_secret';
}
