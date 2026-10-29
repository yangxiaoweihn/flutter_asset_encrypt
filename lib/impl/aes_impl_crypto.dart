import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

import '../logger.dart';
import 'aes_encrypt.dart';

final AesCrypto aesCrypto = AesImplCrypto();

/// encrypt库的实现 速度慢
class AesImplCrypto implements AesCrypto {
  static String generateRandomKey() {
    final enc.Key key = enc.Key.fromSecureRandom(32); // AES-256
    return key.base64;
  }

  /// 使用 AES 加密字节数据
  /// [ 16字节 IV ] [ 加密数据 ]
  @override
  Future<Uint8List> encryptBytes(
    Uint8List data,
    String pwd, {
    Uint8List? iv16,
    String mode = 'GCM',
    String? padding = 'PKCS7',
  }) async {
    final enc.Key key = enc.Key(Uint8List.fromList(base64.decode(pwd)));
    late enc.IV iv;
    if (iv16 == null) {
      // 随机 IV
      iv = enc.IV.fromSecureRandom(16);
    } else {
      iv = enc.IV.fromBase64(base64Encode(iv16));
    }

    final enc.AES algo = enc.AES(key, mode: parseMode(mode)!, padding: padding);
    final enc.Encrypter encrypter = enc.Encrypter(algo);

    final int $1 = DateTime.now().millisecondsSinceEpoch;
    final enc.Encrypted encrypted = encrypter.encryptBytes(data, iv: iv);
    final int $2 = DateTime.now().millisecondsSinceEpoch;
    Logger().debug('enc spend=${$2 - $1}, mode=$mode');
    final int encryptedLen = encrypted.bytes.length;
    // 将 IV 和密文一起存储：IV(16字节) + 密文
    final Uint8List combined = Uint8List(iv.bytes.length + encryptedLen)
      ..setAll(0, iv.bytes)
      ..setAll(iv.bytes.length, encrypted.bytes);
    return combined;
  }

  @override
  Future<Uint8List> decryptBytes(
    Uint8List data,
    String pwd, {
    String mode = 'GCM',
    String? padding = 'PKCS7',
  }) async {
    final enc.Key key = enc.Key(Uint8List.fromList(base64.decode(pwd)));
    final Uint8List combined = data;
    // 提取 IV（前16字节）
    final Uint8List ivBytes = combined.sublist(0, 16);
    final Uint8List encryptedBytes = combined.sublist(16);
    final enc.IV iv = enc.IV(ivBytes);

    final enc.AES algo = enc.AES(key, mode: parseMode(mode)!, padding: padding);
    final enc.Encrypter encrypter = enc.Encrypter(algo);

    final int $1 = DateTime.now().millisecondsSinceEpoch;
    final List<int> decrypted = encrypter.decryptBytes(
      enc.Encrypted(encryptedBytes),
      iv: iv,
    );
    final int $2 = DateTime.now().millisecondsSinceEpoch;
    Logger().debug('dec spend=${$2 - $1}, mode=$mode');
    return Uint8List.fromList(decrypted);
  }

  enc.AESMode? parseMode(String mode) {
    for (final MapEntry<enc.AESMode, String> entry in _modes.entries) {
      if (entry.value == mode) {
        return entry.key;
      }
    }
    return null;
  }

  String toBase64(Uint8List data) {
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
