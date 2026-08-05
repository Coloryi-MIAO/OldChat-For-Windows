import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/navigation.dart';
import '../pages/chat_page.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings =
        InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    windowManager.show();
    windowManager.focus();
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final parts = payload.split('|');
        if (parts.length == 2) {
          final type = parts[0];
          final id = parts[1];
          navigatorKey.currentState?.push(
            MaterialPageRoute(
                builder: (_) => ChatPage(
                    conversationId: id, type: type, title: '聊天', embed: false)),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool withFlash = false,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '聊天消息',
      channelDescription: '收到新消息时通知',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );

    if (withFlash) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {
        print('托盘闪烁功能调用失败，已降级为窗口唤起');
      }
    }
  }

  Future<void> showMessageNotification({
    required String fromName,
    required String message,
    String? conversationId,
    String? conversationType,
    bool withFlash = false,
  }) async {
    final payload = conversationId != null && conversationType != null
        ? '$conversationType|$conversationId'
        : null;
    await showNotification(
      title: '来自 $fromName 的消息',
      body: message.length > 100 ? '${message.substring(0, 100)}...' : message,
      payload: payload,
      withFlash: withFlash,
    );
  }
}
