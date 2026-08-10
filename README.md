# OldChat Desktop

一个面向 Windows 的桌面聊天客户端，基于 Flutter 构建，提供私聊、群聊、动态、收藏、AI 助手和多媒体消息等功能。

> 当前项目主要面向 **Windows Desktop**。

## 功能特性

- 私聊与群聊
- WebSocket 实时消息接收，并在断线时使用轮询兜底
- 未读消息与会话红点
- 消息引用、撤回、复制、@成员和右键菜单
- 聊天记录搜索
- 群成员列表与成员资料
- 动态发布、图片多选和图片浏览
- 图片、头像与视频缩略图缓存
- 视频缩略图预览、延迟加载播放器、浏览器打开和系统播放器打开
- 音频消息播放
- 文件下载，支持 Aria2；未配置 Aria2 时使用默认下载方式
- 收藏消息与收藏内容查看
- AI 助手、自定义 API URL、API Key 和模型选择
- AI 会话保存与侧边栏切换
- 粉色主题与主题切换
- 桌面通知、通知音、系统托盘和单实例运行
- 客户端缓存管理、缓存位置配置和 Windows DNS 缓存清理

## 技术栈

- Flutter / Dart
- Dio：HTTP 网络请求
- `web_socket_channel`：实时消息连接
- Provider：状态管理
- SharedPreferences：本地设置与轻量数据持久化
- `media_kit` / `video_player` / Chewie：视频播放
- `audioplayers`：音频播放
- `flutter_local_notifications`：桌面通知
- `window_manager` / `tray_manager`：Windows 窗口与系统托盘

## 环境要求

- Windows 10 或更高版本
- Flutter 3.44.7 或兼容的 Flutter 3.44.x 版本
- Dart 3.12.x
- Visual Studio 2022 或更高版本
- 安装 **Desktop development with C++** 工作负载
- Git

项目当前的 SDK 约束见 `file pubspec.yaml`。如果你使用其他 Flutter 版本，请先确认 Dart SDK 和依赖版本兼容。

## 获取项目

```bash
git clone https://github.com/Coloryi-MIAO/OldChat-For-Windows.git
cd oldchat_desktop
```

## 安装依赖

```bash
flutter pub get
```

项目包含 Windows 视频播放依赖的本地副本：

```text
pub.dev 的 `media_kit_libs_windows_video`（在线依赖）
```

请确保这个目录随仓库一起保留，不要只提交 `file pubspec.yaml` 而遗漏其中的插件文件和媒体库归档。

## 运行

```bash
flutter run -d windows
```

## 构建 Windows 版本

建议在 Windows 终端中执行：

```powershell
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
flutter pub get
flutter build windows --release
```

生成文件通常位于：

```text
build\windows\x64\runner\Release
```

如果出现 CMake 缓存来自其他电脑或其他目录的错误，先删除项目中的 `build` 目录，再重新执行构建。不要复制其他机器生成的 `build` 目录到当前项目。

如果 `media_kit_libs_windows_video` 报下载或校验错误，请确认：

1. 网络可以访问依赖下载地址；
2. 本地插件目录完整；
3. 已删除旧的 `build` 和 `windows\flutter\ephemeral` 后重新构建；
4. Flutter、Dart 与 `pubspec.lock` 使用的依赖版本匹配。

## 配置服务器

登录页支持配置 OldChat 服务地址。项目中的接口说明和路由说明见：

- `file api.md`
- `file client.md`
- `file routes.md`

不要把生产环境 Token、API Key、密码或其他凭据提交到 Git 仓库。

## AI 助手配置

AI 助手支持配置：

- API URL
- API Key
- 模型名称

自定义 AI 配置用于直接请求用户填写的模型服务，不应把请求发送到 OldChat 服务端。具体兼容格式取决于所使用的 AI 服务接口。

## 缓存说明

Windows 客户端默认按用户保存缓存，目录位于：

```text
C:\Users\<当前用户>\Documents\OldChat_Documents\<用户标识>
```

缓存用于保存会话、消息、图片、头像、视频缩略图及部分客户端数据。缓存文件可能包含用户数据，客户端会对需要保护的本地数据进行加密处理。

设置页提供：

- 查看缓存大小
- 清除客户端缓存
- 选择缓存目录
- 清除 Windows DNS 缓存

缓存大小统计以客户端缓存目录中的实际文件为准；Windows 资源管理器显示的“占用空间”和“大小”可能因文件系统簇大小、隐藏文件或系统缓存而不同。

## 开源协议

本项目采用 [MIT License](LICENSE)。

如果仓库中还没有 `LICENSE` 文件，请在项目根目录添加 MIT License 文件，并将年份和版权所有者替换为实际信息。

```text
MIT License

Copyright (c) 2026 <你的名字或组织>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 贡献

欢迎提交 Issue 和 Pull Request。提交代码前请确认：

```bash
flutter analyze
flutter test
```

请不要提交以下内容：

- `build/`
- `.dart_tool/`
- 本地 IDE 配置
- 用户缓存
- Token、密码和 API Key
- 机器相关的 CMake 缓存