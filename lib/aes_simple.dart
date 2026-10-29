import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'aes_helper.dart';

/// 简单的AES计算
/// 基于dart的大字节AES计算会超级慢 这里采取计算部分
class AesPartSimple {
  static const String magic = 'enc/';
  static final Uint8List _magicBytes = Uint8List.fromList(utf8.encode(magic));

  /// 魔数所占字节
  static const int magicNumberLen = 4;

  /// 加密内容长度所占字节
  static const int encHeaderLen = 4;

  /// 使用 AES 加密字节数据
  /// [ 4字节模数 ] [ 4字节 加密头部长度 ] [ 16字节 IV ] [ 加密数据（长度 = 加密头部长度） ] [ 剩余未加密数据 ]
  static Future<Uint8List> encryptPartBytes(
    Uint8List data,
    int encLength,
    String pwd, {
    String magic = magic,
    String mode = 'GCM',
    String? padding = 'PKCS7',
  }) async {
    final int base = data.offsetInBytes;
    final int totalLen = data.length;

    final int needEncLen = min(encLength, totalLen);
    final Uint8List needEncData = Uint8List.view(
      data.buffer,
      base,
      needEncLen,
    );

    final int leftLen = totalLen - needEncLen;
    final Uint8List leftData = leftLen > 0
        ? Uint8List.view(data.buffer, base + needEncLen, leftLen)
        : Uint8List(0);

    final Uint8List encrypted = await AESHelper.encryptBytes(
      needEncData,
      pwd,
      mode: mode,
      padding: padding,
    );

    final int encryptedLen = encrypted.length;
    // 加密头部长度 和密文一起存储：加密头部长度+IV(16字节) + 密文
    final Uint8List combined = Uint8List(
      magicNumberLen + encHeaderLen + encryptedLen + leftLen,
    );
    // 写入 magic（需确保长度匹配）
    final Uint8List magicBytes = Uint8List.fromList(utf8.encode(magic));
    if (magicBytes.length != magicNumberLen) {
      throw ArgumentError('magic 长度必须为 $magicNumberLen');
    }
    combined.setAll(0, magicBytes);

    // 写入加密长度
    final ByteData header = ByteData(encHeaderLen)
      ..setInt32(0, encryptedLen, Endian.little);
    combined.setAll(magicNumberLen, header.buffer.asUint8List());

    // 写入密文
    combined.setAll(magicNumberLen + encHeaderLen, encrypted);

    // 写入尾部（只有 leftLen > 0 时才拷贝）
    if (leftLen > 0) {
      combined.setAll(magicNumberLen + encHeaderLen + encryptedLen, leftData);
    }
    return combined;
  }

  /// 必须配合[encryptPartBytes]使用
  static Future<Uint8List> decryptPartBytes(
    Uint8List data,
    String pwd, {
    String mode = 'GCM',
    String? padding = 'PKCS7',
  }) async {
    final int base = data.offsetInBytes;
    final int encLen = ByteData.view(
      data.buffer,
      base + magicNumberLen,
      encHeaderLen,
    ).getUint32(0, Endian.little);

    final int totalSize = data.length;
    final int encryptedStart = base + magicNumberLen + encHeaderLen;
    final int encryptedEnd = encryptedStart + encLen;

    final Uint8List decrypted = await AESHelper.decryptBytes(
      Uint8List.view(data.buffer, encryptedStart, encLen),
      pwd,
      mode: mode,
      padding: padding,
    );
    final int decryptedLen = decrypted.length;
    final int tailLen = totalSize - encryptedEnd;
    final Uint8List tail = tailLen > 0
        ? Uint8List.view(data.buffer, encryptedEnd, tailLen)
        : Uint8List(0);

    return Uint8List(decryptedLen + tailLen)
      ..setAll(0, decrypted)
      ..setAll(decryptedLen, tail);
  }

  /// 获取加密头部的长度 只需要传递8个字节即可
  /// [ 4字节魔数 ] [ 4字节 加密头部长度 ] [ 16字节 IV ]
  static int getEncryptedPartLen(Uint8List data) {
    final int encLen = ByteData.view(
      data.buffer,
      magicNumberLen,
      encHeaderLen,
    ).getUint32(0, Endian.little);
    return 4 + 4 + encLen;
  }

  /// 通过魔数判断 4个字节即可
  static bool isEncrypt(Uint8List data) {
    if (data.length < magicNumberLen) {
      return false;
    }
    final Uint8List magicInData = Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      magicNumberLen,
    );
    // 逐字节比较
    for (int i = 0; i < magicNumberLen; i++) {
      if (magicInData[i] != _magicBytes[i]) {
        return false;
      }
    }
    return true;
  }

  void ignore() {}
}
