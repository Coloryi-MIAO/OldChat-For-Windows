import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/constants.dart';
import '../services/aria2_service.dart';
import '../services/theme_service.dart';
import '../services/cache_service.dart';
import '../services/diagnostics_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _aria2EndpointController = TextEditingController();
  final TextEditingController _aria2SecretController = TextEditingController();
  bool _isLoading = false;
  bool _isAria2Loading = false;
  String? _errorMessage;
  int _cacheBytes = 0;
  String _cachePath = '';

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = Constants.baseUrl;
    _loadAria2Settings();
    _loadCacheInfo();
  }

  Future<void> _loadAria2Settings() async {
    final settings = await Aria2Service().settings();
    if (!mounted) return;
    setState(() {
      _aria2EndpointController.text = settings['endpoint'] ?? Aria2Service.defaultEndpoint;
      _aria2SecretController.text = settings['secret'] ?? '';
    });
  }

  Future<void> _loadCacheInfo() async {
    final bytes = await CacheService().sizeBytes();
    final path = await CacheService().cacheDirectory();
    if (!mounted) return;
    setState(() {
      _cacheBytes = bytes;
      _cachePath = path;
    });
  }

  Future<void> _clearCache() async {
    await CacheService().clearClientCache();
    await _loadCacheInfo();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('客户端缓存已清除')));
  }

  Future<void> _chooseCacheLocation() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择客户端缓存目录');
    if (path == null || path.trim().isEmpty) return;
    await CacheService().setCacheLocation(path);
    await _loadCacheInfo();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存位置已保存')));
  }

  Future<void> _clearDns() async {
    await DiagnosticsService.clearDnsCache();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已尝试清除系统 DNS 缓存')));
  }

  Future<void> _saveAria2Settings() async {
    setState(() => _isAria2Loading = true);
    try {
      await Aria2Service().saveSettings(
        endpoint: _aria2EndpointController.text,
        secret: _aria2SecretController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('aria2 设置已保存')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) setState(() => _isAria2Loading = false);
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _aria2EndpointController.dispose();
    _aria2SecretController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    String url = _baseUrlController.text.trim();

    // 验证：不能为空
    if (url.isEmpty) {
      setState(() {
        _errorMessage = '服务器地址不能为空';
      });
      return;
    }

    // 验证：必须包含协议头
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() {
        _errorMessage = '地址必须以 http:// 或 https:// 开头';
      });
      return;
    }

    // 移除末尾斜杠
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
      _baseUrlController.text = url;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Constants.saveBaseUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存，请重启应用生效')),
      );
      // 延迟后退，让用户看到提示
      Future.delayed(const Duration(milliseconds: 800), () {
        // 重启应用
        _restartApp();
      });
    } catch (e) {
      setState(() {
        _errorMessage = '保存失败: $e';
        _isLoading = false;
      });
    }
  }

  void _restartApp() {
    // 退出到登录页并重新加载
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/',
      (route) => false,
    );
    // 重新加载应用
    // 由于 main.dart 中已经在 main() 里加载了 Constants，因此页面会重新获取新的 baseUrl
    // 但为了完全重启，我们使用一个简单方法：重新 runApp
    // 由于无法在这里直接 runApp，我们通知用户重启
    // 或使用上下文重新构建，但更干净的方式是调用 runApp
    // 这里我们使用一个技巧：跳转到一个空白页再返回，触发重建
    // 但更简单：提示用户手动重启
    // 我们已经在上面提示了 "请重启应用生效"
    // 所以这里只弹窗提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('需要重启'),
        content: const Text('服务器地址已修改，请手动重启应用以生效。\n(完全关闭再打开)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 返回登录页
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
            child: const Text('返回登录'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '服务器地址',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '修改后需要重启应用才能生效',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: InputDecoration(
                hintText: '例如: http://60.205.94.101:8080',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            const Text('外观主题', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Consumer<AppThemeController>(
              builder: (context, theme, _) => Card(
                child: SwitchListTile.adaptive(
                  value: theme.isPink,
                  onChanged: theme.setPink,
                  secondary: Icon(
                    theme.isPink ? Icons.favorite : Icons.water_drop,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('桃信粉色主题'),
                  subtitle: Text(theme.isPink ? '当前：桃信风格' : '当前：Blue Archive 蓝色主题'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('aria2 下载引擎', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('配置后，文件消息可交给本机 aria2 下载；默认 RPC 地址为 http://127.0.0.1:6800/jsonrpc。', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextField(controller: _aria2EndpointController, decoration: const InputDecoration(labelText: 'RPC 地址', prefixIcon: Icon(Icons.download_for_offline))),
            const SizedBox(height: 8),
            TextField(controller: _aria2SecretController, obscureText: true, decoration: const InputDecoration(labelText: 'RPC 密钥（可选）')),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isAria2Loading ? null : _saveAria2Settings,
                icon: const Icon(Icons.save),
                label: const Text('保存 aria2 设置'),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '当前地址: ${Constants.baseUrl}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            const SizedBox(height: 24),
            const Text('客户端缓存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('已缓存大小：${(_cacheBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
            Text('存储位置：$_cachePath', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _clearCache, icon: const Icon(Icons.delete_sweep), label: const Text('清除客户端缓存')),
              OutlinedButton.icon(onPressed: _clearDns, icon: const Icon(Icons.dns), label: const Text('清除系统 DNS 缓存')),
              OutlinedButton.icon(onPressed: _chooseCacheLocation, icon: const Icon(Icons.folder_open), label: const Text('选择缓存位置')),
            ]),
          ],
        ),
        ),
      ),
    );
  }
}
