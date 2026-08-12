import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../utils/url_helper.dart';
import 'aria2_service.dart';

class DownloadResult {
  final bool usedAria2;
  final String? gid;
  final String? path;

  const DownloadResult({this.usedAria2 = false, this.gid, this.path});
}

class DownloadProgress {
  final int received;
  final int total;
  final double? fraction;

  const DownloadProgress({required this.received, required this.total, required this.fraction});
}

class DownloadService {
  static bool _looksLikeJson(String value) {
    final trimmed = value.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  static String fileNameFromMessage(String? body, String? url) {
    final raw = (body ?? '').trim();
    final candidates = <String>[];
    if (raw.isNotEmpty) {
      candidates.add(raw);
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final key in const [
            'file_name',
            'filename',
            'name',
            'original_name',
            'title',
          ]) {
            final value = decoded[key];
            if (value != null && value.toString().trim().isNotEmpty) {
              candidates.add(value.toString());
            }
          }
          for (final key in const [
            'url',
            'media_url',
            'download_url',
            'file_url',
            'src',
          ]) {
            final value = decoded[key]?.toString().trim();
            if (value != null && value.isNotEmpty) {
              candidates.add(_nameFromUrl(value));
            }
          }
        }
      } catch (_) {}
    }
    for (final candidate in candidates) {
      final safe = _safeFileName(candidate);
      if (safe != null && !_looksLikeJson(candidate)) return safe;
    }
    return _nameFromUrl(url ?? '');
  }

  static Future<DownloadResult> download(
    String url, {
    String? fileName,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
    bool preferAria2 = false,
  }) async {
    final normalizedUrl = resolveMediaUrl(url);
    if (normalizedUrl.isEmpty) throw Exception('下载地址为空');
    final normalizedName = fileName != null
        ? fileNameFromMessage(fileName, normalizedUrl)
        : _nameFromUrl(normalizedUrl);

    if (preferAria2 && await Aria2Service().isConfigured) {
      try {
        final gid = await Aria2Service().addUri(
          normalizedUrl,
          fileName: normalizedName,
        );
        return DownloadResult(usedAria2: true, gid: gid);
      } catch (_) {}
    }

    final path = await _streamDownload(
      normalizedUrl,
      fileName: normalizedName,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return DownloadResult(path: path);
  }

  static Future<String?> saveWithDialog(String path, {String? fileName}) async {
    final source = File(path);
    if (!await source.exists()) throw Exception('下载文件不存在');
    final selected = await FilePicker.saveFile(
      dialogTitle: '保存文件',
      fileName: fileNameFromMessage(fileName, path),
      bytes: await source.readAsBytes(),
      lockParentWindow: true,
    );
    if (selected == null || selected.isEmpty) return null;
    await source.copy(selected);
    return selected;
  }

  static Future<String> _streamDownload(
    String url, {
    String? fileName,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final downloads = await _downloadsDirectory();
    await downloads.create(recursive: true);
    final name = _safeFileName(fileName) ?? _nameFromUrl(url);
    final target = await _uniqueFile(downloads, name);
    final token = AuthService().token;
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 30),
        headers: {
          'Accept': '*/*',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    ).get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        headers: {
          'Accept': '*/*',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );
    final total = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? -1;
    var received = 0;
    final sink = target.openWrite();
    try {
      onProgress?.call(DownloadProgress(received: 0, total: total, fraction: total > 0 ? 0 : null));
      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled == true) throw DioException.requestCancelled(requestOptions: response.requestOptions, reason: '下载已取消');
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received: received, total: total, fraction: total > 0 ? received / total : null));
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    return target.path;
  }

  static Future<Directory> _downloadsDirectory() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) return Directory('$home\\Downloads');
    }
    return Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}Downloads',
    );
  }

  static Future<File> _uniqueFile(Directory directory, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    var file = File('${directory.path}${Platform.pathSeparator}$name');
    var index = 1;
    while (await file.exists()) {
      file = File(
        '${directory.path}${Platform.pathSeparator}$stem ($index)$extension',
      );
      index++;
    }
    return file;
  }

  static String? _safeFileName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return null;
    final normalized = name.split(RegExp(r'[\\/]')).last;
    final safe = normalized
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return safe.isEmpty ? null : safe;
  }

  static String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    final candidate = path.split('/').last;
    final decoded = Uri.decodeComponent(candidate);
    return _safeFileName(decoded) ??
        'oldchat_download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }
}
