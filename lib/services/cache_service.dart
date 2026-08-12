import 'dart:convert';
import 'dart:typed_data';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const _locationKey = 'client_cache_directory';
  static const _encryptedMarker = 'dpapi:';

  String _defaultUserCacheRoot(String userId) {
    final documents = Platform.environment['USERPROFILE'] == null
        ? (Platform.environment['HOME'] ?? '.')
        : '${Platform.environment['USERPROFILE']}${Platform.pathSeparator}Documents';
    return '$documents${Platform.pathSeparator}OldChat_Documents${Platform.pathSeparator}$userId';
  }

  String _protect(String value) {
    if (!Platform.isWindows) return value;
    final input = utf8.encode(value);
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    final bytes = calloc<Uint8>(input.length);
    try {
      bytes.asTypedList(input.length).setAll(0, input);
      inBlob.ref.cbData = input.length;
      inBlob.ref.pbData = bytes;
      if (!CryptProtectData(inBlob, null, null, null, 0, outBlob).value) return value;
      final protectedBytes = outBlob.ref.pbData.asTypedList(outBlob.ref.cbData);
      return _encryptedMarker + base64Encode(protectedBytes);
    } finally {
      if (outBlob.ref.pbData != nullptr) LocalFree(HLOCAL(outBlob.ref.pbData));
      calloc.free(bytes);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  String _unprotect(String value) {
    if (!value.startsWith(_encryptedMarker) || !Platform.isWindows) return value;
    final input = base64Decode(value.substring(_encryptedMarker.length));
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    final bytes = calloc<Uint8>(input.length);
    try {
      bytes.asTypedList(input.length).setAll(0, input);
      inBlob.ref.cbData = input.length;
      inBlob.ref.pbData = bytes;
      if (!CryptUnprotectData(inBlob, null, null, null, 0, outBlob).value) return '';
      return utf8.decode(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
    } finally {
      if (outBlob.ref.pbData != nullptr) LocalFree(HLOCAL(outBlob.ref.pbData));
      calloc.free(bytes);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  String _userIdFromKey(String key) {
    const prefix = 'oldchat:';
    if (!key.startsWith(prefix)) return '';
    final rest = key.substring(prefix.length);
    final separator = rest.indexOf(':');
    return separator == -1 ? rest : rest.substring(0, separator);
  }

  String _safeFileName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<File> _fileForKey(String key) async {
    final userId = _userIdFromKey(key);
    final dir = await directory(userId: userId.isEmpty ? null : userId);
    return File('${dir.path}${Platform.pathSeparator}${_safeFileName(key)}.json.enc');
  }

  Future<void> writeJson(String key, Object value) async {
    final watch = Stopwatch()..start();
    final file = await _fileForKey(key);
    await file.writeAsString(_protect(jsonEncode(value)), flush: true);
    watch.stop();
    print('[缓存慢] 写入 ${watch.elapsedMilliseconds}ms ${file.path}');
  }

  Future<dynamic> readJson(String key) async {
    final watch = Stopwatch()..start();
    final file = await _fileForKey(key);
    String? encoded;
    if (await file.exists()) {
      encoded = await file.readAsString();
    } else {
      final prefs = await SharedPreferences.getInstance();
      encoded = prefs.getString(key);
      if (encoded != null && encoded!.isNotEmpty) {
        await file.writeAsString(encoded!, flush: true);
      }
    }
    final value = _unprotect(encoded ?? '');
    watch.stop();
    print('[缓存慢] 读取 ${watch.elapsedMilliseconds}ms ${file.path}');
    if (value.isEmpty) return null;
    return jsonDecode(value);
  }

  Future<void> remove(String key) async {
    final file = await _fileForKey(key);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  String scoped(String userId, String name) => 'oldchat:$userId:$name';

  Future<Directory> directory({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    if (configured.isNotEmpty) {
      final dir = Directory(configured);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final uid = (userId ?? prefs.getString('user_id') ?? 'guest').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final result = Directory(_defaultUserCacheRoot(uid));
    await result.create(recursive: true);
    return result;
  }

  Future<String> location({String? userId}) async => (await directory(userId: userId)).path;

  Future<void> ensureUserDirectory(String userId) async {
    await directory(userId: userId);
  }

  Future<void> setLocation(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, _protect(normalized));
    await Directory(normalized).create(recursive: true);
  }

  Future<int> sizeBytes() async {
    final roots = <Directory>{};
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    if (configured.isNotEmpty) {
      roots.add(Directory(configured));
    } else {
      final uid = (prefs.getString('user_id') ?? 'guest').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      roots.add(Directory(_defaultUserCacheRoot(uid)));
    }
    var total = 0;
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clear() async => clearClientCache();

  Future<int> get count async => await _countFiles();

  Future<int> _calculateSizeBytes() async {
    final root = await directory();
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<int> _countFiles() async {
    final root = await directory();
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total++;
    }
    return total;
  }

  Future<void> clearClientCache() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = _unprotect(prefs.getString(_locationKey)?.trim() ?? '');
    final userId = (prefs.getString('user_id') ?? 'guest')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final roots = <Directory>{
      Directory(configured.isNotEmpty ? configured : _defaultUserCacheRoot(userId)),
      Directory(_defaultUserCacheRoot('guest')),
      Directory(_defaultUserCacheRoot(userId)),
      await getTemporaryDirectory(),
      await getApplicationCacheDirectory(),
    };
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    final keys = prefs.getKeys().where((key) => key.startsWith('oldchat:')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<String> cacheDirectory({String? userId}) async => (await directory(userId: userId)).path;

  Future<void> setCacheLocation(String path) async => setLocation(path);
}
