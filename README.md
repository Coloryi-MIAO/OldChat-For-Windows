# OldChat Desktop

OldChat Desktop 是基于 Flutter 的 Windows 桌面聊天客户端，面向 OldChat 服务端提供私聊、群聊、动态、资源、音乐、表情和 AI 等功能。

> 当前只开发和支持 **Windows Desktop**。项目根目录的 `file api.md`、`file client.md` 和 `file routes.md` 是服务端接口与客户端协议的参考文档。

## 功能

### 聊天

- 私聊、群聊和 WebSocket 实时消息
- WebSocket 断线重连、增量同步、轮询兜底和未读消息
- 同一用户连续消息合并头像
- 长时间无消息时显示时间分隔线
- 消息撤回提示、引用、复制、搜索和右键菜单
- @成员、红包、消息状态和会话红点
- 发送文字、图片、视频、音频和文件
- 图片、头像、视频缩略图和媒体缓存

### 内容广场

- 动态发布、图片选择、浏览、评论、点赞和分页加载
- 资源广场的分区、上传、搜索、下载、收藏、点赞、评论和举报
- 音乐广场的搜索、播放、封面缓存、歌词和播放进度同步
- 表情广场的浏览、搜索、分页和缓存
- 收藏消息及图片、视频、文本和文件链接
- 公开法庭、签到墙和通知中心

### 账户与客户端

- 个人中心、好友、群组和成员资料管理
- 设置中心和客户端缓存管理
- AI 助手：自定义 API 地址、API Key、模型和本地会话
- HarmonyOS Sans SC 中文字体
- 粉色主题和其他主题设置
- Windows 系统通知、通知音、系统托盘和单实例运行
- Windows DNS 缓存清理

### 下载与更新

- 文件和媒体下载支持实时进度显示
- 支持取消下载
- 可选 Aria2 下载；未配置时使用客户端内置下载
- 软件内流式检查、下载和安装更新
- 更新前显示版本号、更新说明和下载进度
- Windows 更新安装完成后自动重启客户端

## 界面入口

主窗口顶部保留三个按钮：

- 刷新：刷新会话和未读消息
- 功能：打开功能中心
- 更多：打开更多功能中心

功能中心和更多中心使用独立页面，不依赖容易被窗口裁切的弹出菜单。个人中心和设置页面都提供红色“退出登录”入口。

## 技术栈

- Flutter / Dart
- Dio：HTTP 请求和流式下载
- `web_socket_channel`：WebSocket 实时通信
- Provider：状态管理
- SharedPreferences：设置和轻量本地数据
- `path_provider`：Windows 文件路径
- `video_player`、`media_kit`、`media_kit_video`、Chewie：视频播放
- `audioplayers`：音频播放
- `flutter_local_notifications`、`win_toast`：Windows 通知
- `window_manager`、`tray_manager`：窗口和系统托盘
- `webview_windows`、`webview_flutter`：网页内容
- `win32`、`ffi`：Windows 原生能力

## 环境要求

- Windows 10 或更高版本
- Flutter 3.44.x，或与项目约束兼容的版本
- Dart 3.10.x 或更高版本
- Visual Studio 2022 或更高版本
- Visual Studio 的 **Desktop development with C++** 工作负载
- Git

当前 SDK 和依赖约束以 `file pubspec.yaml` 为准。

## 获取项目

```bash
git clone https://github.com/Coloryi-MIAO/OldChat-For-Windows.git
cd oldchat_desktop
flutter pub get
```

## 开发运行

```bash
flutter run -d windows
```

常用检查命令：

```bash
flutter analyze
flutter test
```

## 构建 Windows 版本

建议在 Windows PowerShell 中使用干净的构建目录：

```powershell
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force windows\flutter\ephemeral -ErrorAction SilentlyContinue
flutter pub get
flutter build windows --release
```

构建结果通常位于：

```text
build\windows\x64\runner\Release
```

### 构建故障排查

如果出现 CMake 缓存来自其他电脑或其他目录的错误：

1. 删除项目中的 `build` 目录。
2. 删除 `windows\flutter\ephemeral`。
3. 重新执行 `flutter pub get`。
4. 再执行 `flutter build windows --release`。

不要复制其他电脑生成的 `build`、`.dart_tool` 或 `windows\flutter\ephemeral` 目录。

