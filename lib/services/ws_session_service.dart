import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import '../utils/constants.dart';
import 'auth_service.dart';

class WsSessionService {
  static final WsSessionService _instance = WsSessionService._internal();
  factory WsSessionService() => _instance;
  WsSessionService._internal();

  final Dio _dio = Dio();
  final Ecdh _ecdh = Ecdh.p256(length: 32);
  SecretKey? _encKey;
  SecretKey? _macKey;
  Future<void>? _pendingHandshake;
  String? sessionId;

  Future<void> ensureReady() async {
    if (_encKey != null && _macKey != null && sessionId != null) return;
    if (_pendingHandshake != null) return _pendingHandshake!;
    _pendingHandshake = _handshake();
    try {
      await _pendingHandshake!;
    } finally {
      _pendingHandshake = null;
    }
  }

  Future<void> _handshake() async {
    final keyPair = await _ecdh.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final response = await _dio.post(
      '${Constants.baseUrl}${Constants.apiPath('/v1/auth/handshake')}',
      data: {'client_pub': base64Encode(publicKey.toDer())},
      options: Options(
        headers: {
          'Authorization': 'Bearer ${AuthService().token ?? ''}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final serverPub = EcPublicKey.parseDer(
      base64Decode(data['server_pub'].toString()),
      type: KeyPairType.p256,
    );
    final shared = await _ecdh.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: serverPub,
    );
    final sharedBytes = await shared.extractBytes();
    final encHash = await Sha256().hash([
      ...sharedBytes,
      ...utf8.encode('enc'),
    ]);
    final macHash = await Sha256().hash([
      ...sharedBytes,
      ...utf8.encode('mac'),
    ]);
    _encKey = SecretKey(encHash.bytes);
    _macKey = SecretKey(macHash.bytes);
    sessionId = data['session_id']?.toString();
    if (sessionId == null || sessionId!.isEmpty) {
      reset();
      throw StateError('握手响应缺少 session_id');
    }
  }

  Future<String?> decrypt(String raw) async {
    if (_encKey == null || _macKey == null) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map ||
        decoded['iv'] == null ||
        decoded['data'] == null ||
        decoded['mac'] == null)
      return null;
    try {
      final iv = base64Decode(decoded['iv'].toString());
      final ciphertext = base64Decode(decoded['data'].toString());
      final actualMac = base64Decode(decoded['mac'].toString());
      final mac = await Hmac.sha256().calculateMac([
        ...iv,
        ...ciphertext,
      ], secretKey: _macKey!);
      if (!_constantTimeEqual(actualMac, mac.bytes)) return null;
      final cipher = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
      final clear = await cipher.decrypt(
        SecretBox(ciphertext, nonce: iv, mac: Mac.empty),
        secretKey: _encKey!,
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var result = 0;
    for (var i = 0; i < left.length; i++) {
      result |= left[i] ^ right[i];
    }
    return result == 0;
  }

  void reset() {
    _encKey?.destroy();
    _macKey?.destroy();
    _encKey = null;
    _macKey = null;
    sessionId = null;
  }
}
