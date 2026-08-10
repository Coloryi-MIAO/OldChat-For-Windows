import 'dart:io';
import 'package:flutter/material.dart';
import 'services/image_cache_service.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'widgets/tray_manager.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/audio_service.dart';
import 'widgets/custom_title_bar.dart';
import 'pages/login_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_profile_page.dart';
import 'pages/moments_page.dart';
import 'pages/music_plaza_page.dart';
import 'pages/emoji_plaza_page.dart';
import 'pages/notifications_page.dart';
import 'pages/checkin_wall_page.dart';
import 'pages/ai_chat_page.dart';
import 'pages/favorites_page.dart';
import 'pages/about_page.dart';
import 'pages/settings_page.dart';
import 'pages/chat_page.dart';
import 'utils/navigation.dart';
import 'utils/constants.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  ImageCacheService.configure();
  VideoPlayerMediaKit.ensureInitialized(
    windows: true,
  );

  // ★ 加载用户自定义 baseUrl
  await Constants.loadBaseUrl();
  final themeController = AppThemeController();
  await themeController.load();

  // 单例检测
  await WindowsSingleInstance.ensureSingleInstance(
    args,
    "oldchat_app",
    onSecondWindow: (secondArgs) {
      print('第二个实例启动: $secondArgs');
    },
  );

  await windowManager.ensureInitialized();

  // 全局音频服务初始化
  await AudioService().init();

  // 窗口关闭事件监听
  windowManager.addListener(_WindowCloseListener());

  const windowOptions = WindowOptions(
    size: Size(1100, 700),
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    fullScreen: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final notificationService = NotificationService();
  await notificationService.init();

  final auth = AuthService();
  await auth.loadFromStorage();

  runApp(
    TrayManager(
      child: MyApp(auth: auth, notificationService: notificationService, themeController: themeController),
    ),
  );
}

// 窗口关闭监听器
class _WindowCloseListener extends WindowListener {
  @override
  void onWindowEvent(String event) async {
    if (event == 'close') {
      final result = await _showExitDialog();
      if (result == 2) {
        await AuthService().clear();
        await windowManager.destroy();
        exit(0);
      } else if (result == 1) {
        await windowManager.hide();
      }
    }
  }

  Future<int> _showExitDialog() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return 0;
    return await showDialog<int>(
          context: ctx,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('退出程序'),
            content: const Text('确定要退出程序吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 0),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 1),
                child: const Text('最小化到托盘'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 2),
                child: const Text('退出', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        0;
  }

  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowMove() {}
}

class MyApp extends StatelessWidget {
  final AuthService auth;
  final NotificationService notificationService;
  final AppThemeController themeController;

  const MyApp({
    super.key,
    required this.auth,
    required this.notificationService,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider.value(value: notificationService),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: Consumer<AppThemeController>(
        builder: (context, themeController, _) => MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          title: 'OldChat Desktop',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(pink: themeController.isPink),
          home: const LoginPage(),
          routes: {
            '/profile': (context) => const ProfilePage(),
            '/user_profile': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as String;
              return UserProfilePage(uid: args);
            },
            '/moments': (context) => const MomentsPage(),
            '/user_moments': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as String;
              return MomentsPage(uid: args);
            },
            '/music_plaza': (context) => const MusicPlazaPage(),
            '/emoji_plaza': (context) => const EmojiPlazaPage(),
            '/notifications': (context) => const NotificationsPage(),
            '/checkin_wall': (context) => const CheckinWallPage(),
            '/ai_chat': (context) => const AIChatPage(),
            '/favorites': (context) => const FavoritesPage(),
            '/about': (context) => const AboutPage(),
            '/settings': (context) => const SettingsPage(),
            '/chat': (context) {
              final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, String>;
              return ChatPage(
                conversationId: args['uid'] ?? '',
                type: 'direct',
                title: args['title'] ?? '聊天',
                embed: false,
              );
            },
          },
          builder: (context, child) {
            final isLogin = ModalRoute.of(context)?.settings.name == '/';
            if (isLogin) return child!;
            return Column(
              children: [
                const CustomTitleBar(),
                Expanded(child: child!),
              ],
            );
          },
        ),
      ),
    );
  }
}
