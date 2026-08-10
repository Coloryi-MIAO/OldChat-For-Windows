import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Aria2Service {
  static final Aria2Service _instance = Aria2Service._internal();
  factory Aria2Service() => _instance;
  Aria2Service._internal();

  static const endpointKey = 'aria2_rpc_endpoint';
  static const secretKey = 'aria2_rpc_secret';
  static const defaultEndpoint = 'http://127.0.0.1:6800/jsonrpc';

  Future<Map<String, String>> settings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'endpoint': prefs.getString(endpointKey) ?? defaultEndpoint,
      'secret': prefs.getString(secretKey) ?? '',
    };
  }

  Future<void> saveSettings({required String endpoint, required String secret}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(endpointKey, endpoint.trim().isEmpty ? defaultEndpoint : endpoint.trim());
    await prefs.setString(secretKey, secret.trim());
  }

  Future<String> addUri(String url, {String? fileName}) async {
    final value = url.trim();
    if (value.isEmpty) throw Exception('下载地址为空');
    final config = await settings();
    final options = <String, String>{};
    if (fileName != null && fileName.trim().isNotEmpty) {
      options['out'] = fileName.trim();
    }
    final params = <dynamic>[
      if (config['secret']!.isNotEmpty) 'token:${config['secret']}',
      [value],
      options,
    ];
    final response = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    )).post(
      config['endpoint']!,
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': DateTime.now().microsecondsSinceEpoch,
        'method': 'aria2.addUri',
        'params': params,
      }),
    );
    final data = response.data is String ? jsonDecode(response.data) : response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']['message'] ?? 'aria2 添加任务失败');
    }
    final gid = data is Map ? data['result']?.toString() : null;
    if (gid == null || gid.isEmpty) throw Exception('aria2 未返回任务 ID');
    return gid;
  }
}
