import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/constants.dart';
import '../services/aria2_service.dart';
import '../services/cache_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/image_cache_service.dart';
import '../services/diagnostics_service.dart';
import '../services/auth_service.dart';
import 'about_page.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _cacheSize = '计算中...';
  bool _showAria2 = false;
  final _aria2EndpointController = TextEditingController();
  final _aria2SecretController = TextEditingController();

  // 关闭窗口设置
  bool _closeConfirmEnabled = true;
  bool _closeMinimizeToTray = false;
  bool _desktopNotificationsEnabled = true;
  bool _autoUpdateEnabled = true;
  String _apiVersion = Constants.apiVersion;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheInfo();
  }

  @override
  void dispose() {
    _aria2EndpointController.dispose();
    _aria2SecretController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _closeConfirmEnabled = prefs.getBool('close_confirm_enabled') ?? true;
      _closeMinimizeToTray = prefs.getBool('close_minimize_to_tray') ?? false;
      _desktopNotificationsEnabled =
          prefs.getBool(Constants.desktopNotificationsKey) ?? true;
      _autoUpdateEnabled = prefs.getBool(Constants.autoUpdateKey) ?? true;
      _apiVersion = prefs.getString(Constants.apiVersionKey) == 'v1'
          ? 'v1'
          : 'v2';
      _showAria2 = prefs.getBool('aria2_show_settings') ?? false;
    });
    final settings = await Aria2Service().settings();
    _aria2EndpointController.text =
        settings['endpoint'] ?? Aria2Service.defaultEndpoint;
    _aria2SecretController.text = settings['secret'] ?? '';
  }

  Future<void> _loadCacheInfo() async {
    final bytes = await CacheService().sizeBytes();
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final count = await CacheService().count;
    setState(() => _cacheSize = '$count 个文件，共 $mb MB');
  }

  Future<void> _clearCache() async {
    try {
      await CacheService().clearClientCache();
      ImageCacheService.instance.clear();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _loadCacheInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清除'), duration: Duration(seconds: 2)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清除缓存失败：$error')));
      }
    }
  }

  Future<void> _chooseCacheLocation() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await CacheService().setLocation(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('缓存位置已设置为 $result'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveAria2Settings() async {
    await Aria2Service().saveSettings(
      endpoint: _aria2EndpointController.text,
      secret: _aria2SecretController.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aria2 设置已保存'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkUpdate() async {
    final service = UpdateService();
    try {
      final current = await service.currentVersion();
      final release = await service.available(UpdateChannel.stable);
      if (!mounted) return;
      if (release == null) {
        _showAlert('已是最新版本', '当前版本：$current');
        return;
      }
      await UpdateDialog.show(
        context,
        release: release,
        currentVersion: current,
      );
    } catch (error) {
      if (mounted) _showAlert('检查更新失败', error.toString());
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final theme = Provider.of<AppThemeController>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _animatedCategory('通用', Icons.tune, [
            _buildFontSetting(theme, primary),
            _buildApiVersionSetting(primary),
          ], 0),
          const SizedBox(height: 12),
          _animatedCategory('外观', Icons.palette_outlined, [
            _buildSwitchTile(
              icon: Icons.favorite,
              title: '粉色主题',
              subtitle: '启用粉色主题配色',
              value: theme.isPink,
              onChanged: (v) => theme.setPink(v),
            ),
          ], 1),
          const SizedBox(height: 12),
          _animatedCategory('通知', Icons.notifications_none, [
            _buildSwitchTile(
              icon: Icons.notifications,
              title: '桌面通知',
              subtitle: '收到新消息时显示 Windows 通知',
              value: _desktopNotificationsEnabled,
              onChanged: (v) async {
                setState(() => _desktopNotificationsEnabled = v);
                await NotificationService().setEnabled(v);
              },
            ),
          ], 2),
          const SizedBox(height: 12),
          _animatedCategory('窗口', Icons.window, [
            _buildSwitchTile(
              icon: Icons.close,
              title: '关闭时确认',
              subtitle: '关闭窗口时弹出确认对话框',
              value: _closeConfirmEnabled,
              onChanged: (v) {
                setState(() => _closeConfirmEnabled = v);
                SharedPreferences.getInstance().then(
                  (prefs) => prefs.setBool('close_confirm_enabled', v),
                );
              },
            ),
            if (!_closeConfirmEnabled)
              _buildChoiceTile(
                icon: Icons.minimize,
                title: '关闭操作',
                subtitle: _closeMinimizeToTray ? '最小化到系统托盘' : '直接退出程序',
                options: ['直接退出', '最小化到托盘'],
                selectedIndex: _closeMinimizeToTray ? 1 : 0,
                onSelected: (index) {
                  final minimize = index == 1;
                  setState(() => _closeMinimizeToTray = minimize);
                  SharedPreferences.getInstance().then((prefs) async {
                    await prefs.setBool('close_minimize_to_tray', minimize);
                    await prefs.setString(
                      'exit_close_action',
                      minimize ? 'minimize' : 'exit',
                    );
                  });
                },
              ),
          ], 3),
          const SizedBox(height: 12),
          _animatedCategory('存储', Icons.storage, [
            _buildInfoTile(
              icon: Icons.cached,
              title: '缓存大小',
              subtitle: _cacheSize,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _clearCache,
                    child: const Text('清除缓存', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _chooseCacheLocation,
                    child: const Text('选择位置', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ], 4),
          const SizedBox(height: 12),
          _animatedCategory('下载', Icons.download, [
            _buildSwitchTile(
              icon: Icons.settings_ethernet,
              title: 'Aria2 设置',
              subtitle: '显示高级下载设置',
              value: _showAria2,
              onChanged: (v) {
                setState(() => _showAria2 = v);
                SharedPreferences.getInstance().then(
                  (prefs) => prefs.setBool('aria2_show_settings', v),
                );
              },
            ),
            if (_showAria2) ...[
              _buildTextInputTile(
                icon: Icons.link,
                title: '端点',
                controller: _aria2EndpointController,
                hint: Aria2Service.defaultEndpoint,
              ),
              _buildTextInputTile(
                icon: Icons.key,
                title: '密钥',
                controller: _aria2SecretController,
                hint: '留空则不使用密钥',
                obscure: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 8),
                child: ElevatedButton.icon(
                  onPressed: _saveAria2Settings,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('保存 Aria2 设置'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ], 5),
          const SizedBox(height: 12),
          _animatedCategory('信息', Icons.info_outline, [
            _buildSwitchTile(
              icon: Icons.system_update_alt,
              title: '自动检查更新',
              subtitle: '启动应用后在后台检查新版本',
              value: _autoUpdateEnabled,
              onChanged: (value) async {
                setState(() => _autoUpdateEnabled = value);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(Constants.autoUpdateKey, value);
              },
            ),
            _buildInfoTile(
              icon: Icons.update,
              title: '检查更新',
              subtitle: '点击检查是否有新版本',
              onTap: _checkUpdate,
            ),
            _buildInfoTile(
              icon: Icons.bug_report,
              title: '环境诊断',
              subtitle: '查看系统环境信息',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            _buildInfoTile(
              icon: Icons.dns,
              title: 'DNS 缓存',
              subtitle: '清除系统 DNS 缓存',
              onTap: () async {
                await DiagnosticsService.clearDnsCache();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('DNS 缓存已清除'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            _buildInfoTile(
              icon: Icons.logout,
              title: '退出登录',
              subtitle: '清除登录状态并返回登录页',
              danger: true,
              onTap: () async {
                await context.read<AuthService>().clear();
                if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
            ),
          ], 6),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _animatedCategory(
    String title,
    IconData icon,
    List<Widget> children, [
    int index = 0,
  ]) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 55),
      curve: Curves.easeOutCubic,
      child: _buildCategory(title, icon, children),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCategory(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
            ),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildFontSetting(AppThemeController theme, Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.font_download_outlined, size: 22, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '字体',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                DropdownButtonFormField<String>(
                  value: theme.fontFamily,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'HarmonyOS Sans SC',
                      child: Text('鸿蒙字体'),
                    ),
                    DropdownMenuItem(
                      value: 'Microsoft YaHei',
                      child: Text('微软雅黑（系统字体）'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) theme.setFontFamily(value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiVersionSetting(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.api_outlined, size: 22, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'API 路径版本',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                DropdownButtonFormField<String>(
                  value: _apiVersion,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'v1', child: Text('v1（兼容旧服务端）')),
                    DropdownMenuItem(value: 'v2', child: Text('v2（新版服务端）')),
                  ],
                  onChanged: (value) async {
                    if (value == null || value == _apiVersion) return;
                    setState(() => _apiVersion = value);
                    await Constants.saveApiVersion(value);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('API 已切换为 $value，重新进入页面后生效')),
                      );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildChoiceTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          SegmentedButton<int>(
            segments: List.generate(
              options.length,
              (i) => ButtonSegment(
                value: i,
                label: Text(options[i], style: const TextStyle(fontSize: 12)),
              ),
            ),
            selected: {selectedIndex},
            onSelectionChanged: (v) => onSelected(v.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: danger ? Colors.red : null,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputTile({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: title,
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
