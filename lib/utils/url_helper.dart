import 'constants.dart';

/// 将相对路径补全为完整 URL
String resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  // 已经是完整 URL（http/https/data/blob）
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('data:') ||
      url.startsWith('blob:')) {
    return url;
  }
  // ★ 协议相对路径（如 //example.com/path）→ 补充 http:
  if (url.startsWith('//')) {
    return 'http:$url';
  }
  // 绝对路径（以 / 开头）或相对路径
  String base = Constants.baseUrl.endsWith('/')
      ? Constants.baseUrl.substring(0, Constants.baseUrl.length - 1)
      : Constants.baseUrl;
  String path = url.startsWith('/') ? url : '/$url';
  return base + path;
}
