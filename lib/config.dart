import 'dart:io';

import 'package:flutter_asset_collector/filter.dart';
import 'package:function_tree/function_tree.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

/// config_file= priority low
class Config {
  Config({
    this.type = 'default',
    required this.params,
  });

  // factory Config.fromArgResults(ArgResults results) {
  //   final Config config = Config(params: {});
  //   config.refresh();
  //   return config;
  // }

  static const String defaultOutput = 'fae_xxx';
  static const String defaultConfigFile = 'cfg_assets_encrypt.yaml';
  static const String defaultMode = 'GCM';
  static const String defaultPadding = 'PKCS7';

  final String type;
  final Map<String, dynamic> params;
  late String src;
  late String output;

  int? encBytesLength;

  /// 128 196 256 bits length
  late String? encKey;

  /// AES 运算模式
  late String mode;

  /// AES 填充模式
  late String padding;

  late bool isWatch;
  late YamlMap? configFileOptions;
  late String configFilePath;
  List<String>? inputRFiles;

  late bool dbgPubspec;

  Filter? filter;

  void refresh() {
    String src = params['src'] as String? ?? '.';

    src = absolute(src);
    src = normalize(src);

    final String? cfgFile = params['config_file'];
    configFilePath =
        join(src, (cfgFile?.isEmpty ?? true) ? defaultConfigFile : cfgFile!);
    final File configFile = File(configFilePath);

    String? outputDirName;
    List<String>? inputRFiles;
    bool? watch;
    int? encBytesLen;
    String? encKey;
    String? mode;
    String? padding;
    bool? dbgPubspec;

    YamlMap? yamlMap;
    if (configFile.existsSync()) {
      final String configFileText = configFile.readAsStringSync();
      filter = Filter(configFileText);
      yamlMap = loadYaml(configFileText) as YamlMap?;

      if (yamlMap != null) {
        outputDirName ??= yamlMap['output'] as String?;
        inputRFiles = (yamlMap['input_r_files'] as YamlList?)?.cast();
        watch = yamlMap['watch'] as bool? ?? false;

        encBytesLen = yamlMap['enc_bytes_len']?.toString().interpret().toInt();
        encKey = yamlMap['enc_key'] as String?;
        mode = yamlMap['enc_mode'] as String?;
        padding = yamlMap['enc_padding'] as String?;

        dbgPubspec = yamlMap['dbg_pubspec'] as bool?;
      }
    }

    outputDirName = params['output'] as String? ?? outputDirName;
    inputRFiles = (params['input_r_files'] as YamlList?)?.cast() ?? inputRFiles;

    watch = params['watch'] as bool? ?? watch;
    encBytesLen =
        params['enc_bytes_len']?.toString().interpret().toInt() ?? encBytesLen;
    encKey = params['enc_key'] as String? ?? encKey;
    mode = params['enc_mode'] as String? ?? mode;
    padding = params['enc_padding'] as String? ?? padding;

    final YamlList? include = params['include'] as YamlList?;
    final YamlList? exclude = params['exclude'] as YamlList?;
    if (null != include || null != exclude) {
      filter = Filter.create();
      filter!.replace(include: include, exclude: exclude);
    }

    dbgPubspec = params['dbg_pubspec'] as bool? ?? dbgPubspec;

    this.src = src;
    output = outputDirName ?? defaultOutput;
    isWatch = watch ?? false;
    configFileOptions = yamlMap;
    encBytesLength = encBytesLen;
    this.encKey = encKey;
    this.mode = mode ?? defaultMode;
    this.padding = padding ?? defaultPadding;

    this.dbgPubspec = dbgPubspec ?? false;

    if (null != inputRFiles) {
      this.inputRFiles = inputRFiles.map((String f) {
        return join(src, f);
      }).toList();
    }
  }

  @override
  String toString() {
    return 'Config{'
        'src: $src, output: $output, isWatch: $isWatch , config_file: $configFilePath , '
        'enc_bytes_len: $encBytesLength, mode: $mode , padding: $padding , '
        'inputRFiles: $inputRFiles , dbg_pubspec=$dbgPubspec'
        '}';
  }
}
