import '../utils/image_saver.dart';
import 'aria2_service.dart';

class DownloadResult {
  final bool usedAria2;
  final String? gid;
  final String? path;

  const DownloadResult({this.usedAria2 = false, this.gid, this.path});
}

class DownloadService {
  static Future<DownloadResult> download(String url, {String? fileName}) async {
    try {
      final gid = await Aria2Service().addUri(url, fileName: fileName);
      return DownloadResult(usedAria2: true, gid: gid);
    } catch (_) {
      final path = await ImageSaver.saveUrl(url, fileName: fileName);
      if (path == null || path.isEmpty) {
        throw Exception('默认下载方式保存失败');
      }
      return DownloadResult(path: path);
    }
  }
}
