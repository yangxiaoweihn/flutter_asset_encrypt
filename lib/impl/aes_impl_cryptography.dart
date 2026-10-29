import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../logger.dart';
import 'aes_encrypt.dart';

final AesCrypto aesAesImplCryptography = AesImplCryptography();

/// cryptography库的实现 快
/// 部分模式可能有问题 需要的时候再调
class AesImplCryptography implements AesCrypto {
  /// 生成随机的 256 位密钥，以 Base64 字符串返回
  static String generateRandomKey() {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// 加密字节数据
  /// 返回格式：`[ IV (16字节) ] + [ 密文 ]`（GCM 等模式下密文末尾附带 16 字节认证标签）
  @override
  Future<Uint8List> encryptBytes(
    Uint8List data,
    String pwd, {
    Uint8List? iv16,
    String mode = 'GCM',
    // 仅对 CBC、ECB 有效，其他模式忽略
    String? padding = 'PKCS7',
  }) async {
    // 1. 解析密钥
    final Uint8List keyBytes = base64.decode(pwd);
    final Cipher algorithm =
        _createAlgorithm(mode, keyBytes.length * 8, padding);

    // 2. 生成随机 IV（Nonce），长度固定为 16 字节（与旧版兼容）

    final Uint8List iv = iv16 ?? Uint8List(16);
    if (iv16 == null) {
      final Random random = Random.secure();
      for (int i = 0; i < iv.length; i++) {
        iv[i] = random.nextInt(256);
        iv[i] = 0;
      }
    }

    // 3. 执行加密（同步）
    final SecretKey secretKey = SecretKey(keyBytes);
    final int $1 = DateTime.now().millisecondsSinceEpoch;
    final SecretBox secretBox = await algorithm.encrypt(
      data,
      secretKey: secretKey,
      nonce: iv,
    );
    final int $2 = DateTime.now().millisecondsSinceEpoch;
    Logger().debug('enc spend=${$2 - $1}, mode=$mode');

    // 4. 组装输出：IV + 密文 + MAC（如果有）
    final List<int> cipherText = secretBox.cipherText;
    final Mac mac = secretBox.mac;
    final Uint8List combined = Uint8List(
      iv.length + cipherText.length + mac.bytes.length,
    );
    combined.setAll(0, iv);
    combined.setAll(iv.length, cipherText);
    if (mac.bytes.isNotEmpty) {
      combined.setAll(iv.length + cipherText.length, mac.bytes);
    }
    return combined;
  }

  /// 解密字节数据（格式与 [encryptBytes] 输出一致）
  @override
  Future<Uint8List> decryptBytes(
    Uint8List data,
    String pwd, {
    String mode = 'GCM',
    String? padding = 'PKCS7',
  }) async {
    // 1. 解析密钥
    final Uint8List keyBytes = base64.decode(pwd);
    final Cipher algorithm = _createAlgorithm(
      mode,
      keyBytes.length * 8,
      padding,
    );

    // 2. 提取 IV（前 16 字节）
    final Uint8List iv = data.sublist(0, 16);
    final Uint8List remaining = data.sublist(16);

    // 3. 根据算法确定 MAC 长度
    final int macLength = algorithm.macAlgorithm.macLength;
    Uint8List cipherText;
    Uint8List macBytes;
    if (macLength > 0) {
      Logger().debug('has mac');
      // 有 MAC（如 GCM）：末尾取 macLength 字节作为 MAC
      macBytes = remaining.sublist(remaining.length - macLength);
      cipherText = remaining.sublist(0, remaining.length - macLength);
    } else {
      // 无 MAC（如 CTR、CBC）
      macBytes = Uint8List(0);
      cipherText = remaining;
    }

    // 4. 构造 SecretBox 并解密
    final SecretKey secretKey = SecretKey(keyBytes);
    final SecretBox secretBox = SecretBox(
      cipherText,
      nonce: iv,
      mac: macBytes.isEmpty ? Mac.empty : Mac(macBytes),
    );
    final int $1 = DateTime.now().millisecondsSinceEpoch;
    final List<int> decrypted = await algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    final int $2 = DateTime.now().millisecondsSinceEpoch;
    Logger().debug('dec spend=${$2 - $1}, mode=$mode');
    return Uint8List.fromList(decrypted);
  }

  // -------------------- 内部辅助 --------------------

  /// 根据模式和密钥位数创建对应的算法实例

  Cipher _createAlgorithm(
    String mode,
    int keyLengthBits,
    String? padding,
  ) {
    final int keyLengthBytes = keyLengthBits ~/ 8;
    if (![16, 24, 32].contains(keyLengthBytes)) {
      throw ArgumentError('密钥长度必须是 128/192/256 位');
    }

    // 根据模式创建对应的算法实例，并转换为同步版本（支持 encryptSync/decryptSync）
    switch (mode.toUpperCase()) {
      case 'CTR':
        print('CTR mode');
        final AesCtr algorithm = _createAesCtr(keyLengthBits);
        return algorithm; // 返回同步实例 (DartAesCtr)

      case 'GCM':
        final AesGcm algorithm = _createAesGcm(16 * 8);
        return algorithm.toSync(); // 返回同步实例 (DartAesGcm)

      case 'CBC':
        final AesCbc algorithm = _createAesCbc(keyLengthBits, padding!);
        return algorithm.toSync(); // 返回同步实例 (DartAesCbc)

      default:
        throw ArgumentError('不支持的加密模式: $mode');
    }
  }

// ---------- 辅助创建函数 ----------

  AesCtr _createAesCtr(int keyLengthBits) {
    print(':::: $keyLengthBits');
    switch (keyLengthBits) {
      case 128:
        return AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);
      case 192:
        return AesCtr.with192bits(macAlgorithm: MacAlgorithm.empty);
      case 256:
        return AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      default:
        throw ArgumentError('不支持的密钥长度: $keyLengthBits');
    }
  }

