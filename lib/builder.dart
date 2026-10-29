import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

import 'assets_executor.dart';
import 'config.dart';

Builder assetsEncryptBuilder(BuilderOptions options) {
  final Map<String, dynamic> p = options.config.map((String k, dynamic v) {
    // print('options: $k -> $v');
    if (v is YamlMap) {
      return MapEntry<String, dynamic>(
        k,
        v.map((dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v)),
      );
    } else {
      return MapEntry<String, dynamic>(k, v);
    }
  });

  log.info('asset_encrypt: config is=$p');

  return AssetsEncryptBuilder(p);
}

const String _m = '.dart_tool/generated/.assets_encrypt_trigger_cache.dart';

class AssetsEncryptBuilder implements Builder {
  AssetsEncryptBuilder(this.params) {
    builders = params.entries.map((MapEntry<String, dynamic> entry) {
      final Config config = Config(params: entry.value, type: entry.key)
        ..refresh();
      return AssetsExecutor(config);
    }).toList();

    if (builders.isEmpty) {
      log.info('asset_encrypt: params is empty, set a default builder.');
      builders = [
        AssetsExecutor(Config(params: <String, dynamic>{})..refresh()),
      ];
    }
  }

  /// 做了分类
  final Map<String, dynamic> params;
  late List<AssetsExecutor> builders;

  static int _buildCount = 0;

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    _buildCount++;
    print('🏗️  build-count: $_buildCount');

    final timestamp = DateTime.now().toIso8601String();
    final buildId = '${_buildCount}_${DateTime.now().millisecondsSinceEpoch}';

    // 生成构建信息
    final AssetId output = AssetId(buildStep.inputId.package, _m);

    await buildStep.writeAsString(output, '''
// GENERATED - Build #$_buildCount
// Build ID: $buildId
// Timestamp: $timestamp

class BuildInfo {
  static const int count = $_buildCount;
  static const String id = '$buildId';
  static const String timestamp = '$timestamp';
}
    ''');

    for (final AssetsExecutor builder in builders) {
      final File logFile = AssetsExecutor.getLogFile(builder.config);
      if (logFile.existsSync()) {
        logFile.deleteSync();
      }
    }

    for (final AssetsExecutor builder in builders) {
      await builder.collectAssetsAndEncrypt();
    }
    return Future<void>.value();
  }

  @override
  Map<String, List<String>> get buildExtensions => <String, List<String>>{
        'pubspec.yaml': <String>[_m],
      };
}
