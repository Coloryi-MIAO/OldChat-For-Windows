import 'package:shared_preferences/shared_preferences.dart';

class Constants {
  static const String baseUrlKey = 'base_url';
  static const String apiVersionKey = 'api_version';
  static const String defaultBaseUrl = 'http://154.9.24.232';

  static String _baseUrl = defaultBaseUrl;
  static String _apiVersion = 'v2';

  static String get apiVersion => _apiVersion;

  static String apiPath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    if (!normalized.startsWith('/v1/')) return normalized;
    return '/v1/${normalized.substring(4)}';
  }

  static String get baseUrl {
    return _baseUrl;
  }

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(baseUrlKey) ?? defaultBaseUrl;
    final version = prefs.getString(apiVersionKey) ?? 'v2';
    _apiVersion = version == 'v1' ? 'v1' : 'v2';
  }

  static Future<void> saveBaseUrl(String url) async {
    _baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(baseUrlKey, url.trim());
  }

  static Future<void> saveApiVersion(String version) async {
    _apiVersion = version == 'v1' ? 'v1' : 'v2';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(apiVersionKey, _apiVersion);
  }

  static String get loginPath => apiPath('/v1/auth/login');
  static String get directMessagesPath => apiPath(
        _apiVersion == 'v1' ? '/v1/direct/messages' : '/v1/direct/messages/v2',
      );
  static String get groupMessagesPath => apiPath(
        _apiVersion == 'v1' ? '/v1/groups/messages' : '/v1/groups/messages/v2',
      );
  static String get momentsPath => apiPath(
        _apiVersion == 'v1' ? '/v1/moments' : '/v1/moments/v2',
      );
  static String get wsPath => apiPath('/v1/ws');
  static const String geetestCaptchaId = '769d069177e132e46eeba07a6210cf3a';
  static const String tokenKey = 'access_token';
  static const String userIdKey = 'user_id';
  static const String refreshTokenKey = 'refresh_token';
  static const String savedUsernameKey = 'saved_username'; // ★ 新增
  static const String savedPasswordKey = 'saved_password';
  static const String desktopNotificationsKey = 'desktop_notifications_enabled';
  static const String autoUpdateKey = 'auto_update_enabled';
  static const String updateChannelKey = 'update_channel';
  static const String aria2EndpointKey = 'aria2_rpc_endpoint';
  static const String aria2SecretKey = 'aria2_rpc_secret';
}
