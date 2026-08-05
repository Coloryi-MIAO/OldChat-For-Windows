import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/constants.dart';
import '../models/message.dart';
import 'auth_service.dart';
import 'api_service.dart';

typedef OnMessageCallback = void Function(Message message);
typedef OnEventCallback = void Function(String type, Map<String, dynamic> data);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  IOWebSocketChannel? _channel;
  bool _connecting = false;
  bool _shouldReconnect = true;
  int _connectionGeneration = 0;
  bool _connected = false;
  final AuthService _auth = AuthService();
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  bool _isReconnecting = false;
  int _refreshAttempts = 0;
  static const int _maxRefreshAttempts = 2;

  OnEventCallback? onEvent;
  final Set<OnMessageCallback> _directListeners = <OnMessageCallback>{};
  final Set<OnMessageCallback> _groupListeners = <OnMessageCallback>{};

  void addDirectListener(OnMessageCallback listener) => _directListeners.add(listener);
  void removeDirectListener(OnMessageCallback listener) => _directListeners.remove(listener);
  void addGroupListener(OnMessageCallback listener) => _groupListeners.add(listener);
  void removeGroupListener(OnMessageCallback listener) => _groupListeners.remove(listener);

  void _emit(Set<OnMessageCallback> listeners, Message message) {
    for (final listener in List<OnMessageCallback>.from(listeners)) {
      try {
        listener(message);
      } catch (error) {
        print('WebSocket: listener error - $error');
      }
    }
  }

  void connect() {
    if (_connected || _connecting || _channel != null) return;
    final token = _auth.token;
    if (token == null || token.isEmpty) {
      print('WebSocket: No token, skip');
      return;
    }
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    _connecting = true;
    final generation = ++_connectionGeneration;

    try {
      final baseUri = Uri.parse(Constants.baseUrl);
      final wsUri = baseUri.replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
        path: Constants.wsPath,
        queryParameters: const <String, String>{},
      );
      late final IOWebSocketChannel channel;
      channel = IOWebSocketChannel.connect(
        wsUri,
        headers: {'Authorization': 'Bearer $token'},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 10),
      );
      _channel = channel;
      channel.stream.listen(
        (data) => _handleMessage(data),
        onDone: () => _handleDisconnected(channel, generation),
        onError: (error) {
          final authError = error.toString().contains('401') ||
              error.toString().contains('Unauthorized');
          _handleDisconnected(channel, generation, error, false);
          if (authError) {
            unawaited(_refreshTokenAndReconnect());
          } else if (_shouldReconnect) {
            _scheduleReconnect();
          }
        },
      );
      unawaited(_markReady(channel, generation));
    } catch (e) {
      _connecting = false;
      _channel = null;
      print('WebSocket: Connection failed - $e');
      _scheduleReconnect();
    }
  }

  Future<void> _markReady(IOWebSocketChannel channel, int generation) async {
    try {
      await channel.ready;
      if (!identical(_channel, channel)) return;
      _connected = true;
      _reconnectAttempts = 0;
      _refreshAttempts = 0;
      _isReconnecting = false;
      print('WebSocket: Connected');
    } catch (e) {
      _handleDisconnected(channel, generation, e);
    }
  }

  void _handleDisconnected(
    IOWebSocketChannel channel,
    int generation, [
    Object? error,
    bool schedule = true,
  ]) {
    if (generation != _connectionGeneration || !identical(_channel, channel)) return;
    _channel = null;
    _connected = false;
    _connecting = false;
    if (error != null) print('WebSocket: Error - $error');
    print('WebSocket: Disconnected');
    if (_shouldReconnect && schedule) _scheduleReconnect();
  }

  void _emitDirect(Message message) {
    _emit(_directListeners, message);
  }

  void _emitGroup(Message message) {
    _emit(_groupListeners, message);
  }

  Future<void> _refreshTokenAndReconnect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    // 检查刷新次数是否已达上限
    _refreshAttempts++;
    try {
      final refreshToken = await _auth.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        print('WebSocket: 尝试刷新 token (第 $_refreshAttempts 次)...');
        final api = ApiService();
        final data = await api.refreshToken(refreshToken);
        if (data['access_token'] != null) {
          await _auth.saveToken(
            data['access_token'],
            userId: data['user_id'],
            refreshToken: data['refresh_token'] ?? refreshToken,
          );
          print('WebSocket: Token 刷新成功，重新连接...');
          _reconnectAttempts = 0;
          _refreshAttempts = 0;
          disconnect();
          connect();
          return;
        } else {
          print('WebSocket: 刷新返回数据缺少 access_token');
        }
      } else {
        print('WebSocket: 没有 refresh token，无法刷新');
        // ★ 不清除 token，只停止重连
        _isReconnecting = false;
        _scheduleReconnect();
        return;
      }
    } catch (e) {
      print('WebSocket: Token 刷新失败: $e');
      // ★ 如果是 429，不清除 token，只打印警告
      if (e.toString().contains('429')) {
        print('WebSocket: 触发限流 (429)，暂停刷新，等待下次重连');
        _isReconnecting = false;
        // 降低重试频率（增加延迟）
        _reconnectAttempts = _maxReconnectAttempts - 1; // 让后续重连间隔更长
        return;
      }
      // 其他错误（如网络问题）也不清除 token
    }
    _isReconnecting = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer?.isActive == true || _connecting) return;
    _reconnectAttempts++;
    final exponent = _reconnectAttempts > 4 ? 4 : _reconnectAttempts - 1;
    final delay = Duration(seconds: _reconnectDelay.inSeconds * (1 << exponent));
    print('WebSocket: ${delay.inSeconds}秒后重连 (尝试 $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_shouldReconnect && !_connected && !_connecting) connect();
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionGeneration++;
    final channel = _channel;
    _channel = null;
    _connected = false;
    _connecting = false;
    _reconnectAttempts = 0;
    if (channel != null) {
      unawaited(channel.sink.close(status.normalClosure));
    }
    print('WebSocket: 主动断开');
  }

  bool get isConnected => _connected;

  void _handleMessage(dynamic data) {
    try {
      dynamic decoded = data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map) return;

      final envelope = Map<String, dynamic>.from(decoded as Map);
      var type = envelope['type']?.toString().toLowerCase();
      dynamic rawPayload = envelope['data'] ?? envelope['message'] ?? envelope['payload'] ?? envelope;
      if (rawPayload is String) rawPayload = jsonDecode(rawPayload);
      if (rawPayload is! Map) return;
      var payload = Map<String, dynamic>.from(rawPayload as Map);
      final nestedType = payload['type']?.toString().toLowerCase();
      if ((type == null || type == 'message' || type == 'event') && nestedType != null) {
        type = nestedType;
      }
      if (payload['message'] is Map) {
        payload = Map<String, dynamic>.from(payload['message'] as Map);
      }

      final normalizedType = (type ?? '').replaceAll('-', '_').replaceAll('.', '_');
      final isGroup = normalizedType == 'group_message' || normalizedType == 'new_group_message' ||
          (normalizedType == 'new_message' && payload['group_id'] != null);
      final isDirect = normalizedType == 'direct_message' || normalizedType == 'new_direct_message' ||
          (normalizedType == 'new_message' && payload['group_id'] == null);
      if ((!isDirect && !isGroup) || payload['id'] == null) return;

      onEvent?.call(normalizedType, payload);
      final message = Message.fromJson(payload);
      if (isDirect) {
        _emitDirect(message);
      } else {
        _emitGroup(message);
      }
    } catch (e) {
      print('WebSocket: 解析消息错误 - $e');
    }
  }
}
