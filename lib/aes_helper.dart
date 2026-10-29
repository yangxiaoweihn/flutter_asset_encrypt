import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

import 'impl/aes_encrypt.dart';
import 'impl/aes_impl_cryptography.dart';

final AesCrypto impl = aesAesImplCryptography;

class AESHelper {
  static String generateRandomKey() {
    final enc.Key key = enc.Key.fromSecureRandom(32); // AES-256
    return key.base64;
  }

  /// 使用 AES 加密字节数据
  /// [ 16字节 IV ] [ 加密数据 ]
  static Future<Uint8List> encryptBytes(
    Uint8List data,
    String pwd, {
    Uint8List? iv16,
    String mode = 'CTR',
    String? padding = 'PKCS7',
  }) async {
    return impl.encryptBytes(
      data,
      pwd,
      iv16: iv16,
      mode: mode,
      padding: padding,
    );
  }

  static Future<Uint8List> decryptBytes(
    Uint8List data,
    String pwd, {
    String mode = 'CTR',
    String? padding = 'PKCS7',
  }) async {
    return impl.decryptBytes(data, pwd, mode: mode, padding: padding);
  }

  static enc.AESMode? parseMode(String mode) {
    for (final MapEntry<enc.AESMode, String> entry in _modes.entries) {
      if (entry.value == mode) {
        return entry.key;
      }
    }
    return null;
  }

  static String toBase64(Uint8List data) {
    return base64Encode(data);
  }

  void ignore() {}
}

const Map<enc.AESMode, String> _modes = <enc.AESMode, String>{
  enc.AESMode.cbc: 'CBC',
  enc.AESMode.cfb64: 'CFB-64',
  enc.AESMode.ctr: 'CTR',
  enc.AESMode.ecb: 'ECB',
  enc.AESMode.ofb64Gctr: 'OFB-64/GCTR',
  enc.AESMode.ofb64: 'OFB-64',
  enc.AESMode.sic: 'SIC',
  enc.AESMode.gcm: 'GCM',
};