  AesGcm _createAesGcm(int nonceLength) {
    switch (nonceLength) {
      case 128:
        return AesGcm.with128bits(
          nonceLength: nonceLength,
        );
      case 192:
        return AesGcm.with192bits(
          nonceLength: nonceLength,
        );
      case 256:
        return AesGcm.with256bits(
          nonceLength: nonceLength,
        );
      default:
        throw ArgumentError('不支持的密钥长度: $nonceLength');
    }
  }

  AesCbc _createAesCbc(int keyLengthBits, String padding) {
    // 将字符串 padding 转换为 PaddingScheme
    final PaddingAlgorithm paddingScheme = _parsePadding(padding);

    switch (keyLengthBits) {
      case 128:
        return AesCbc.with128bits(
          macAlgorithm: MacAlgorithm.empty,
          paddingAlgorithm: paddingScheme,
        );
      case 192:
        return AesCbc.with192bits(
          macAlgorithm: MacAlgorithm.empty,
          paddingAlgorithm: paddingScheme,
        );
      case 256:
        return AesCbc.with256bits(
          macAlgorithm: MacAlgorithm.empty,
          paddingAlgorithm: paddingScheme,
        );
      default:
        throw ArgumentError('不支持的密钥长度: $keyLengthBits');
    }
  }

  PaddingAlgorithm _parsePadding(String padding) {
    switch (padding.toUpperCase()) {
      case 'PKCS7':
        return PaddingAlgorithm.pkcs7;
      case 'PKCS5':
        return PaddingAlgorithm.pkcs7;
      // case 'ISO9797':
      //   return PaddingAlgorithm.iso9797;
      // case 'ISO7816':
      //   return PaddingAlgorithm.iso7816;
      // case 'X923':
      //   return PaddingAlgorithm.x923;
      case 'ZEROS':
        return PaddingAlgorithm.zero;
      case 'NONE':
        return PaddingAlgorithm.zero;
      default:
        throw ArgumentError('不支持的填充模式: $padding');
    }
  }
}
