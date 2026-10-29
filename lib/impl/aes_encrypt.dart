import 'dart:typed_data';

abstract class AesCrypto {

  Future<Uint8List> encryptBytes(
    Uint8List data,
    String pwd, {
    Uint8List? iv16,
    String mode = 'GCM',
    // 仅对 CBC、ECB 有效，其他模式忽略
    String? padding = 'PKCS7',
  });

  Future<Uint8List> decryptBytes(
    Uint8List data,
    String pwd, {
    String mode = 'GCM',
    // 仅对 CBC、ECB 有效，其他模式忽略
    String? padding = 'PKCS7',
  });
}