如果 `media_kit_libs_windows_video` 出现下载、校验或 CMake 错误，请确认网络可以访问 pub.dev，然后按上面的步骤清理并重新构建。项目不需要提交本地插件副本。

## 服务端配置

登录页支持填写 OldChat 服务地址。服务端相关文档：

- `file api.md`：接口、参数和响应格式
- `file client.md`：客户端协议与行为说明
- `file routes.md`：路由清单
- `file lua-cip.md`：Lua 相关协议说明

不要把生产环境 Token、密码、AI API Key 或其他凭据提交到 Git 仓库。

### 服务端路由概览

| 模块 | 路由范围 |
| --- | --- |
| 认证与连接 | `/v1/auth/*`、`GET /v1/ws`、`/v1/uploads/*` |
| 当前用户与设备 | `/v1/me`、`/v1/me/*`、`/v1/ai/*`、`/v1/chat/completions` |
| 好友与用户 | `/v1/users/profile`、`/v1/friends/*` |
| 私聊与红包 | `/v1/direct/*`、`/v1/chats/*`、`/v1/redpackets/*` |
| 群组与群消息 | `/v1/groups/*` |
| 动态 | `/v1/moments/*` |
| 资源广场 | `/v1/resources/*`、`/v1/me/resources/quota` |
| 表情广场 | `/v1/emoji/plaza/*` |
| 音乐广场 | `/v1/music/plaza/*`、`/v1/music/cover/*` |
| 收藏、举报与反馈 | `/v1/favorites/*`、`/v1/reports/*`、`/v1/feedback` |
| 通知 | `GET /v1/notifications` |
| Lua 小程序 | `/v1/discover/lua/*` |

主要接口包括：

```text
POST /v1/auth/register
POST /v1/auth/login
POST /v1/auth/refresh
POST /v1/auth/logout
GET  /v1/ws

GET  /v1/me
GET  /v1/friends
POST /v1/friends/request
POST /v1/friends/respond

POST /v1/direct/send
GET  /v1/direct/messages/v2
GET  /v1/direct/messages/search
POST /v1/direct/read

POST /v1/groups/create
POST /v1/groups/join
GET  /v1/groups/list
GET  /v1/groups/members
POST /v1/groups/message/send
GET  /v1/groups/messages/v2
GET  /v1/groups/messages/after

POST /v1/moments
GET  /v1/moments/v2
POST /v1/moments/like
POST /v1/moments/comment

POST /v1/resources/upload
GET  /v1/resources/items
GET  /v1/resources/search
POST /v1/resources/like
POST /v1/resources/comment
```

完整接口定义以项目内文档为准。

## AI 助手

AI 助手支持配置：

- API URL
- API Key
- 模型名称

AI 会话默认保存在本地，可以从侧边栏切换和管理。API Key 属于敏感信息，不要提交到仓库或写入日志。

## 缓存

Windows 客户端默认按用户保存缓存：

```text
C:\Users\<当前用户>\Documents\OldChat_Documents\<用户标识>
```

缓存可能包括：

- 会话和消息
- 图片、头像和视频缩略图
- 音乐封面和歌词数据
- 动态和表情广场数据
- 其他客户端设置

设置页提供：

- 查看客户端缓存大小
- 清除客户端缓存
- 选择缓存目录
- 清除 Windows DNS 缓存
- 开关系统通知和通知音

清除缓存不会删除服务端数据，但会移除本地登录后的缓存内容；重新打开相关页面时，客户端会重新从服务端加载。

## 项目结构

```text
lib/
├── main.dart                    应用入口、主题和路由
├── models/                      数据模型
├── pages/                       页面
├── services/                    网络、缓存、更新、音频和媒体服务
├── theme/                       主题定义
├── utils/                       工具类和消息解析
└── widgets/                    可复用组件

assets/                          字体、图标和图片资源
windows/                         Windows Runner 和构建配置
api.md                           API 文档
client.md                        客户端协议文档
routes.md                        服务端路由文档
```

## 安全与提交规范

不要提交：

- `build/`
- `.dart_tool/`
- `windows/flutter/ephemeral/`
- 用户缓存
- Token、密码、Cookie 和 API Key
- 机器相关的 CMake 缓存

更新 API、消息格式或服务端路由时，应同步检查 `file api.md`、`file client.md` 和 `file routes.md`。

## 开源协议

本项目采用 [MIT License](LICENSE)。

版权所有者：Coloryi