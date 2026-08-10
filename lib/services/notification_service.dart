import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../pages/chat_page.dart';
import '../utils/constants.dart';
import '../utils/navigation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(Constants.desktopNotificationsKey) ?? true;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(Constants.desktopNotificationsKey, value);
  }

  void _onNotificationTap(NotificationResponse response) => _openConversation(response.payload);

  void _openConversation(String? payload) {
    windowManager.show();
    windowManager.focus();
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length != 2) return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => ChatPage(conversationId: parts[1], type: parts[0], title: '聊天', embed: false),
    ));
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool withFlash = false,
  }) async {
    if (!_enabled) return;
    if (!Platform.isWindows) {
      const androidDetails = AndroidNotificationDetails(
        'chat_channel',
        '聊天消息',
        channelDescription: '收到新消息时通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    }
    if (withFlash) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }

  Future<void> showMessageNotification({
    required String fromName,
    required String message,
    String? conversationId,
    String? conversationType,
    bool withFlash = false,
  }) async {
    final payload = conversationId != null && conversationType != null ? '$conversationType|$conversationId' : null;
    await showNotification(
      title: '来自 $fromName 的消息',
      body: message.length > 100 ? '${message.substring(0, 100)}...' : message,
      payload: payload,
      withFlash: withFlash,
    );
  }
}
