import 'package:flutter/material.dart';

class ToolsHubPage extends StatelessWidget {
  final bool more;

  const ToolsHubPage({super.key, this.more = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final sections = more
        ? <({String label, IconData icon, String route})>[
            (label: '我的收藏', icon: Icons.star_outline, route: '/favorites'),
            (label: '签到墙', icon: Icons.event_available, route: '/checkin_wall'),
            (label: 'AI 助手', icon: Icons.smart_toy_outlined, route: '/ai_chat'),
            (label: '设置', icon: Icons.settings_outlined, route: '/settings'),
            (label: '关于 OldChat', icon: Icons.info_outline, route: '/about'),
          ]
        : <({String label, IconData icon, String route})>[
            (label: '动态', icon: Icons.dynamic_feed_outlined, route: '/moments'),
            (label: '资源广场', icon: Icons.folder_open, route: '/resource_plaza'),
            (label: '公开法庭', icon: Icons.gavel_outlined, route: '/public_court'),
            (label: '音乐广场', icon: Icons.music_note, route: '/music_plaza'),
            (label: '表情广场', icon: Icons.emoji_emotions_outlined, route: '/emoji_plaza'),
            (label: '通知', icon: Icons.notifications_none, route: '/notifications'),
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(more ? '更多' : '功能中心'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 112,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final item = sections[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, item.route),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 30, color: primary),
                    const SizedBox(height: 8),
                    Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
