import 'dart:io';
import 'dart:typed_data';

import 'aes_simple.dart';

const int encryptLength = 300 * 1024;

/// [DataEncrypt#encryptBytes先要初始化]
/// 内部有个通用的缓存目录
/// 如果每个模块需要不同的缓存目录 则需要重新创建该类对象
/// 或者克隆该对象后设置缓存路径
final DataEncrypt commonDataEncrypt = DataEncrypt();

// [FIX] 顶层校验，供构造函数初始化列表使用
int _checkEncryptBytes(int v) {
  if (v < 0) {
    throw ArgumentError('encryptBytes 必须大于 0，当前: $v');
  }
  return v;
}

class DataEncrypt {
  String _key;
  int _encryptBytes;
  final Future<String>? cacheDirPath;

  DataEncrypt({
    String key = '',
    int encryptBytes = encryptLength,
    this.cacheDirPath,
  })  : _key = key,
        // [FIX] 构造时校验，避免 0/负数导致“只加头不加密”
        _encryptBytes = _checkEncryptBytes(encryptBytes);

  DataEncrypt clone({
    String? key,
    int? encryptBytes,
    Future<String>? cacheDirPath,
  }) {
    return DataEncrypt(
      key: key ?? _key,
      encryptBytes: encryptBytes ?? _encryptBytes,
      cacheDirPath: cacheDirPath,
    );
  }

  void setKey(String key) {
    _key = key;
  }

  String getKey() {
    return _key;
  }

  int getEncryptBytes() {
    return _encryptBytes;
  }

  void setEncryptBytes(int encryptBytes) {
    _encryptBytes = _checkEncryptBytes(encryptBytes);
  }

  String? _cacheDirPath;

  Future<String> _cacheDir() async {
    if (_cacheDirPath != null) {
      // [FIX] 目录不存在时创建，而不是直接返回
      final Directory d = Directory(_cacheDirPath!);
      if (!d.existsSync()) {
        await d.create(recursive: true);
      }
      return _cacheDirPath!;
    }

    // [FIX] cacheDirPath 为 null 时明确报错，避免 await null + 空断言崩溃
    if (cacheDirPath == null) {
      throw StateError(
        'DataEncrypt 未设置 cacheDirPath，且调用方未传 toPath',
      );
    }
    _cacheDirPath = await cacheDirPath;
    final Directory d = Directory(_cacheDirPath!);
    if (!d.existsSync()) {
      await d.create(recursive: true);
    }
    return _cacheDirPath!;
  }

  Future<String> getCacheDir() async {
    return _cacheDir();
  }

  void clearEncryptCache() {
    if (null != _cacheDirPath) {
      try {
        final Directory d = Directory(_cacheDirPath!);
        if (d.existsSync()) {
          d.deleteSync(recursive: true);
        }
      } catch (e) {}
    }
  }

  /// [FIX] 简单判断是否同一路径，防原地操作
  bool _isSameFile(String a, String b) {
    try {
      return File(a).absolute.path == File(b).absolute.path;
    } catch (_) {
      return a == b;
    }
  }

  /// [FIX] 缓存文件名加 path hash，降低不同目录同名文件互相覆盖
  String _cacheName(String path, String suffix) {
    final String name = path.split(Platform.pathSeparator).last;
    return '${path.hashCode.toRadixString(16)}_$name$suffix';
  }

  /// [FIX] 未加密分支的复制逻辑，统一用覆盖写入，且禁止原地复制
  Future<String> _copyOrReturn(
    File inputFile,
    String path,
    String? toPath,
  ) async {
    if (toPath == null) {
      return path;
    }
    if (_isSameFile(path, toPath)) {
      return path;
    }
    final File outputFile = File(toPath);
    await outputFile.parent.create(recursive: true);
    // File.copy 默认覆盖目标
    await inputFile.copy(toPath);
    return toPath;
  }

  Future<String> encryptFile(String path, {String? toPath}) async {
    final File inputFile = File(path);
    // [FIX] encryptBytes == 0 表示不加密，直接复制/返回原路径
    if (_encryptBytes == 0) {
      return _copyOrReturn(inputFile, path, toPath);
    }
    final int totalSize = await inputFile.length();

    // [FIX] 空文件不加密，直接输出空文件或返回原路径
    if (totalSize == 0) {
      return _copyOrReturn(inputFile, path, toPath);
    }

    // [FIX] 禁止原地加密
    if (toPath != null && _isSameFile(path, toPath)) {
      throw ArgumentError('toPath 不能与 path 相同: $path');
    }

    final RandomAccessFile raf = await inputFile.open();
    final Uint8List bytes = await raf.read(_encryptBytes);
    // 这是加密的一部分
    final Uint8List encryptedBytes = await AesPartSimple.encryptPartBytes(
      bytes,
      bytes.length,
      _key,
    );
    await raf.close();

    late File outputFile;
    if (null != toPath) {
      outputFile = File(toPath);
      // [FIX] 创建父目录
      await outputFile.parent.create(recursive: true);
    } else {
      final String tempDir = await _cacheDir();
      outputFile = File('$tempDir/${_cacheName(path, '.enc')}');
    }
    await outputFile.writeAsBytes(encryptedBytes);

    if (totalSize > _encryptBytes) {
      final Stream<List<int>> tailStream = inputFile.openRead(_encryptBytes);
      final IOSink outputSink = outputFile.openWrite(mode: FileMode.append);
      await tailStream.pipe(outputSink); // 自动逐块复制，关闭 sink
      await outputSink.close();
    }

    return outputFile.path;
  }

