import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../utils/url_helper.dart';
import '../pages/moments_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _myMoments = [];
  bool _uploadingAvatar = false;
  final TextEditingController _friendUidController = TextEditingController();
  final TextEditingController _groupIdController = TextEditingController();

  int _extractOldCoinValue(Map<String, dynamic>? profile) {
    if (profile == null) return 0;
    final candidates = [
      'old_coin',
      'oldCoin',
      'oldcoin',
      'old_coins',
      'oldCoins',
      'coin',
      'coins',
      'coin_balance',
      'coinBalance',
      'balance',
      'wallet_balance',
      'walletBalance',
    ];
    for (final key in candidates) {
      final value = profile[key];
      if (value != null) {
        final parsed = _parseInt(value);
        if (parsed != null) return parsed;
      }
    }

    for (final nestedKey in ['wallet', 'account', 'stats', 'data']) {
      final nested = profile[nestedKey];
      if (nested is Map) {
        final nestedMap = Map<String, dynamic>.from(nested);
        final nestedValue = _extractOldCoinValue(nestedMap);
        if (nestedValue != 0) return nestedValue;
      }
    }

    return 0;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @override
  void dispose() {
    _friendUidController.dispose();
    _groupIdController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null) {
      setState(() {
        _error = '未登录';
        _loading = false;
      });
      return;
    }
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getMyProfile(),
        api.getUserMoments(uid, offset: 0, limit: 20),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>;
          _myMoments = (results[1]['moments'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              [];
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _updateAvatar() async {
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final file = File(result.path);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
      });
      final api = ApiService();
      await api.updateAvatar(formData);
      await _loadProfile();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('头像已更新')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _updateDisplayName(String newName) async {
    if (newName.trim().isEmpty) return;
    try {
      final api = ApiService();
      await api.updateProfile({'display_name': newName.trim()});
      setState(() {
        _profile?['display_name'] = newName.trim();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称已更新')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败: $e')));
    }
  }

  Future<void> _updateSignature(String newSignature) async {
    try {
      final api = ApiService();
      await api.updateProfile({'signature': newSignature.trim()});
      setState(() {
        _profile?['signature'] = newSignature.trim();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('签名已更新')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败: $e')));
    }
  }

  Future<void> _addFriend({String? uid}) async {
    String? targetUid = uid?.trim();
    if (targetUid == null || targetUid.isEmpty) {
      final controller = TextEditingController(text: _friendUidController.text);
      targetUid = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('添加好友'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入对方 UID',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('添加'),
            ),
          ],
        ),
      );
      controller.dispose();
    }
    final normalizedUid = targetUid?.trim();
    if (normalizedUid == null || normalizedUid.isEmpty) return;
    _friendUidController.clear();
    try {
      await ApiService().sendFriendRequest(normalizedUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('好友申请已发送')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }

  Future<void> _joinGroup({String? groupId}) async {
    String? targetGroupId = groupId?.trim();
    if (targetGroupId == null || targetGroupId.isEmpty) {
      final controller = TextEditingController(text: _groupIdController.text);
      targetGroupId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('加入群聊'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入群聊 ID',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('加入'),
            ),
          ],
        ),
      );
      controller.dispose();
    }
    final normalizedGroupId = targetGroupId?.trim();
    if (normalizedGroupId == null || normalizedGroupId.isEmpty) return;
    _groupIdController.clear();
    try {
      await ApiService().joinGroup(normalizedGroupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入群聊')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('个人主页', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
              icon: const Icon(Icons.photo_album, color: Colors.white),
              onPressed: () {
                final myUid = _profile?['uid'];
                if (myUid != null) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MomentsPage(uid: myUid)));
                } else {
                  Navigator.pushNamed(context, '/moments');
                }
              },
              tooltip: '我的动态'),
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadProfile),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('加载失败: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _loadProfile, child: const Text('重试')),
                      ]),
                )
              : _profile == null
                  ? const Center(child: Text('暂无数据'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildAvatarSection(primaryColor),
                          const SizedBox(height: 16),
                          _buildEditableField(
                              label: '昵称',
                              value: _profile!['display_name'] ??
                                  _profile!['username'] ??
                                  '未命名',
                              onSave: _updateDisplayName,
                              isTitle: true),
                          const SizedBox(height: 4),
                          _buildEditableField(
                              label: 'UID',
                              value: _profile!['uid'] ?? '',
                              onSave: (v) {},
                              readOnly: true,
                              textStyle: const TextStyle(
                                  fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 4),
                          _buildEditableField(
                              label: '签名',
                              value: _profile!['signature'] ?? '点击添加签名',
                              onSave: _updateSignature,
                              isBio: true),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.account_balance_wallet,
                                    color: Colors.orange),
                                const SizedBox(width: 8),
                                const Text('旧币数量',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text(
                                  '${_extractOldCoinValue(_profile)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              final myUid = _profile?['uid'];
                              if (myUid != null) {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            MomentsPage(uid: myUid)));
                              } else {
                                Navigator.pushNamed(context, '/moments');
                              }
                            },
                            icon: const Icon(Icons.photo_album),
                            label: const Text('查看我的动态'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: primaryColor,
                                side:
                                    BorderSide(color: primaryColor, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20))),
                          ),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildActionSection(
                            title: '添加好友',
                            child: Row(
                              children: [
                                Expanded(
                                    child: TextField(
                                        controller: _friendUidController,
                                        decoration: const InputDecoration(
                                            hintText: '输入对方 UID',
                                            border: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(20))),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10)),
                                        onSubmitted: (v) {
                                          if (v.trim().isNotEmpty) _addFriend(uid: v);
                                        })),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                    onPressed: () => _addFriend(uid: _friendUidController.text),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20))),
                                    child: const Text('添加')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildActionSection(
                            title: '加入群聊',
                            child: Row(
                              children: [
                                Expanded(
                                    child: TextField(
                                        controller: _groupIdController,
                                        decoration: const InputDecoration(
                                            hintText: '输入群聊 ID',
                                            border: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(20))),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10)),
                                        onSubmitted: (v) {
                                          if (v.trim().isNotEmpty) _joinGroup(groupId: v);
                                        })),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                    onPressed: () => _joinGroup(groupId: _groupIdController.text),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20))),
                                    child: const Text('加入')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildMomentsSection(primaryColor),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildAvatarSection(Color primaryColor) {
    final avatarUrl = _profile?['avatar_url'];
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _updateAvatar,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(resolveMediaUrl(avatarUrl))
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 46)
                : null,
            onBackgroundImageError: (_, __) {},
          ),
          if (!_uploadingAvatar)
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black.withOpacity(0.4)),
              child:
                  const Icon(Icons.camera_alt, color: Colors.white, size: 28),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildEditableField(
      {required String label,
      required String value,
      required Function(String) onSave,
      bool readOnly = false,
      bool isTitle = false,
      bool isBio = false,
      TextStyle? textStyle}) {
    return GestureDetector(
      onTap: readOnly
          ? null
          : () {
              final controller = TextEditingController(text: value);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('编辑$label'),
                  content: TextField(
                      controller: controller,
                      maxLines: isBio ? 3 : 1,
                      decoration: InputDecoration(
                          hintText: '请输入$label',
                          border: const OutlineInputBorder())),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onSave(controller.text);
                        },
                        child: const Text('保存')),
                  ],
                ),
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.grey.withOpacity(0.05)),
        child: Text(value.isNotEmpty ? value : '点击添加$label',
            style: textStyle ??
                (isTitle
                    ? const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)
                    : const TextStyle(fontSize: 14)),
            textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildActionSection({required String title, required Widget child}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      child,
    ]);
  }

  Widget _buildMomentsSection(Color primaryColor) {
    if (_myMoments.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('我的动态 (0)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(10)),
            child: const Center(
                child: Text('暂无动态', style: TextStyle(color: Colors.grey)))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('我的动态 (${_myMoments.length})',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(10)),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _myMoments.length > 3 ? 3 : _myMoments.length,
          separatorBuilder: (_, __) =>
              Divider(color: Colors.grey[200], height: 1),
          itemBuilder: (context, index) {
            final m = _myMoments[index];
            return ListTile(
              leading: const Icon(Icons.photo_album, color: Colors.orange),
              title: Text(m['body'] ?? '无内容'),
              subtitle: Text('喜欢 ${m['likes'] ?? 0}',
                  style: const TextStyle(fontSize: 12)),
              onTap: () {
                final myUid = _profile?['uid'];
                if (myUid != null) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MomentsPage(uid: myUid)));
                } else {
                  Navigator.pushNamed(context, '/moments');
                }
              },
            );
          },
        ),
      ),
      if (_myMoments.length > 3)
        TextButton(
          onPressed: () {
            final myUid = _profile?['uid'];
            if (myUid != null) {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => MomentsPage(uid: myUid)));
            } else {
              Navigator.pushNamed(context, '/moments');
            }
          },
          child: Text('查看全部 (${_myMoments.length})',
              style: TextStyle(color: primaryColor)),
        ),
    ]);
  }
}
