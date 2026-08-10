import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_service.dart';
import '../utils/constants.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _token;
  String? _userId;
  String? _refreshToken;
  String? _savedUsername;
  String? _savedPassword;

  String? get token => _token;
  String? get userId => _userId;
  String? get refreshToken => _refreshToken;
  String? get savedUsername => _savedUsername;
  String? get savedPassword => _savedPassword;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(Constants.tokenKey);
    _userId = prefs.getString(Constants.userIdKey);
    _refreshToken = prefs.getString(Constants.refreshTokenKey);
    _savedUsername = prefs.getString(Constants.savedUsernameKey);
    _savedPassword = prefs.getString(Constants.savedPasswordKey);
    notifyListeners();
  }

  Future<void> saveToken(
    String token, {
    String? userId,
    String? refreshToken,
  }) async {
    _token = token;
    if (userId != null) _userId = userId;
    if (refreshToken != null) _refreshToken = refreshToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.tokenKey, token);
    if (userId != null) {
      await prefs.setString(Constants.userIdKey, userId);
      await CacheService().ensureUserDirectory(userId);
    }
    if (refreshToken != null) {
      await prefs.setString(Constants.refreshTokenKey, refreshToken);
    }
    if (userId != null && userId.isNotEmpty) {
      await CacheService().directory(userId: userId);
    }
    if (_userId != null) {
      await CacheService().ensureUserDirectory(_userId!);
    }
    notifyListeners();
  }

  // ★ 保存账号密码（用于自动登录）
  Future<void> saveCredentials(String username, String password) async {
    _savedUsername = username;
    _savedPassword = password;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.savedUsernameKey, username);
    await prefs.setString(Constants.savedPasswordKey, password);
  }

  // ★ 清除账号密码
  Future<void> clearCredentials() async {
    _savedUsername = null;
    _savedPassword = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.savedUsernameKey);
    await prefs.remove(Constants.savedPasswordKey);
  }

  Future<void> clear() async {
    _token = null;
    _userId = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
    await prefs.remove(Constants.userIdKey);
    await prefs.remove(Constants.refreshTokenKey);
    notifyListeners();
  }

  Future<String?> getRefreshToken() async {
    if (_refreshToken != null) return _refreshToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.refreshTokenKey);
  }

  bool get isLoggedIn => _token != null;
}