  /// 如果文件不是加密 会返回[path] 或者[toPath]
  /// 如果是加密的 会返回[toPath] 或者生成的缓存地址
  Future<String> maybeDecryptFile(String path, {String? toPath}) async {
    final File inputFile = File(path);

    final RandomAccessFile raf = await inputFile.open();
    final Uint8List lenBytes = await raf.read(8);

    final bool isEncrypt = AesPartSimple.isEncrypt(lenBytes);
    if (!isEncrypt) {
      await raf.close();
      if (toPath != null) {
        final File outputFile = File(toPath);
        await outputFile.parent.create(recursive: true);
        final Stream<List<int>> tailStream = inputFile.openRead(0);
        final IOSink outputSink = outputFile.openWrite(mode: FileMode.append);
        await tailStream.pipe(outputSink);
        return toPath;
      }
      return path;
    }

    await raf.setPosition(0);
    final int encryptLength = AesPartSimple.getEncryptedPartLen(lenBytes);
    final Uint8List encBytes = await raf.read(encryptLength);
    await raf.close();
    final Uint8List decryptedBytes = await AesPartSimple.decryptPartBytes(
      encBytes,
      _key,
    );

    late File outputFile;
    if (null != toPath) {
      outputFile = File(toPath);
      await outputFile.parent.create(recursive: true);
    } else {
      final String tempDir = await _cacheDir();
      outputFile = File('$tempDir/${_cacheName(path, '.dec')}');
    }

    await outputFile.writeAsBytes(decryptedBytes);

    final int totalSize = await inputFile.length();
    if (totalSize > encryptLength) {
      final Stream<List<int>> tailStream = inputFile.openRead(encryptLength);
      final IOSink outputSink = outputFile.openWrite(mode: FileMode.append);
      await tailStream.pipe(outputSink);
    }
    return outputFile.path;
  }

  Future<bool> judgeNeedDecrypt(File file) async {
    final File inputFile = file;
    final RandomAccessFile raf = await inputFile.open();
    final Uint8List lenBytes = await raf.read(8);

    final bool isEncrypt = AesPartSimple.isEncrypt(lenBytes);
    await raf.close();

    return isEncrypt;
  }

  Future<Uint8List?> maybeDecryptFileToUint8List(
    File file, {
    bool readFileOnNoDecrypt = true,
  }) async {
    return maybeDecryptFileToUint8List1(
      file,
      key: _key,
      readFileOnNoDecrypt: readFileOnNoDecrypt,
    );
  }

  static Future<Uint8List?> maybeDecryptFileToUint8List1(
    File file, {
    required String key,
    bool readFileOnNoDecrypt = true,
  }) async {
    final File inputFile = file;

    final RandomAccessFile raf = await inputFile.open();
    final Uint8List lenBytes = await raf.read(8);

    final bool isEncrypt = AesPartSimple.isEncrypt(lenBytes);
    if (!isEncrypt) {
      await raf.close();
      return readFileOnNoDecrypt ? inputFile.readAsBytes() : null;
    }

    await raf.setPosition(0);
    final int encryptLength = AesPartSimple.getEncryptedPartLen(lenBytes);
    final Uint8List encBytes = await raf.read(encryptLength);
    await raf.close();
    final Uint8List decryptedBytes = await AesPartSimple.decryptPartBytes(
      encBytes,
      key,
    );

    final int totalSize = await inputFile.length();

    if (totalSize <= encryptLength) {
      return decryptedBytes;
    }

    final int tailLength = totalSize - encryptLength;
    final Stream<List<int>> tailStream = inputFile.openRead(encryptLength);

    final Uint8List result = Uint8List(decryptedBytes.length + tailLength);

    result.setRange(0, decryptedBytes.length, decryptedBytes);

    int offset = decryptedBytes.length;
    await for (final List<int> chunk in tailStream) {
      final Uint8List bytes =
          chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      result.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
    }

    return result;
  }
}
