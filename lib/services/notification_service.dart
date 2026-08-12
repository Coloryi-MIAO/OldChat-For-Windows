import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win_toast/win_toast.dart';

import '../pages/chat_page.dart';
import '../utils/constants.dart';
import '../utils/navigation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _enabled = true;
  static bool _winToastInitialized = false;

  bool get enabled => _enabled;

  String _notificationIconPath() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '${executableDir}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico',
      '${executableDir}${Platform.pathSeparator}app_icon.ico',
      '${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico',
      '${executableDir}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.png',
      '${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.png',
    ];
    return candidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(Constants.desktopNotificationsKey) ?? true;
    if (Platform.isWindows) {
      try {
        _winToastInitialized = await WinToast.instance().initialize(
          aumId: 'Coloryi.OldChatDesktop',
          displayName: 'OldChat Desktop',
          iconPath: _notificationIconPath(),
          clsid: '936C39FC-6BBC-4A57-B8F8-7C627E401B2F',
        );
      } catch (error) {
        _winToastInitialized = false;
        debugPrint('[Windows 通知] 初始化失败：$error');
      }
      if (_winToastInitialized) {
        WinToast.instance().setActivatedCallback((event) {
          _openConversation(event.argument);
        });
      }
    }
    if (!Platform.isWindows) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      await _notifications.initialize(
        const InitializationSettings(android: androidSettings),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(Constants.desktopNotificationsKey, value);
  }

  void _onNotificationTap(NotificationResponse response) =>
      _openConversation(response.payload);

  void _openConversation(String? payload) {
    windowManager.show();
    windowManager.focus();
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length != 2) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversationId: parts[1],
          type: parts[0],
          title: '聊天',
          embed: false,
        ),
      ),
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool withFlash = false,
  }) async {
    if (!_enabled) return;
    if (Platform.isWindows && _winToastInitialized) {
      final safeTitle = _escapeXml(title);
      final safeBody = _escapeXml(body);
      final launch = _escapeXml(payload ?? '');
      await WinToast.instance().showCustomToast(
        xml:
            '<?xml version="1.0" encoding="utf-8"?><toast launch="$launch"><visual><binding template="ToastGeneric"><text>$safeTitle</text><text>$safeBody</text></binding></visual></toast>',
        tag: 'oldchat-${DateTime.now().millisecondsSinceEpoch}',
        group: 'oldchat',
      );
    }
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

  String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
